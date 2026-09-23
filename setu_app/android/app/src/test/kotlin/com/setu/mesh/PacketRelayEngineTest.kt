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
    /** Fixed instant 10 s after the default fixture timestamp, so every
     * fixture is "fresh" for the Block 1 age guard regardless of when the
     * suite runs. */
    private val fixtureNow = PacketRelayEngine.parseTimestampMillis("2026-01-01T00:00:10.000Z")!!
    private var clockNow = fixtureNow

    private fun newEngine(): PacketRelayEngine = PacketRelayEngine(nowMillis = { clockNow })

    private data class SignedFixture(val senderIdHex: String, val json: JSONObject, val bytes: ByteArray)

    private fun signedEmergencyPacket(
        packetId: String = "abc12345-2000",
        message: String = "Test SOS message",
        latitude: String = "12.9716",
        longitude: String = "77.5946",
        timestamp: String = "2026-01-01T00:00:00.000Z",
        priority: String = "high",
        ttl: Int = 5
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
        json.put("ttl", ttl)
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
        val engine = newEngine()
        val fixture = signedEmergencyPacket()
        val result = engine.process(fixture.bytes)
        assertEquals(true, result.isNew)
        assertNotNull(result.relayBytes)
        assertEquals(0L, engine.signatureFailures)
    }

    @Test
    fun process_validSignature_entersDedupCache_exactlyOnce_duplicateSuppressed() {
        val engine = newEngine()
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
        val engine = newEngine()
        val fixture = signedEmergencyPacket()
        val tamperedJson = JSONObject(String(fixture.bytes))
        tamperedJson.put("message", "TAMPERED - this was not what was signed")
        val result = engine.process(tamperedJson.toString().toByteArray())
        assertEquals(false, result.isNew)
        assertEquals(1L, engine.signatureFailures)
    }

    @Test
    fun process_validSignature_tamperedLatitudeAfterSigning_isRejected() {
        val engine = newEngine()
        val fixture = signedEmergencyPacket()
        val tamperedJson = JSONObject(String(fixture.bytes))
        tamperedJson.put("latitude", 0.0001)
        val result = engine.process(tamperedJson.toString().toByteArray())
        assertEquals(false, result.isNew)
    }

    @Test
    fun process_validSignature_tamperedLongitudeAfterSigning_isRejected() {
        val engine = newEngine()
        val fixture = signedEmergencyPacket()
        val tamperedJson = JSONObject(String(fixture.bytes))
        tamperedJson.put("longitude", 0.0001)
        val result = engine.process(tamperedJson.toString().toByteArray())
        assertEquals(false, result.isNew)
    }

    @Test
    fun process_validSignature_tamperedTimestampAfterSigning_isRejected() {
        val engine = newEngine()
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
        val engine = newEngine()
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
        val engine = newEngine()
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
        val engine = newEngine()
        val result = engine.process("not json at all".toByteArray())
        assertEquals(false, result.isNew)
        assertNull(result.relayBytes)
    }

    @Test
    fun process_emptyPacketId_isRejected() {
        val engine = newEngine()
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
        val engine = newEngine()
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
        val engine = newEngine()
        val bytes = emergencyJson()
        engine.process(bytes)
        engine.process(bytes)
        assertEquals(2L, engine.signatureFailures)
        assertEquals(0L, engine.duplicatesFiltered)
    }

    @Test
    fun process_missingSignatureField_isRejected_doesNotCrash() {
        val engine = newEngine()
        val json = JSONObject(String(emergencyJson()))
        json.remove("signature")
        val result = engine.process(json.toString().toByteArray())
        assertEquals(false, result.isNew)
    }

    @Test
    fun process_malformedPublicKey_isRejected_doesNotCrash() {
        val engine = newEngine()
        val json = JSONObject(String(emergencyJson()))
        json.put("sender_id", "not-hex-at-all")
        val result = engine.process(json.toString().toByteArray())
        assertEquals(false, result.isNew)
    }

    @Test
    fun process_oversizedPacket_stillHandledBySizeLimitNotSignaturePath() {
        // Block 1: the native size guard (4096 bytes, mirroring Dart) now
        // rejects this before parsing; see the size-boundary tests below.
        val engine = newEngine()
        val json = JSONObject(String(emergencyJson()))
        json.put("message", "x".repeat(50_000))
        val result = engine.process(json.toString().toByteArray())
        assertEquals(false, result.isNew)
    }

    @Test
    fun process_malformedTopLevelJson_missingRequiredFields_rejectedByPayloadBuilder() {
        val engine = newEngine()
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

    // =====================================================================
    // Block 1 (mesh-stability): size / age / ttl guards + poisoning
    // regressions. All packets below are genuinely signed.
    // =====================================================================

    private fun rewrapped(f: SignedFixture, edit: (JSONObject) -> Unit): ByteArray {
        val j = JSONObject(String(f.bytes))
        edit(j)
        return j.toString().toByteArray()
    }

    /** A validly signed packet whose serialized size is exactly [target]. */
    private fun signedPacketOfSize(target: Int): SignedFixture {
        var n = 10
        var f = signedEmergencyPacket(message = "x".repeat(n))
        n += target - f.bytes.size
        f = signedEmergencyPacket(message = "x".repeat(n))
        assertEquals(target, f.bytes.size)
        return f
    }

    @Test
    fun size_4095_and_4096_accepted() {
        assertEquals(true, newEngine().process(signedPacketOfSize(4095).bytes).isNew)
        assertEquals(true, newEngine().process(signedPacketOfSize(4096).bytes).isNew)
    }

    @Test
    fun size_4097_rejected_beforeAnythingElse() {
        val engine = newEngine()
        val result = engine.process(signedPacketOfSize(4097).bytes)
        assertEquals(false, result.isNew)
        assertNull(result.relayBytes)
        assertEquals(1L, engine.oversizedDropped)
        assertEquals(0L, engine.signatureFailures)
    }

    @Test
    fun age_freshPacket_accepted_andMicrosecondTimestampParsesCorrectly() {
        // Dart emits 6-digit fractions on Android. The old SimpleDateFormat
        // "SSS" parse read ".123456" as 123456 ms (+2 min).
        val ts = "2026-01-01T00:00:00.123456Z"
        assertEquals(
            PacketRelayEngine.parseTimestampMillis("2026-01-01T00:00:00.123Z"),
            PacketRelayEngine.parseTimestampMillis(ts)
        )
        assertEquals(true, newEngine().process(signedEmergencyPacket(timestamp = ts).bytes).isNew)
    }

    @Test
    fun age_exactlyAtLimit_accepted_beyondLimit_rejected_notAdmittedToDedup() {
        val f = signedEmergencyPacket()
        val sentAt = PacketRelayEngine.parseTimestampMillis("2026-01-01T00:00:00.000Z")!!
        val engine = newEngine()

        clockNow = sentAt + PacketRelayEngine.MAX_PACKET_AGE_MS + 1
        val stale = engine.process(f.bytes)
        assertEquals(false, stale.isNew)
        assertEquals(1L, engine.staleDropped)

        // The stale attempt must not have poisoned the cache: once the
        // packet is within the window it is accepted as NEW.
        clockNow = sentAt + PacketRelayEngine.MAX_PACKET_AGE_MS
        val ok = engine.process(f.bytes)
        assertEquals(true, ok.isNew)
        assertEquals(0L, engine.duplicatesFiltered)
        clockNow = fixtureNow
    }

    @Test
    fun age_futureBeyondSkew_rejected_withinSkew_accepted() {
        val f = signedEmergencyPacket()
        val sentAt = PacketRelayEngine.parseTimestampMillis("2026-01-01T00:00:00.000Z")!!
        clockNow = sentAt - PacketRelayEngine.ALLOWED_CLOCK_SKEW_MS - 1
        assertEquals(false, newEngine().process(f.bytes).isNew)
        clockNow = sentAt - PacketRelayEngine.ALLOWED_CLOCK_SKEW_MS
        assertEquals(true, newEngine().process(f.bytes).isNew)
        clockNow = fixtureNow
    }

    @Test
    fun age_unparseableTimestamp_rejected() {
        // Signed over the garbage timestamp, so signature passes and the
        // age guard is what rejects it.
        val f = signedEmergencyPacket(timestamp = "yesterday")
        val engine = newEngine()
        assertEquals(false, engine.process(f.bytes).isNew)
        assertEquals(1L, engine.staleDropped)
    }

    @Test
    fun ttl_zero_isRejected_andDoesNotPoisonTheGenuineCopy() {
        val engine = newEngine()
        val genuine = signedEmergencyPacket(ttl = 5)
        val attack = rewrapped(genuine) { it.put("ttl", 0) }

        val first = engine.process(attack)
        assertEquals(false, first.isNew)
        assertNull(first.relayBytes)
        assertEquals(1L, engine.ttlDropped)

        val second = engine.process(genuine.bytes)
        assertEquals(true, second.isNew)
        assertNotNull(second.relayBytes)
        assertEquals(0L, engine.duplicatesFiltered)
    }

    @Test
    fun ttl_negative_missing_nonNumeric_andOversized_areRejected_withoutAdmission() {
        val engine = newEngine()
        val genuine = signedEmergencyPacket()
        for (bad in listOf<Any?>(-1, 6, 9999, "abc", null)) {
            val bytes = rewrapped(genuine) {
                if (bad == null) it.remove("ttl") else it.put("ttl", bad)
            }
            assertEquals("ttl=$bad", false, engine.process(bytes).isNew)
        }
        assertEquals(5L, engine.ttlDropped)
        assertEquals(true, engine.process(genuine.bytes).isNew)
    }

    @Test
    fun ttl_one_isDelivered_butNotRelayed() {
        val result = newEngine().process(signedEmergencyPacket(ttl = 1).bytes)
        assertEquals(true, result.isNew)
        assertNull(result.relayBytes)
    }

    @Test
    fun ttl_five_relayedWithFourAndHopIncremented() {
        val result = newEngine().process(signedEmergencyPacket(ttl = 5).bytes)
        val relayed = JSONObject(String(result.relayBytes!!))
        assertEquals(4, relayed.getInt("ttl"))
        assertEquals(1, relayed.getInt("hop_count"))
    }

    @Test
    fun invalidSignature_isNeverAdmitted_thenGenuineAccepted() {
        val engine = newEngine()
        val genuine = signedEmergencyPacket()
        val forged = rewrapped(genuine) { it.put("message", "forged") }
        assertEquals(false, engine.process(forged).isNew)
        assertEquals(true, engine.process(genuine.bytes).isNew)
        assertEquals(0L, engine.duplicatesFiltered)
    }

    @Test
    fun closedEmergency_isNeitherDeliveredNorRelayed() {
        val engine = newEngine()
        val f = signedEmergencyPacket(packetId = "closeme-1")
        engine.markEmergencyClosed("closeme-1")
        val r = engine.process(f.bytes)
        assertEquals(false, r.isNew)
        assertNull(r.relayBytes)
        assertEquals(1L, engine.closedEmergencyDropped)
    }

    @Test
    fun closedEmergency_doesNotAffectOtherEmergencies() {
        val engine = newEngine()
        engine.markEmergencyClosed("someone-else")
        assertEquals(true, engine.process(signedEmergencyPacket().bytes).isNew)
    }

    @Test
    fun closedEmergency_setIsBounded() {
        val engine = newEngine()
        for (i in 0 until PacketRelayEngine.MAX_CLOSED_IDS + 50) engine.markEmergencyClosed("id-$i")
        // Oldest evicted, newest retained.
        assertEquals(true, engine.process(signedEmergencyPacket(packetId = "id-0").bytes).isNew)
        assertEquals(false, engine.process(signedEmergencyPacket(packetId = "id-${PacketRelayEngine.MAX_CLOSED_IDS + 49}").bytes).isNew)
    }

    // ---- pure nextTtl matrix ----

    @Test
    fun nextTtl_matrix() {
        assertEquals(4, PacketRelayEngine.nextTtl(5, "critical", null))
        assertEquals(3, PacketRelayEngine.nextTtl(4, "high", null))
        assertEquals(0, PacketRelayEngine.nextTtl(1, "high", null))
        assertEquals(0, PacketRelayEngine.nextTtl(0, "high", null))
        assertEquals(0, PacketRelayEngine.nextTtl(-3, "high", null))
        assertEquals(4, PacketRelayEngine.nextTtl(9999, "critical", null))
        // stale, non-critical: -2 ; stale critical: still -1
        assertEquals(3, PacketRelayEngine.nextTtl(5, "medium", PacketRelayEngine.STALE_AFTER_MS))
        assertEquals(4, PacketRelayEngine.nextTtl(5, "critical", PacketRelayEngine.STALE_AFTER_MS))
    }

    // ---- BatteryPolicy ----

    @Test
    fun batteryPolicy_thresholds() {
        assertEquals(BatteryPolicy.FULL, BatteryPolicy.forLevel(100))
        assertEquals(BatteryPolicy.FULL, BatteryPolicy.forLevel(51))
        assertEquals(BatteryPolicy.BALANCED, BatteryPolicy.forLevel(50))
        assertEquals(BatteryPolicy.BALANCED, BatteryPolicy.forLevel(20))
        assertEquals(BatteryPolicy.POWER_SAVER, BatteryPolicy.forLevel(19))
        assertEquals(BatteryPolicy.POWER_SAVER, BatteryPolicy.forLevel(0))
        assertEquals(false, BatteryPolicy.forLevel(19).allowRelay)
        assertEquals(true, BatteryPolicy.forLevel(20).allowRelay)
        assertEquals(5_000L, BatteryPolicy.FULL.discoveryIntervalMs)
        assertEquals(15_000L, BatteryPolicy.BALANCED.discoveryIntervalMs)
        assertEquals(30_000L, BatteryPolicy.POWER_SAVER.discoveryIntervalMs)
    }

    @Test
    fun batteryPolicy_recoveryFromPowerSaverRestoresRelay() {
        assertEquals(false, BatteryPolicy.forLevel(15).allowRelay)
        assertEquals(true, BatteryPolicy.forLevel(21).allowRelay)
    }

    // ---- ConnectionBackoff ----

    private var backoffClock = 0L
    private fun newBackoff() = ConnectionBackoff(nowMs = { backoffClock })

    @Test
    fun backoff_firstAttemptNeverDelayed_failureDelaysAndDoubles() {
        backoffClock = 0
        val b = newBackoff()
        assertEquals(true, b.canAttempt("e"))
        b.markAttempt("e")
        assertEquals(1, b.recordFailure("e"))
        assertEquals(false, b.canAttempt("e"))
        backoffClock = ConnectionBackoff.INITIAL_BACKOFF_MS
        assertEquals(true, b.canAttempt("e"))
        b.markAttempt("e")
        b.recordFailure("e")
        assertEquals(2 * ConnectionBackoff.INITIAL_BACKOFF_MS, b.delayMsFor("e"))
        for (i in 0 until 20) b.recordFailure("e")
        assertEquals(ConnectionBackoff.MAX_BACKOFF_MS, b.delayMsFor("e"))
    }

    @Test
    fun backoff_immediateDisconnectCountsAsFailure_stableConnectionClearsIt() {
        backoffClock = 1_000
        val b = newBackoff()
        b.recordConnected("e")
        backoffClock += 100
        assertEquals(true, b.recordDisconnected("e"))
        assertEquals(1, b.failureCount("e"))

        b.recordConnected("e") // success alone does not reset
        assertEquals(1, b.failureCount("e"))
        backoffClock += ConnectionBackoff.STABLE_CONNECTION_MS
        assertEquals(false, b.recordDisconnected("e"))
        assertEquals(0, b.failureCount("e"))
        assertEquals(true, b.canAttempt("e"))
    }

    @Test
    fun backoff_isPerEndpoint_boundedAndClearable() {
        val b = newBackoff()
        b.recordFailure("a")
        assertEquals(true, b.canAttempt("b"))
        for (i in 0 until ConnectionBackoff.MAX_TRACKED + 20) b.recordFailure("e$i")
        assertEquals(ConnectionBackoff.MAX_TRACKED, b.trackedCount())
        b.clear()
        assertEquals(0, b.trackedCount())
        assertEquals(true, b.canAttempt("a"))
    }

    // ---- HandoffBuffer (native -> Dart) ----

    @Test
    fun handoff_beforeListener_buffers_thenFlushesInOrder_exactlyOnce() {
        val buf = HandoffBuffer<String>(10)
        assertEquals(false, buf.deliver("a", null))   // no listener yet
        assertEquals(false, buf.deliver("b", { false })) // listener present but not accepting
        assertEquals(2, buf.size)

        val got = mutableListOf<String>()
        assertEquals(2, buf.flush { got.add(it); true })
        assertEquals(listOf("a", "b"), got)
        assertEquals(0, buf.size)
        assertEquals(0, buf.flush { got.add(it); true }) // nothing re-delivered
        assertEquals(listOf("a", "b"), got)
    }

    @Test
    fun handoff_afterListener_deliversImmediately_andNeverOvertakesQueued() {
        val buf = HandoffBuffer<String>(10)
        val got = mutableListOf<String>()
        val fwd: (String) -> Boolean = { got.add(it); true }
        assertEquals(true, buf.deliver("live-1", fwd))

        buf.deliver("queued", null)
        // A new event while one is still waiting must queue behind it.
        assertEquals(false, buf.deliver("live-2", fwd))
        assertEquals(listOf("live-1"), got)
        buf.flush(fwd)
        assertEquals(listOf("live-1", "queued", "live-2"), got)
    }

    @Test
    fun handoff_isBounded_dropsOldest() {
        val buf = HandoffBuffer<Int>(3)
        for (i in 1..5) buf.deliver(i, null)
        assertEquals(3, buf.size)
        assertEquals(2L, buf.dropped)
        val got = mutableListOf<Int>()
        buf.flush { got.add(it); true }
        assertEquals(listOf(3, 4, 5), got)
    }

    @Test
    fun handoff_partialFlush_keepsRemainderQueued() {
        val buf = HandoffBuffer<Int>(5)
        for (i in 1..3) buf.deliver(i, null)
        var accept = 1
        val got = mutableListOf<Int>()
        buf.flush { if (accept-- > 0) { got.add(it); true } else false }
        assertEquals(listOf(1), got)
        assertEquals(2, buf.size)
        buf.clear()
        assertEquals(0, buf.size)
    }
}
