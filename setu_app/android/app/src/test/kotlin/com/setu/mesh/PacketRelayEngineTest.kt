package com.setu.mesh

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Sep 21 2026 (Vib, Bulk Sprint 4).
 *
 * This is the REAL, intended local-unit-test source (Gradle's standard
 * `src/test/kotlin` source set — Gradle picks this up automatically for
 * the `testDebugUnitTest`/`test` task, no build.gradle.kts wiring beyond
 * the `testImplementation` dependencies already added). It imports and
 * exercises the ACTUAL production classes (`PacketRelayEngine`,
 * `SignatureVerifier`), not a copy.
 *
 * STATUS, stated honestly: this file has NOT been compiled or run in this
 * sandbox. The real Android/Gradle build remains blocked here (no
 * Flutter/Android SDK — see docs/BUILD_AND_VALIDATION.md), and even a
 * JVM-only compile of PacketRelayEngine.kt needs org.json on the
 * classpath, which is not locally cached anywhere in this sandbox either
 * (confirmed by an exhaustive filesystem search — see
 * docs/mesh/NATIVE_TEST_INFRASTRUCTURE.md). This file is therefore
 * "written, believed correct, NOT executed" — it is exactly what should
 * run once a real toolchain (developer machine or CI) is available, and
 * it is not claimed as passing or verified here.
 *
 * A DIFFERENT file, tools/NativeLogicTest.kt, duplicates the
 * org.json-independent pure functions (`nextTtl`, `parseTimestampMillis`)
 * as a standalone, non-Gradle harness — THAT one WAS actually compiled
 * with kotlinc and run with the real JUnit runner in this sandbox, with
 * real captured output (13/13 passing), because it needed no org.json.
 * The two files test overlapping logic for different reasons: this one is
 * the real target for CI; that one is the closest thing to executed proof
 * this sandbox could produce without org.json. See
 * docs/mesh/NATIVE_TEST_INFRASTRUCTURE.md for the full picture.
 */
class PacketRelayEngineTest {

    private fun emergencyJson(
        packetId: String = "abc12345-1000",
        senderId: String = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcd",
        ttl: Int = 5,
        priority: String = "high",
        timestamp: String = "2026-01-01T00:00:00.000Z",
        signature: String = "deadbeef", // deliberately invalid/short — see test names below
        latitude: Double = 12.9716,
        longitude: Double = 77.5946
    ): ByteArray {
        val json = JSONObject()
        json.put("packet_id", packetId)
        json.put("sender_id", senderId)
        json.put("type", "emergency")
        json.put("timestamp", timestamp)
        json.put("nonce", "000102030405060708090a0b0c0d0e0f")
        json.put("ttl", ttl)
        json.put("hop_count", 0)
        json.put("emergency_id", packetId)
        json.put("latitude", latitude)
        json.put("longitude", longitude)
        json.put("message", "Test SOS message")
        json.put("priority", priority)
        json.put("signature", signature)
        return json.toString().toByteArray()
    }

    // ---- Structural rejection (unchanged from before Sprint 4) ----

    @Test
    fun process_malformedJson_isRejected_doesNotCrash() {
        val engine = PacketRelayEngine()
        val result = engine.process("not json at all".toByteArray())
        assertEquals(false, result.isNew)
        assertNull(result.relayBytes)
    }

    @Test
    fun process_emptyPacketId_isRejected() {
        val engine = PacketRelayEngine()
        val json = JSONObject().apply { put("packet_id", "") }
        val result = engine.process(json.toString().toByteArray())
        assertEquals(false, result.isNew)
    }

    // ---- Signature verification gate (NEW, Sprint 4) ----
    //
    // These are the core "did the wiring actually work" tests for task
    // #27: a packet with an invalid/missing signature must be rejected
    // BEFORE it is ever inserted into the dedup cache, and must never be
    // relayed. Because the fixture packets above use a deliberately
    // invalid `signature` ("deadbeef", too short to be a real 64-byte
    // Ed25519 signature), EVERY packet built by emergencyJson() above is
    // expected to fail verification and never reach the dedup/TTL logic
    // at all — which is itself the thing being tested here.

    @Test
    fun process_invalidSignature_isRejected_notRelayed() {
        val engine = PacketRelayEngine()
        val result = engine.process(emergencyJson())
        assertEquals(false, result.isNew)
        assertNull(result.relayBytes)
        assertEquals(1L, engine.signatureFailures)
    }

    @Test
    fun process_invalidSignature_isNotAdmittedToDedupCache() {
        // A packet that fails signature verification must not "poison"
        // the dedup cache -- sending the exact same (still-invalid)
        // packet again should be rejected identically, not treated as a
        // dedup-suppressed duplicate. If this ever starts asserting
        // `duplicatesFiltered` instead of `signatureFailures` incrementing
        // a second time, that would mean an unverified packet slipped
        // into `seen`, which is exactly the regression this test exists
        // to catch.
        val engine = PacketRelayEngine()
        val bytes = emergencyJson()
        engine.process(bytes)
        engine.process(bytes)
        assertEquals(2L, engine.signatureFailures)
        assertEquals(0L, engine.duplicatesFiltered)
    }

    @Test
    fun process_missingSignatureField_isRejected_doesNotCrash() {
        val engine = PacketRelayEngine()
        val json = JSONObject(String(emergencyJson()))
        json.remove("signature")
        val result = engine.process(json.toString().toByteArray())
        assertEquals(false, result.isNew)
    }

    @Test
    fun process_malformedPublicKey_isRejected_doesNotCrash() {
        val engine = PacketRelayEngine()
        val json = JSONObject(String(emergencyJson()))
        json.put("sender_id", "not-hex-at-all")
        val result = engine.process(json.toString().toByteArray())
        assertEquals(false, result.isNew)
    }

    @Test
    fun process_oversizedPacket_stillHandledBySizeLimitNotSignaturePath() {
        // Oversized-packet rejection is SecurityConstants.maxPacketSize's
        // job (Dart-side transport layer), not SignatureVerifier's -- this
        // test only documents that a large-but-otherwise-normal payload
        // does not crash the native verifier itself; it does not assert
        // the transport-level size cap, which this class has no knowledge
        // of.
        val engine = PacketRelayEngine()
        val json = JSONObject(String(emergencyJson()))
        json.put("message", "x".repeat(50_000))
        val result = engine.process(json.toString().toByteArray())
        assertEquals(false, result.isNew) // still rejected -- invalid signature, unrelated to size
    }

    @Test
    fun process_malformedTopLevelJson_missingRequiredFields_rejectedByPayloadBuilder() {
        val engine = PacketRelayEngine()
        val json = JSONObject().apply {
            put("packet_id", "abc12345-1000")
            put("sender_id", "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcd")
            put("type", "emergency")
            // timestamp/nonce/emergency_id/priority all deliberately
            // missing -- SignatureVerifier.buildSignaturePayload() must
            // return null (not throw) and process() must treat that as a
            // rejection, same as any other verification failure.
        }
        val result = engine.process(json.toString().toByteArray())
        assertEquals(false, result.isNew)
    }

    // ---- Pure companion-object logic (also covered, standalone-executed,
    // by tools/NativeLogicTest.kt -- kept here too so the real CI run
    // covers everything in one place once the toolchain exists) ----

    @Test
    fun nextTtl_normalDecrement_dropsByOne() {
        assertEquals(4, PacketRelayEngine.nextTtl(5, "high", null))
    }

    @Test
    fun nextTtl_hostileOversizedTtl_isClampedFirst() {
        assertEquals(4, PacketRelayEngine.nextTtl(9999, "high", null))
    }

    @Test
    fun nextTtl_atZero_staysZero() {
        assertEquals(0, PacketRelayEngine.nextTtl(0, "critical", null))
    }

    @Test
    fun parseTimestamp_garbageInput_returnsNull_doesNotThrow() {
        assertNull(PacketRelayEngine.parseTimestampMillis("not-a-timestamp"))
    }
}
