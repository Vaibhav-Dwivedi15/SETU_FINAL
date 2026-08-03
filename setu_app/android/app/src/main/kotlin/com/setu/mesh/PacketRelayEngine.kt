package com.setu.mesh

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
 */
class PacketRelayEngine(private val maxCacheSize: Int = 500) {
    private val seen = LinkedHashSet<String>()

    // packetId -> (lat, lon) this device was at when it last saw that
    // packet. Only populated when a location reading is available;
    // packets seen before any location update behave exactly as the
    // original packet-id-only dedup (no regression for devices that
    // never call updateDeviceLocation()).
    private val seenAtLocation = LinkedHashMap<String, Pair<Double, Double>>()

    companion object {
        private const val EARTH_RADIUS_METERS = 6_371_000.0
        const val RELAY_REENTRY_DISTANCE_METERS = 150.0

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
    }

    data class RelayResult(val isNew: Boolean, val relayBytes: ByteArray?)

    fun process(bytes: ByteArray, currentLat: Double? = null, currentLon: Double? = null): RelayResult {
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
            val eligibleForReentry = hasMovedSignificantly(packetId, currentLat, currentLon)
            if (!eligibleForReentry) {
                return RelayResult(isNew = false, relayBytes = null)
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

        val ttl = json.optInt("ttl", 0)
        if (ttl <= 0) {
            return RelayResult(isNew = true, relayBytes = null)
        }

        json.put("ttl", ttl - 1)
        json.put("hop_count", json.optInt("hop_count", 0) + 1)
        return RelayResult(isNew = true, relayBytes = json.toString().toByteArray())
    }

    fun rememberOriginated(packetId: String) = remember(packetId)

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
