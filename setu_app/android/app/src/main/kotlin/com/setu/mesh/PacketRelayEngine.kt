package com.setu.mesh

import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import org.json.JSONObject

/**
 * Minimal native relay engine — dedup + TTL check + rebroadcast, done
 * entirely in Kotlin so relay keeps working even when the Flutter/Dart
 * engine isn't attached (app backgrounded or killed).
 *
 * This does NOT replace the Dart-side PacketService — Dart still owns the
 * full packet model, UI display, and backend-upload decision. This native
 * copy only does the minimum needed to keep packets physically moving
 * through the mesh while nobody's looking at the screen.
 *
 * FIX: field keys were camelCase ("packetId", "hopCount") but the actual
 * frozen packet spec (mesh_packet.dart toJson()) uses snake_case
 * ("packet_id", "hop_count"). This meant packetId always read as "",
 * so every real packet was silently dropped as "already seen" before
 * relay logic even ran. Corrected to match the real wire format.
 *
 * LOCATION-AWARE RE-ENTRY (Aug 4 2026, per team ideation): plain
 * packet-id dedup means a device that already relayed a given packet
 * once will never relay it again, even if it's since moved somewhere
 * that would make it a genuinely useful relay for a NEW cluster of
 * nearby devices forming around the same incident. Pure "seen once,
 * ignore forever" is the safe default (prevents relay storms/loops)
 * but is unnecessarily strict for a device that's physically moved.
 *
 * Fix: track not just "seen" but "seen at roughly this location". If
 * the same packet_id shows up again AND this device's position has
 * drifted more than RELAY_REENTRY_DISTANCE_METERS since it last saw
 * that packet, treat it as eligible for relay again instead of
 * dropping it. Devices that haven't moved keep the original
 * loop-preventing behavior exactly as before.
 *
 * SEP 2026 — three additions, all additive. The existing seen-cache and
 * its behaviour are untouched; nothing here replaces the dedup system.
 *
 *  1. COUNTERS (PRIORITY 1). totalProcessed / duplicatesFiltered /
 *     relaySuppressed are read up into Dart's MeshMetrics through
 *     MeshChannelHandler's "getRelayStats". Duplicates are filtered here,
 *     before Dart ever sees them, so this is the ONLY place a real
 *     duplicate rate can be measured.
 *
 *  2. ADAPTIVE TTL (PRIORITY 3), mirroring mesh/services/adaptive_ttl.dart.
 *     A relayed packet loses 1 TTL normally and 2 when it is stale and
 *     not CRITICAL. It never loses less than 1, and TTL is clamped to
 *     MAX_TTL on the way in, so a packet claiming ttl=9999 gets the
 *     ceiling rather than unlimited propagation. Critical packets keep
 *     the old flat behaviour exactly.
 *
 *  3. ECHO ACCOUNTING (PRIORITY 4). Duplicates arriving inside a short
 *     window are counted per packet id, so MeshForegroundService can ask
 *     "did my neighbours already flood this?" before spending a
 *     rebroadcast. The engine only counts; the decision and the delay
 *     live in the service, which owns the Handler.
 */
class PacketRelayEngine(private val maxCacheSize: Int = 500) {
    private val seen = LinkedHashSet<String>()

    // packetId -> (lat, lon) this device was at when it last saw that
    // packet. Only populated when a location reading is available;
    // packets seen before any location update behave exactly as the
    // original packet-id-only dedup (no regression for devices that
    // never call updateDeviceLocation()).
    private val seenAtLocation = LinkedHashMap<String, Pair<Double, Double>>()

    /** packetId -> timestamps (ms) at which a DUPLICATE copy arrived. */
    private val echoTimestamps = LinkedHashMap<String, MutableList<Long>>()

    // ---- counters, read by MeshForegroundService.relayStats() ----
    @Volatile
    var totalProcessed: Long = 0L
        private set

    @Volatile
    var duplicatesFiltered: Long = 0L
        private set

    @Volatile
    var relaySuppressed: Long = 0L
        private set

    fun noteSuppressedRelay() { relaySuppressed++ }

    companion object {
        private const val EARTH_RADIUS_METERS = 6_371_000.0
        const val RELAY_REENTRY_DISTANCE_METERS = 150.0

        /** Must stay in sync with SecurityConstants.maxTTL (Dart). */
        const val MAX_TTL = 5

        /**
         * Mirrors AdaptiveTtl.staleAgeFraction * maxPacketAge in Dart:
         * 60% of the 5-minute maximum accepted packet age. A packet older
         * than this is not expired (PacketValidator still owns expiry, and
         * this does not bypass it) — it is just no longer worth a full
         * hop budget unless it is critical.
         */
        const val STALE_AFTER_MS = 180_000L

        /** How long a duplicate still counts as an "echo" of our own
         * pending rebroadcast. Deliberately short: this is about one
         * burst, not about history. */
        const val ECHO_WINDOW_MS = 1_500L

        private fun haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
            val phi1 = Math.toRadians(lat1)
            val phi2 = Math.toRadians(lat2)
            val dPhi = Math.toRadians(lat2 - lat1)
            val dLambda = Math.toRadians(lon2 - lon1)
            val a = sin(dPhi / 2).let { it * it } +
                cos(phi1) * cos(phi2) * sin(dLambda / 2).let { it * it }
            val c = 2 * atan2(sqrt(a), sqrt(1 - a))
            return EARTH_RADIUS_METERS * c
        }

        /**
         * Parses the packet's ISO-8601 `timestamp` into epoch millis.
         *
         * SimpleDateFormat rather than java.time.Instant on purpose: the
         * module's minSdk comes from Flutter and java.time needs API 26
         * or core-library desugaring, neither of which this build
         * guarantees. Returns null on anything unparseable, and a null
         * age always means "treat as fresh" — missing information must
         * never make TTL handling more aggressive.
         */
        fun parseTimestampMillis(raw: String?): Long? {
            if (raw.isNullOrEmpty()) return null
            val patterns = arrayOf(
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                "yyyy-MM-dd'T'HH:mm:ss'Z'",
                "yyyy-MM-dd'T'HH:mm:ss.SSS",
                "yyyy-MM-dd'T'HH:mm:ss"
            )
            for (pattern in patterns) {
                try {
                    val format = SimpleDateFormat(pattern, Locale.US)
                    if (pattern.endsWith("'Z'")) {
                        format.timeZone = TimeZone.getTimeZone("UTC")
                    }
                    return format.parse(raw)?.time
                } catch (_: Exception) {
                    // try the next pattern
                }
            }
            return null
        }

        /**
         * Native mirror of AdaptiveTtl.nextTtl (Dart).
         *
         * Invariants, identical to the Dart side:
         *   result <= MAX_TTL always, even for a hostile ttl=9999;
         *   result < currentTtl always, so nothing propagates forever;
         *   result >= 0.
         */
        fun nextTtl(currentTtl: Int, priority: String?, ageMillis: Long?): Int {
            var ttl = currentTtl
            if (ttl > MAX_TTL) ttl = MAX_TTL
            if (ttl <= 0) return 0

            val isCritical = priority != null && priority.equals("critical", ignoreCase = true)
            var decrement = 1
            if (!isCritical && ageMillis != null && ageMillis >= STALE_AFTER_MS) {
                decrement += 1
            }

            val next = ttl - decrement
            if (next <= 0) return 0
            val ceiling = if (MAX_TTL < ttl - 1) MAX_TTL else ttl - 1
            return if (next > ceiling) ceiling else next
        }
    }

    /**
     * [packetId] is exposed so the caller can consult echo accounting for
     * this packet before actually spending a rebroadcast.
     */
    data class RelayResult(
        val isNew: Boolean,
        val relayBytes: ByteArray?,
        val packetId: String? = null,
        val isCritical: Boolean = false
    )

    fun process(bytes: ByteArray, currentLat: Double? = null, currentLon: Double? = null): RelayResult {
        totalProcessed++

        val json: JSONObject
        try {
            json = JSONObject(String(bytes))
        } catch (e: Exception) {
            return RelayResult(isNew = false, relayBytes = null)
        }

        val packetId = json.optString("packet_id", "")
        if (packetId.isEmpty()) {
            return RelayResult(isNew = false, relayBytes = null)
        }

        if (seen.contains(packetId)) {
            // Record the echo BEFORE deciding, so a rebroadcast that is
            // still sitting in its jitter window can see it.
            noteEcho(packetId)

            val eligibleForReentry = hasMovedSignificantly(packetId, currentLat, currentLon)
            if (!eligibleForReentry) {
                duplicatesFiltered++
                return RelayResult(isNew = false, relayBytes = null, packetId = packetId)
            }
            // Falls through to relay again — location changed enough
            // that this device is being treated as a fresh relay
            // opportunity for this packet, not a loop.
        } else {
            remember(packetId)
        }

        if (currentLat != null && currentLon != null) {
            rememberLocation(packetId, currentLat, currentLon)
        }

        val priority = json.optString("priority", "").ifEmpty { null }
        val isCritical = priority != null && priority.equals("critical", ignoreCase = true)

        val ttl = json.optInt("ttl", 0)
        if (ttl <= 0) {
            return RelayResult(isNew = true, relayBytes = null, packetId = packetId, isCritical = isCritical)
        }

        val sentAt = parseTimestampMillis(json.optString("timestamp", "").ifEmpty { null })
        val ageMillis = if (sentAt == null) null else (System.currentTimeMillis() - sentAt).coerceAtLeast(0L)

        val newTtl = nextTtl(ttl, priority, ageMillis)
        if (newTtl <= 0) {
            return RelayResult(isNew = true, relayBytes = null, packetId = packetId, isCritical = isCritical)
        }

        json.put("ttl", newTtl)
        json.put("hop_count", json.optInt("hop_count", 0) + 1)
        return RelayResult(
            isNew = true,
            relayBytes = json.toString().toByteArray(),
            packetId = packetId,
            isCritical = isCritical
        )
    }

    fun rememberOriginated(packetId: String) = remember(packetId)

    /**
     * How many duplicate copies of [packetId] arrived within the last
     * [ECHO_WINDOW_MS]. MeshForegroundService uses this to decide whether
     * its own pending rebroadcast is still worth sending.
     */
    fun recentEchoCount(packetId: String, now: Long = System.currentTimeMillis()): Int {
        val stamps = echoTimestamps[packetId] ?: return 0
        stamps.removeAll { now - it > ECHO_WINDOW_MS }
        if (stamps.isEmpty()) {
            echoTimestamps.remove(packetId)
            return 0
        }
        return stamps.size
    }

    private fun noteEcho(packetId: String, now: Long = System.currentTimeMillis()) {
        val stamps = echoTimestamps.getOrPut(packetId) { mutableListOf() }
        stamps.removeAll { now - it > ECHO_WINDOW_MS }
        stamps.add(now)
        if (echoTimestamps.size > maxCacheSize) {
            echoTimestamps.remove(echoTimestamps.keys.first())
        }
    }

    private fun hasMovedSignificantly(packetId: String, currentLat: Double?, currentLon: Double?): Boolean {
        if (currentLat == null || currentLon == null) return false
        val lastSeenAt = seenAtLocation[packetId] ?: return false
        val distance = haversineMeters(lastSeenAt.first, lastSeenAt.second, currentLat, currentLon)
        return distance > RELAY_REENTRY_DISTANCE_METERS
    }

    private fun remember(packetId: String) {
        if (seen.size >= maxCacheSize) {
            val oldest = seen.iterator().next()
            seen.remove(oldest)
            seenAtLocation.remove(oldest)
            echoTimestamps.remove(oldest)
        }
        seen.add(packetId)
    }

    private fun rememberLocation(packetId: String, lat: Double, lon: Double) {
        if (seenAtLocation.size >= maxCacheSize) {
            seenAtLocation.remove(seenAtLocation.keys.first())
        }
        seenAtLocation[packetId] = Pair(lat, lon)
    }
}
