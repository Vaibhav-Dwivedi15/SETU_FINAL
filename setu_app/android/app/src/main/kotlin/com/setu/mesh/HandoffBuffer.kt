package com.setu.mesh

/**
 * Block 1 (mesh-stability): bounded FIFO holding events destined for Dart
 * while no Dart listener is attached.
 *
 * Pure (no Android types) so its ordering / bound / no-duplicate
 * guarantees are covered by JVM tests. MeshForegroundService owns one
 * instance; see the comment there for why it exists.
 *
 *  - [deliver] hands an event straight to [forward] when nothing is
 *    waiting and the listener accepts it; otherwise it queues it.
 *    An event never overtakes ones already waiting (FIFO).
 *  - [flush] drains the queue in order for as long as [forward] accepts;
 *    an event that was delivered is removed exactly once (no duplicates).
 *  - The queue holds at most [capacity] events; when full the OLDEST is
 *    discarded and counted in [dropped].
 *
 * Thread-safe: all state is guarded by one lock.
 */
class HandoffBuffer<T>(private val capacity: Int) {
    private val lock = Any()
    private val queue = ArrayDeque<T>()

    @Volatile
    var dropped: Long = 0L
        private set

    val size: Int get() = synchronized(lock) { queue.size }

    /** @return true if delivered immediately, false if it was queued. */
    fun deliver(event: T, forward: ((T) -> Boolean)?): Boolean = synchronized(lock) {
        if (queue.isEmpty() && forward != null && forward(event)) return@synchronized true
        if (queue.size >= capacity) {
            queue.removeFirst()
            dropped++
        }
        queue.addLast(event)
        false
    }

    /** @return number of events delivered by this flush. */
    fun flush(forward: ((T) -> Boolean)?): Int = synchronized(lock) {
        if (forward == null) return@synchronized 0
        var flushed = 0
        while (queue.isNotEmpty()) {
            if (!forward(queue.first())) break
            queue.removeFirst()
            flushed++
        }
        flushed
    }

    fun clear() = synchronized(lock) { queue.clear() }
}
