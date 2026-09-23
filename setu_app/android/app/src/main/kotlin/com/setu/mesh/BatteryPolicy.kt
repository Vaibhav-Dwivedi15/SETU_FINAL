package com.setu.mesh

/**
 * Block 1 (mesh-stability): the battery tiers, expressed natively.
 *
 * These are the SAME thresholds and values Dart already uses
 * (BatteryService._updateMode + MeshPolicy.fromPowerMode):
 *
 *   > 50%    full        relay on   discovery every  5 s (continuous)
 *   20..50%  balanced    relay on   discovery every 15 s
 *   < 20%    powerSaver  relay off  discovery every 30 s
 *
 * Why this exists: the service persists the last policy Dart pushed and
 * used to restore it verbatim after a restart. If the process restarted
 * while the phone was <20% and Dart did not re-attach (the normal case
 * when only the foreground service is revived), allowRelay=false
 * stayed in force after the phone was charged. The service now derives
 * the tier from the actual battery level at start and on level changes;
 * Dart's explicit pushes still apply, and both agree by construction.
 *
 * Pure (no Android imports) so it is covered by plain JVM tests.
 */
object BatteryPolicy {
    const val FULL_ABOVE_PERCENT = 50
    const val POWER_SAVER_BELOW_PERCENT = 20

    data class Tier(val name: String, val discoveryIntervalMs: Long, val allowRelay: Boolean)

    val FULL = Tier("full", 5_000L, true)
    val BALANCED = Tier("balanced", 15_000L, true)
    val POWER_SAVER = Tier("powerSaver", 30_000L, false)

    fun forLevel(percent: Int): Tier = when {
        percent > FULL_ABOVE_PERCENT -> FULL
        percent >= POWER_SAVER_BELOW_PERCENT -> BALANCED
        else -> POWER_SAVER
    }
}
