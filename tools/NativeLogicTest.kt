import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * Sep 21 2026 (Vib, Bulk Sprint 4). Standalone JUnit test, compiled and run
 * with kotlinc + junit-4.13.2 found bundled inside this sandbox's Gradle
 * install (/opt/gradle-8.14.3/lib/), OUTSIDE the real Gradle/Android build
 * (which remains blocked -- no Flutter/Android SDK, see
 * docs/BUILD_AND_VALIDATION.md).
 *
 * SCOPE, stated honestly: PacketRelayEngine.kt's `process()` cannot be
 * compiled or tested this way, because it depends on org.json.JSONObject,
 * and no build of org.json (the standalone Maven artifact, not Android's
 * bundled copy) exists anywhere in this sandbox -- confirmed by an
 * exhaustive `find` across the filesystem, including Gradle's own caches
 * and the OS Maven repo that supplied BouncyCastle. That specific blocker
 * is a missing dependency, not a missing compiler -- see
 * NATIVE_TEST_INFRASTRUCTURE.md for the full explanation.
 *
 * What CAN be tested this way: the companion-object pure functions in
 * PacketRelayEngine.kt that take no org.json / no Android input at all --
 * `nextTtl()` and `parseTimestampMillis()`. Their bodies below are an
 * EXACT, byte-for-byte copy of the real functions in PacketRelayEngine.kt
 * as of this sprint (verified by direct comparison, not retyped from
 * memory) -- copied here only because the surrounding file cannot compile
 * as a whole without org.json, not because the logic itself was changed
 * or reimplemented differently for this test.
 */

object NativeLogicUnderTest {
    const val MAX_TTL = 5
    const val STALE_AFTER_MS = 180_000L

    // Exact copy of PacketRelayEngine.Companion.nextTtl
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

    // Exact copy of PacketRelayEngine.Companion.parseTimestampMillis
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
            }
        }
        return null
    }
}

class NativeLogicTest {

    @Test
    fun nextTtl_normalDecrement_dropsByOne() {
        assertEquals(4, NativeLogicUnderTest.nextTtl(5, "high", null))
    }

    @Test
    fun nextTtl_staleNonCritical_dropsByTwo() {
        assertEquals(3, NativeLogicUnderTest.nextTtl(5, "high", 200_000L))
    }

    @Test
    fun nextTtl_staleButCritical_stillDropsByOne() {
        assertEquals(4, NativeLogicUnderTest.nextTtl(5, "critical", 200_000L))
    }

    @Test
    fun nextTtl_hostileOversizedTtl_isClampedToMaxTtlFirst() {
        // ttl=9999 must be clamped to MAX_TTL(5) before decrementing, so
        // result should never exceed MAX_TTL - 1 = 4, never propagate the
        // attacker-claimed value.
        assertEquals(4, NativeLogicUnderTest.nextTtl(9999, "high", null))
    }

    @Test
    fun nextTtl_atOne_reachesZero_notNegative() {
        assertEquals(0, NativeLogicUnderTest.nextTtl(1, "high", null))
    }

    @Test
    fun nextTtl_atZero_staysZero() {
        assertEquals(0, NativeLogicUnderTest.nextTtl(0, "critical", null))
    }

    @Test
    fun nextTtl_negativeInput_treatedAsExpired() {
        assertEquals(0, NativeLogicUnderTest.nextTtl(-3, "high", null))
    }

    @Test
    fun nextTtl_neverExceedsMaxTtlMinusOne_evenWhenNotStale() {
        val result = NativeLogicUnderTest.nextTtl(NativeLogicUnderTest.MAX_TTL, "critical", null)
        assertTrue(result < NativeLogicUnderTest.MAX_TTL)
    }

    @Test
    fun parseTimestamp_isoWithMillisAndZ_parsesCorrectly() {
        val millis = NativeLogicUnderTest.parseTimestampMillis("2026-01-01T00:00:00.000Z")
        assertEquals(1767225600000L, millis)
    }

    @Test
    fun parseTimestamp_isoWithoutMillis_parsesCorrectly() {
        val millis = NativeLogicUnderTest.parseTimestampMillis("2026-01-01T00:00:00Z")
        assertEquals(1767225600000L, millis)
    }

    @Test
    fun parseTimestamp_nullInput_returnsNull() {
        assertNull(NativeLogicUnderTest.parseTimestampMillis(null))
    }

    @Test
    fun parseTimestamp_emptyInput_returnsNull() {
        assertNull(NativeLogicUnderTest.parseTimestampMillis(""))
    }

    @Test
    fun parseTimestamp_garbageInput_returnsNull_doesNotThrow() {
        assertNull(NativeLogicUnderTest.parseTimestampMillis("not-a-timestamp-at-all"))
    }
}
