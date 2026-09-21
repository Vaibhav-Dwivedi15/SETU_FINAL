package com.setu.mesh

import android.content.Context
import android.content.SharedPreferences

/**
 * Sep 21 2026 (Vib, Bulk Sprint 3): small SharedPreferences wrapper so
 * [MeshForegroundService] can survive a START_STICKY restart without
 * forgetting its last-known battery policy or briefly re-relaying
 * packets it had already deduped, as documented as a real gap in
 * docs/mesh/NATIVE_MESH_AUDIT.md §16 and docs/mesh/NATIVE_FAILURE_MATRIX.md
 * row 17.
 *
 * Deliberately NOT a database. This stores a handful of scalar values
 * (the current policy) plus one bounded, comma-joined string (recent
 * dedup packet IDs, capped the same way PacketRelayEngine's in-memory
 * `seen` cache already is) -- a few kilobytes at most. A real database
 * (Room/SQLite) would be the wrong tool for a value this small and this
 * infrequently written; SharedPreferences' existing durability guarantee
 * (survives process death, backed by a small file under
 * /data/data/<pkg>/shared_prefs/) is exactly what this needs and nothing
 * more.
 *
 * Persistence is deliberately best-effort and NOT written on every single
 * packet: MeshForegroundService only calls [saveSeenIds] on a periodic
 * timer (see PERSIST_INTERVAL_MS there) and once more, opportunistically,
 * from onDestroy() -- writing on every process() call would mean a disk
 * write per received packet, which is not an acceptable cost for a
 * battery-constrained relay device. This means a truly abrupt kill (e.g.
 * the OS OOM-killer, which does not guarantee onDestroy() runs at all)
 * can still lose up to one persistence interval's worth of dedup history
 * -- an accepted, documented trade-off, not a silently-assumed guarantee.
 * Losing that history is not a correctness bug: a re-relayed packet that
 * slips through is still bounded by TTL and still deduped by every other
 * device's own cache, exactly as it already is when a device's seen-cache
 * evicts an old entry under normal FIFO pressure.
 */
class MeshStateStore(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // ---- Policy (discoveryIntervalMs / allowRelay) ----

    fun savePolicy(discoveryIntervalMs: Long, allowRelay: Boolean) {
        prefs.edit()
            .putLong(KEY_DISCOVERY_INTERVAL_MS, discoveryIntervalMs)
            .putBoolean(KEY_ALLOW_RELAY, allowRelay)
            .apply()
    }

    /**
     * Returns null if no policy has ever been persisted (fresh install, or
     * a build predating this change) -- caller should fall back to its
     * existing hardcoded defaults in that case, exactly as before this
     * pass. When a value IS present, it reflects the last policy Dart
     * actually pushed via updateMeshPolicy, which is a strictly better
     * starting point than the hardcoded full-power default while waiting
     * for Dart to reattach and re-sync after a restart.
     */
    fun loadPolicy(): Policy? {
        if (!prefs.contains(KEY_DISCOVERY_INTERVAL_MS)) return null
        return Policy(
            discoveryIntervalMs = prefs.getLong(KEY_DISCOVERY_INTERVAL_MS, DEFAULT_DISCOVERY_INTERVAL_MS),
            allowRelay = prefs.getBoolean(KEY_ALLOW_RELAY, true)
        )
    }

    data class Policy(val discoveryIntervalMs: Long, val allowRelay: Boolean)

    // ---- Bounded dedup snapshot ----

    /**
     * [ids] is expected to already be bounded by the caller (it's a
     * snapshot of PacketRelayEngine's own maxCacheSize-bounded `seen`
     * set) -- this method does not re-bound it, it just persists what it's
     * given. packet_id values are generated as "<shortSenderId>-<micros>"
     * (see mesh/services identity/packet builders, Dart side) and never
     * contain a comma, so a plain comma join/split is safe and avoids
     * pulling in a JSON dependency for a handful of short strings.
     */
    fun saveSeenIds(ids: Collection<String>) {
        prefs.edit().putString(KEY_SEEN_IDS, ids.joinToString(",")).apply()
    }

    fun loadSeenIds(): List<String> {
        val raw = prefs.getString(KEY_SEEN_IDS, null) ?: return emptyList()
        if (raw.isEmpty()) return emptyList()
        return raw.split(",").filter { it.isNotEmpty() }
    }

    companion object {
        private const val PREFS_NAME = "setu_mesh_state"
        private const val KEY_DISCOVERY_INTERVAL_MS = "discovery_interval_ms"
        private const val KEY_ALLOW_RELAY = "allow_relay"
        private const val KEY_SEEN_IDS = "seen_ids"

        /** Mirrors MeshForegroundService's own pre-existing full-power
         * default -- only used if [loadPolicy] returns null AND the
         * caller has no other default of its own, kept here so this
         * store is self-describing rather than silently relying on the
         * caller to remember the right fallback number. */
        const val DEFAULT_DISCOVERY_INTERVAL_MS = 5_000L
    }
}
