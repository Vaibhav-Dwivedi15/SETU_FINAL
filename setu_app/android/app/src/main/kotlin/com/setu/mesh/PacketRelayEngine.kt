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
 *
 * SEP 21 2026 (Vib, native-mesh hardening pass): [seen], [seenAtLocation]
 * and [echoTimestamps] were plain, non-thread-safe LinkedHashSet/
 * LinkedHashMap, and [totalProcessed]/[duplicatesFiltered]/
 * [relaySuppressed] were @Volatile but incremented with a plain, non-
 * atomic `++`. Nothing in this file enforced (or even documented) an
 * assumption that Nearby Connections callbacks always arrive on one
 * thread -- in practice GMS typically delivers them on the main looper,
 * but nothing here relied on or asserted that, which is fragile. Fixed by
 * synchronizing every method that reads or mutates this shared state on
 * [lock], rather than swapping in synchronized/concurrent collections
 * individually -- a synchronizedSet/Map wrapper still requires external
 * synchronization for iteration (the FIFO-eviction `.iterator().next()`/
 * `.keys.first()` calls below), and this engine's real correctness
 * requirement is that "is this a duplicate" + "record it as seen" happen
 * as one atomic step, not just that each individual map access is safe in
 * isolation. This is purely a concurrency fix -- no dedup/TTL/relay LOGIC
 * changed, confirmed by keeping every method's body identical, just
 * wrapped.
 */
class PacketRelayEngine(
    private val maxCacheSize: Int = 500,
    /** Injectable clock so the age guard is deterministic under test. */
    private val nowMillis: () -> Long = { System.currentTimeMillis() }
) {
    private val lock = Any()

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
    // Sep 21 2026: reads/writes now happen inside `synchronized(lock)`
    // blocks (see process()/noteSuppressedRelay() below), so the plain
    // `++` is no longer a race -- @Volatile kept for cheap external reads
    // of the current value without needing to take the lock.
    @Volatile
    var totalProcessed: Long = 0L
        private set

    @Volatile
    var duplicatesFiltered: Long = 0L
        private set

    @Volatile
    var relaySuppressed: Long = 0L
        private set

    /**
     * Sep 21 2026 (Vib, Bulk Sprint 4): count of packets rejected by
     * [SignatureVerifier], counted separately from [duplicatesFiltered]
     * so a spike in forged/corrupted traffic is visible on its own rather
     * than hiding inside the ordinary duplicate-rate metric. See
     * docs/security/NATIVE_SIGNATURE_VERIFICATION_DESIGN.md §10, which
     * originally recommended this counter.
     */
    @Volatile
    var signatureFailures: Long = 0L
        private set

    /** Block 1 (mesh-stability): drops made by the guards that run in
     * process(), each counted separately so a spike is attributable. */
    @Volatile
    var oversizedDropped: Long = 0L
        private set

    @Volatile
    var staleDropped: Long = 0L
        private set

    @Volatile
    var ttlDropped: Long = 0L
        private set

    @Volatile
    var closedEmergencyDropped: Long = 0L
        private set

    /** Emergency ids a verified responder has closed (reported by Dart
     * via [markEmergencyClosed]). Bounded FIFO -- see [MAX_CLOSED_IDS]. */
    private val closedEmergencyIds = LinkedHashSet<String>()

    fun noteSuppressedRelay() {
        synchronized(lock) { relaySuppressed++ }
    }

    companion object {
        private const val EARTH_RADIUS_METERS = 6_371_000.0
        const val RELAY_REENTRY_DISTANCE_METERS = 150.0

        /** Must stay in sync with SecurityConstants.maxTTL (Dart). */
        const val MAX_TTL = 5

        /** Must stay in sync with SecurityConstants.maxPacketSize (Dart). */
        const val MAX_PACKET_BYTES = 4096

        /** Must stay in sync with SecurityConstants.maxPacketAge (Dart, 5 min). */
        const val MAX_PACKET_AGE_MS = 300_000L

        /** Must stay in sync with SecurityConstants.allowedClockSkew (Dart, 30 s). */
        const val ALLOWED_CLOCK_SKEW_MS = 30_000L

        /** Upper bound on remembered closed-emergency ids. */
        const val MAX_CLOSED_IDS = 200

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

        private val TIMESTAMP_REGEX =
            Regex("^(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2})(?:\\.(\\d+))?(Z)?$")

        /**
         * Parses the packet's ISO-8601 `timestamp` into epoch millis.
         *
         * Accepts exactly what Dart's DateTime.toIso8601String() emits:
         * `yyyy-MM-ddTHH:mm:ss[.fraction][Z]`, where the fraction is
         * milliseconds (3 digits) OR microseconds (6 digits, which is
         * what Dart produces on Android). Block 1 fix: the previous
         * implementation fed the raw text to SimpleDateFormat with an
         * `SSS` pattern, which reads a 6-digit fraction as that many
         * MILLISECONDS -- e.g. ".123456" became +123 s -- skewing every
         * age calculation by up to two minutes. The fraction is now
         * truncated to milliseconds before parsing.
         *
         * SimpleDateFormat rather than java.time on purpose: minSdk comes
         * from Flutter and java.time needs API 26 / desugaring. Returns
         * null on anything unparseable; the caller decides what null
         * means (process() rejects it, exactly as Dart's DateTime.parse
         * failure would drop the packet).
         */
        fun parseTimestampMillis(raw: String?): Long? {
            if (raw.isNullOrEmpty()) return null
            val m = TIMESTAMP_REGEX.matchEntire(raw) ?: return null
            val base = m.groupValues[1]
            val fraction = m.groupValues[2]
            val isUtc = m.groupValues[3].isNotEmpty()
            val millis = (fraction + "000").substring(0, 3)
            return try {
                val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
                format.isLenient = false
                if (isUtc) format.timeZone = TimeZone.getTimeZone("UTC")
                format.parse("$base.$millis")?.time
            } catch (_: Exception) {
                null
            }
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

    fun process(bytes: ByteArray, currentLat: Double? = null, currentLon: Double? = null): RelayResult = synchronized(lock) {
        totalProcessed++

        // Block 1 (mesh-stability): size guard, mirroring Dart's
        // SecurityConstants.maxPacketSize. Runs before parsing: it is
        // the cheapest possible check, cannot admit anything, and keeps
        // an oversized payload away from the JSON parser and the
        // signature verifier. A packet Dart would accept (<= 4096 bytes)
        // is never affected.
        if (bytes.size > MAX_PACKET_BYTES) {
            oversizedDropped++
            return@synchronized RelayResult(isNew = false, relayBytes = null)
        }

        val rawJson = String(bytes)
        val json: JSONObject
        try {
            json = JSONObject(rawJson)
        } catch (e: Exception) {
            return@synchronized RelayResult(isNew = false, relayBytes = null)
        }

        val packetId = json.optString("packet_id", "")
        if (packetId.isEmpty()) {
            return@synchronized RelayResult(isNew = false, relayBytes = null)
        }

        // Sep 21 2026 (Vib): signature verification happens after basic
        // structural checks but BEFORE anything is admitted to the dedup
        // cache or considered for relay. An unverified packet must never
        // enter [seen] (cache poisoning) and must never be relayed.
        // [rawJson] is passed through because SignatureVerifier reads
        // latitude/longitude from the ORIGINAL wire text.
        if (!SignatureVerifier.verifyPacket(rawJson, json)) {
            signatureFailures++
            return@synchronized RelayResult(isNew = false, relayBytes = null, packetId = packetId)
        }

        // Block 1: age guard, mirroring Dart's TimestampValidator. It
        // runs after signature verification (the timestamp is inside the
        // signed payload, so it is trustworthy here) and before any
        // admission to [seen]. A stale packet therefore cannot poison
        // the cache and is not re-flooded. Unparseable timestamps are
        // rejected: Dart's DateTime.parse would drop them too.
        val sentAt = parseTimestampMillis(json.optString("timestamp", "").ifEmpty { null })
        if (sentAt == null) {
            staleDropped++
            return@synchronized RelayResult(isNew = false, relayBytes = null, packetId = packetId)
        }
        val ageMillis = nowMillis() - sentAt
        if (ageMillis > MAX_PACKET_AGE_MS || ageMillis < -ALLOWED_CLOCK_SKEW_MS) {
            staleDropped++
            return@synchronized RelayResult(isNew = false, relayBytes = null, packetId = packetId)
        }

        // Block 1: a packet for an emergency a responder has closed is
        // neither delivered nor relayed (Dart drops it as well).
        val type = json.optString("type", "")
        if ((type == "emergency" || type == "ack") &&
            closedEmergencyIds.contains(json.optString("emergency_id", ""))
        ) {
            closedEmergencyDropped++
            return@synchronized RelayResult(isNew = false, relayBytes = null, packetId = packetId)
        }

        // Block 1: TTL outside 1..MAX_TTL (including absent/non-numeric)
        // is rejected exactly as Dart's PacketValidator rejects it
        // (InvalidTTLException), so it must not enter [seen]. A genuine
        // packet is born at MAX_TTL and only ever decremented, so a
        // value above the ceiling cannot be genuine; nextTtl() still
        // clamps as defence in depth.
        // ttl is NOT covered by the signature, so any neighbour can
        // re-send a genuine packet with ttl=0; admitting it here would
        // make the real copy look like a duplicate. Rejecting before
        // admission means such a copy leaves no trace.
        val ttl = json.optInt("ttl", 0)
        if (ttl <= 0 || ttl > MAX_TTL) {
            ttlDropped++
            return@synchronized RelayResult(isNew = false, relayBytes = null, packetId = packetId)
        }

        if (seen.contains(packetId)) {
            // Record the echo BEFORE deciding, so a rebroadcast that is
            // still sitting in its jitter window can see it.
            noteEcho(packetId)

            val eligibleForReentry = hasMovedSignificantly(packetId, currentLat, currentLon)
            if (!eligibleForReentry) {
                duplicatesFiltered++
                return@synchronized RelayResult(isNew = false, relayBytes = null, packetId = packetId)
            }
            // Falls through to relay again -- location changed enough
            // that this device is treated as a fresh relay opportunity
            // for this packet, not a loop.
        } else {
            remember(packetId)
        }

        if (currentLat != null && currentLon != null) {
            rememberLocation(packetId, currentLat, currentLon)
        }

        val priority = json.optString("priority", "").ifEmpty { null }
        val isCritical = priority != null && priority.equals("critical", ignoreCase = true)

        val newTtl = nextTtl(ttl, priority, ageMillis.coerceAtLeast(0L))
        if (newTtl <= 0) {
            // Terminal hop: delivered to Dart (it may be an exit node)
            // but not relayed further.
            return@synchronized RelayResult(isNew = true, relayBytes = null, packetId = packetId, isCritical = isCritical)
        }

        json.put("ttl", newTtl)
        json.put("hop_count", json.optInt("hop_count", 0) + 1)
        RelayResult(
            isNew = true,
            relayBytes = json.toString().toByteArray(),
            packetId = packetId,
            isCritical = isCritical
        )
    }

    /**
     * Block 1: called (via MeshChannelHandler) when Dart has accepted a
     * termination from an authorized responder. From then on native
     * neither delivers nor relays emergency/ack packets for that id.
     * Bounded FIFO so it cannot grow without limit.
     */
    fun markEmergencyClosed(emergencyId: String) = synchronized(lock) {
        if (emergencyId.isEmpty()) return@synchronized
        closedEmergencyIds.remove(emergencyId)
        if (closedEmergencyIds.size >= MAX_CLOSED_IDS) {
            closedEmergencyIds.remove(closedEmergencyIds.iterator().next())
        }
        closedEmergencyIds.add(emergencyId)
    }

    fun rememberOriginated(packetId: String) = synchronized(lock) { remember(packetId) }

    /**
     * Sep 21 2026 (Vib, Bulk Sprint 3): bounded snapshot of the current
     * dedup cache, for MeshForegroundService to periodically persist via
     * MeshStateStore so a START_STICKY restart doesn't start with a
     * completely empty seen-cache (see NATIVE_MESH_AUDIT.md §16). Does
     * NOT include [seenAtLocation]/[echoTimestamps] -- location-based
     * re-entry and echo-suppression are short-lived, in-the-moment
     * signals (a few minutes at most) that are of no value restored after
     * a restart; only the durable "have I already relayed this packet_id
     * at all" fact is worth persisting.
     */
    fun snapshotSeen(): List<String> = synchronized(lock) { seen.toList() }

    /**
     * Seeds the dedup cache from a previous run's persisted snapshot.
     * Intended to be called exactly once, immediately after construction
     * and before [process] is ever called -- calling it later would not
     * corrupt anything (it goes through the same bounded [remember] path,
     * respecting maxCacheSize/FIFO eviction) but has no defined ordering
     * against concurrently-arriving packets, so the service is expected
     * to call this synchronously during onCreate() before Nearby
     * Connections is started.
     */
    fun restoreSeen(ids: Collection<String>) = synchronized(lock) {
        for (id in ids) {
            if (id.isNotEmpty()) remember(id)
        }
    }

    /**
     * How many duplicate copies of [packetId] arrived within the last
     * [ECHO_WINDOW_MS]. MeshForegroundService uses this to decide whether
     * its own pending rebroadcast is still worth sending.
     */
    fun recentEchoCount(packetId: String, now: Long = System.currentTimeMillis()): Int = synchronized(lock) {
        val stamps = echoTimestamps[packetId] ?: return@synchronized 0
        stamps.removeAll { now - it > ECHO_WINDOW_MS }
        if (stamps.isEmpty()) {
            echoTimestamps.remove(packetId)
            return@synchronized 0
        }
        stamps.size
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
