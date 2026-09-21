package com.setu.mesh

import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.charset.StandardCharsets

/**
 * Sep 21 2026 (Vib, Bulk Sprint 4), UPDATED Sep 21 2026 (Vib, Bulk Sprint 5).
 *
 * This is the REAL, intended local-unit-test source (Gradle's standard
 * `src/test/kotlin` source set — Gradle picks this up automatically for
 * the `testDebugUnitTest`/`test` task, no build.gradle.kts wiring beyond
 * the `testImplementation` dependencies already added). It imports and
 * exercises the ACTUAL production classes (`PacketRelayEngine`,
 * `SignatureVerifier`), not a copy.
 *
 * STATUS, stated honestly, UPDATED Sprint 5: this file WAS actually
 * compiled and run this sprint — but not by the real Android/Gradle build
 * (still blocked here, no Flutter/Android SDK — see
 * docs/BUILD_AND_VALIDATION.md), and not against the real `org.json:json`
 * Maven artifact (still not locally resolvable anywhere in this sandbox,
 * re-confirmed this sprint). Instead, this exact, unmodified file was
 * copied verbatim into a standalone `kotlinc` workspace alongside verbatim
 * copies of `SignatureVerifier.kt`/`PacketRelayEngine.kt` and a hand-written,
 * clearly-labeled, test-only `org.json.JSONObject`-compatible shim
 * (`tools/test-shim/org/json/JSONObject.kt` — read that file's own doc
 * comment before trusting any result below), then compiled with a real
 * `kotlinc` and run with the real JUnit 4.13.2 runner. Real, captured
 * output — command and result — is in
 * `docs/mesh/SPRINT5_INTEGRATION_VALIDATION.md` §6/§7. This is genuine
 * executed evidence for this file's real logic and ordering, but it is
 * NOT the same claim as "compiles against the real org.json artifact" or
 * "compiles under the real Android/Gradle build" — both remain open, and
 * `docs/mesh/FINAL_VALIDATION_MATRIX.md` states the distinction precisely
 * rather than collapsing it.
 *
 * A DIFFERENT file, tools/NativeLogicTest.kt, duplicates the
 * org.json-independent pure functions (`nextTtl`, `parseTimestampMillis`)
 * as a standalone, non-Gradle harness — that one needed no shim at all
 * (no org.json dependency in the first place) and was already compiled
 * and run in Sprint 4. See docs/mesh/NATIVE_TEST_INFRASTRUCTURE.md and
 * docs/mesh/SPRINT5_INTEGRATION_VALIDATION.md for the full picture.
 */
class PacketRelayEngineTest {

    /** Generates a fresh Ed25519 keypair and signs [payload] with it,
     * using the exact same BouncyCastle primitives (`Ed25519Signer`) that
     * `SignatureVerifier.verify()` uses to check the signature -- this is
     * NOT a substitute for real Dart-produced signatures (see Phase 4 /
     * docs/mesh/CROSS_LANGUAGE_SIGNATURE_VALIDATION.md for that distinct,
     * still-open question), it only lets this JVM-only test suite
     * construct a packet whose signature genuinely, cryptographically
     * verifies, so the ACCEPT path (not just every REJECT path) can
     * actually be exercised. */
    private data class SignedFixture(val senderIdHex: String, val json: JSONObject, val bytes: ByteArray)

    private fun signedEmergencyPacket(
        packetId: String = "abc12345-2000",
        message: String = "Test SOS message",
        latitude: String = "12.9716",
        longitude: String = "77.5946",
        timestamp: String = "2026-01-01T00:00:00.000Z",
        priority: String = "high"
    ): SignedFixture {
        val seed = ByteArray(32) { (it + 7).toByte() }
        val priv = Ed25519PrivateKeyParameters(seed, 0)
        val pub = priv.generatePublicKey()
        val senderIdHex = pub.encoded.joinToString("") { "%02x".format(it) }
        val nonce = "000102030405060708090a0b0c0d0e0f"
        val emergencyId = packetId
        val payload = "$packetId|$senderIdHex|emergency|$timestamp|$nonce|$emergencyId|$latitude|$longitude|$message|$priority"

        val signer = Ed25519Signer()
        signer.init(true, priv)
        val msgBytes = payload.toByteArray(StandardCharsets.UTF_8)
        signer.update(msgBytes, 0, msgBytes.size)
        val signatureHex = signer.generateSignature().joinToString("") { "%02x".format(it) }

        val json = JSONObject()
        json.put("packet_id", packetId)
        json.put("sender_id", senderIdHex)
        json.put("type", "emergency")
        json.put("timestamp", timestamp)
        json.put("nonce", nonce)
        json.put("ttl", 5)
        json.put("hop_count", 0)
        json.put("emergency_id", emergencyId)
        json.put("latitude", latitude.toDouble())
        json.put("longitude", longitude.toDouble())
        json.put("message", message)
        json.put("priority", priority)
        json.put("signature", signatureHex)

        return SignedFixture(senderIdHex, json, json.toString().toByteArray())
    }

    // ---- Sprint 5: the ACCEPT path, actually exercised with a genuinely
    // valid signature -- Sprint 4 never had a way to produce one in
    // Kotlin, so every existing test below only exercised REJECT paths. ----

    @Test
    fun process_validSignature_isAccepted_andRelayed() {
        val engine = PacketRelayEngine()
        val fixture = signedEmergencyPacket()
        val result = engine.process(fixture.bytes)
        assertEquals(true, result.isNew)
        assertNotNull(result.relayBytes)
        assertEquals(0L, engine.signatureFailures)
    }

    @Test
    fun process_validSignature_entersDedupCache_exactlyOnce_duplicateSuppressed() {
        val engine = PacketRelayEngine()
        val fixture = signedEmergencyPacket()
        val first = engine.process(fixture.bytes)
        val second = engine.process(fixture.bytes)
        assertEquals(true, first.isNew)
        assertEquals(false, second.isNew)
        assertNull(second.relayBytes)
        assertEquals(1L, engine.duplicatesFiltered)
        assertEquals(0L, engine.signatureFailures)
    }

    @Test
    fun process_validSignature_tamperedMessageAfterSigning_isRejected() {
        val engine = PacketRelayEngine()
        val fixture = signedEmergencyPacket()
        val tamperedJson = JSONObject(String(fixture.bytes))
        tamperedJson.put("message", "TAMPERED - this was not what was signed")
        val result = engine.process(tamperedJson.toString().toByteArray())
        assertEquals(false, result.isNew)
        assertEquals(1L, engine.signatureFailures)
    }

    @Test
    fun process_validSignature_tamperedLatitudeAfterSigning_isRejected() {
        val engine = PacketRelayEngine()
        val fixture = signedEmergencyPacket()
        val tamperedJson = JSONObject(String(fixture.bytes))
        tamperedJson.put("latitude", 0.0001)
        val result = engine.process(tamperedJson.toString().toByteArray())
        assertEquals(false, result.isNew)
    }

    @Test
    fun process_validSignature_tamperedLongitudeAfterSigning_isRejected() {
        val engine = PacketRelayEngine()
        val fixture = signedEmergencyPacket()
        val tamperedJson = JSONObject(String(fixture.bytes))
        tamperedJson.put("longitude", 0.0001)
        val result = engine.process(tamperedJson.toString().toByteArray())
        assertEquals(false, result.isNew)
    }

    @Test
    fun process_validSignature_tamperedTimestampAfterSigning_isRejected() {
        val engine = PacketRelayEngine()
        val fixture = signedEmergencyPacket()
        val tamperedJson = JSONObject(String(fixture.bytes))
        tamperedJson.put("timestamp", "2026-01-01T00:00:01.000Z")
        val result = engine.process(tamperedJson.toString().toByteArray())
        assertEquals(false, result.isNew)
    }

    @Test
    fun process_validSignature_tamperedSenderIdAfterSigning_isRejected() {
        // Classic identity-substitution attempt: claim a different
        // sender_id while keeping the original (now mismatched) signature.
        val engine = PacketRelayEngine()
        val fixture = signedEmergencyPacket()
        val tamperedJson = JSONObject(String(fixture.bytes))
        val otherSeed = ByteArray(32) { (it + 99).toByte() }
        val otherPub = Ed25519PrivateKeyParameters(otherSeed, 0).generatePublicKey()
        val otherSenderIdHex = otherPub.encoded.joinToString("") { "%02x".format(it) }
        tamperedJson.put("sender_id", otherSenderIdHex)
        val result = engine.process(tamperedJson.toString().toByteArray())
        assertEquals(false, result.isNew)
    }

    @Test
    fun process_validSignature_tamperedSignatureItself_isRejected() {
        val engine = PacketRelayEngine()
        val fixture = signedEmergencyPacket()
        val tamperedJson = JSONObject(String(fixture.bytes))
        val originalSig = tamperedJson.optString("signature", "")
        val flippedSig = (if (originalSig.first() == '0') '1' else '0') + originalSig.substring(1)
        tamperedJson.put("signature", flippedSig)
        val result = engine.process(tamperedJson.toString().toByteArray())
        assertEquals(false, result.isNew)
    }

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
