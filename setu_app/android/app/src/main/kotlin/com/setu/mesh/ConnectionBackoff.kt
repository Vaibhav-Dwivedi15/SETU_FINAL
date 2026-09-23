package com.setu.mesh

/**
 * Block 1 (mesh-stability): per-endpoint reconnect bookkeeping, pulled
 * out of NearbyConnectionsManager so it can be tested on the JVM (the
 * manager itself needs Google Play Services and cannot be).
 *
 * Behaviour:
 *  - A FIRST attempt to an endpoint we have no failures recorded for is
 *    never delayed.
 *  - A failed attempt (requestConnection failure or a non-OK
 *    onConnectionResult) adds a failure; the next attempt to that
 *    endpoint is delayed 2 s, 4 s, 8 s ... capped at 30 s.
 *  - A connection that drops before [STABLE_CONNECTION_MS] counts as a
 *    failure too (connect -> immediate disconnect = flapping). A
 *    connection that lasted long enough clears the history. Success
 *    alone does NOT clear it any more -- that let a flapping peer reset
 *    its own backoff on every brief success.
 *  - Bounded: at most [MAX_TRACKED] endpoints are remembered.
 *
 * SETU still accepts connections from unknown devices; this only paces
 * OUR outgoing attempts. It is not an allowlist.
 */
class ConnectionBackoff(
    private val nowMs: () -> Long = { System.nanoTime() / 1_000_000L }
) {
    private val failures = LinkedHashMap<String, Int>()
    private val lastAttemptAt = HashMap<String, Long>()
    private val connectedAt = HashMap<String, Long>()

    @Synchronized
    fun delayMsFor(endpointId: String): Long {
        val count = failures[endpointId] ?: 0
        if (count <= 0) return 0L
        val exponential = INITIAL_BACKOFF_MS * (1L shl (count - 1).coerceAtMost(10))
        return exponential.coerceAtMost(MAX_BACKOFF_MS)
    }

    @Synchronized
    fun failureCount(endpointId: String): Int = failures[endpointId] ?: 0

    @Synchronized
    fun canAttempt(endpointId: String): Boolean {
        if ((failures[endpointId] ?: 0) <= 0) return true
        val last = lastAttemptAt[endpointId] ?: return true
        return nowMs() - last >= delayMsFor(endpointId)
    }

    @Synchronized
    fun markAttempt(endpointId: String) {
        lastAttemptAt[endpointId] = nowMs()
    }

    @Synchronized
    fun recordFailure(endpointId: String): Int {
        val count = (failures.remove(endpointId) ?: 0) + 1
        failures[endpointId] = count // re-insert: most recently failed is newest
        evictIfNeeded()
        return count
    }

    /** Connection established. Deliberately does not clear failures. */
    @Synchronized
    fun recordConnected(endpointId: String) {
        connectedAt[endpointId] = nowMs()
    }

    /**
     * Connection ended. Returns true if it was short-lived (counted as a
     * failure), false if it was stable (history cleared).
     */
    @Synchronized
    fun recordDisconnected(endpointId: String): Boolean {
        val since = connectedAt.remove(endpointId)
        val lived = if (since == null) Long.MAX_VALUE else nowMs() - since
        return if (lived < STABLE_CONNECTION_MS) {
            recordFailure(endpointId)
            true
        } else {
            failures.remove(endpointId)
            lastAttemptAt.remove(endpointId)
            false
        }
    }

    @Synchronized
    fun clear() {
        failures.clear()
        lastAttemptAt.clear()
        connectedAt.clear()
    }

    @Synchronized
    fun trackedCount(): Int = failures.size

    private fun evictIfNeeded() {
        while (failures.size > MAX_TRACKED) {
            val oldest = failures.keys.iterator().next()
            failures.remove(oldest)
            lastAttemptAt.remove(oldest)
        }
    }

    companion object {
        const val INITIAL_BACKOFF_MS = 2_000L
        const val MAX_BACKOFF_MS = 30_000L

        /** A connection shorter than this is treated as a failed one. */
        const val STABLE_CONNECTION_MS = 5_000L

        const val MAX_TRACKED = 128
    }
}
