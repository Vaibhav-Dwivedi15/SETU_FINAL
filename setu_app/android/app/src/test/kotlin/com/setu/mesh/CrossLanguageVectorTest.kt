package com.setu.mesh

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/**
 * Block 1 (Phase 16): Kotlin side of the cross-language signature vector.
 *
 * Consumes wire packets that DART signed (setu_app/test/
 * cross_language_signature_test.dart, run with SETU_XLANG_OUT=<dir>) and
 * runs them through the production Kotlin verification path:
 * SignatureVerifier.verifyPacket over the raw wire text, and the full
 * PacketRelayEngine.process pipeline for the genuine ones. Every
 * tampered variant must be rejected.
 *
 * Run:
 *   SETU_XLANG_OUT=/tmp/xlang flutter test test/cross_language_signature_test.dart   (in setu_app)
 *   SETU_XLANG_DIR=/tmp/xlang ./gradlew :app:testDebugUnitTest --tests '*CrossLanguageVectorTest*'
 *
 * Without SETU_XLANG_DIR the test is SKIPPED (not passed) -- it never
 * claims validation it did not perform.
 */
class CrossLanguageVectorTest {

    @Test
    fun dartSignedPackets_verifyInKotlin_andTamperedOnesFail() {
        val dir = System.getenv("SETU_XLANG_DIR")
        assumeTrue("SETU_XLANG_DIR not set -- cross-language vector not exercised", !dir.isNullOrEmpty())
        val root = File(dir!!)
        val manifest = File(root, "manifest.tsv")
        assumeTrue("manifest.tsv missing in $dir", manifest.exists())

        var checked = 0
        for (line in manifest.readLines().filter { it.isNotBlank() }) {
            val (name, expectedStr) = line.split("\t")
            val expected = expectedStr == "true"
            val raw = File(root, "$name.json").readText(Charsets.UTF_8)
            val json = JSONObject(raw)

            val verified = SignatureVerifier.verifyPacket(raw, json)
            assertEquals("verifyPacket($name)", expected, verified)

            // Full pipeline, with the clock pinned to the packet's own
            // timestamp so the age guard is not what decides the outcome.
            val sentAt = PacketRelayEngine.parseTimestampMillis(json.getString("timestamp"))!!
            val engine = PacketRelayEngine(nowMillis = { sentAt })
            val result = engine.process(raw.toByteArray(Charsets.UTF_8))
            val ttl = json.optInt("ttl", 0)
            if (expected && ttl in 1..PacketRelayEngine.MAX_TTL) {
                assertTrue("engine should accept $name", result.isNew)
            } else if (!expected) {
                assertEquals("engine must reject $name", false, result.isNew)
            }
            checked++
        }
        assertTrue("no vectors were checked", checked > 0)
        println("CrossLanguageVectorTest: $checked vectors verified in Kotlin")
    }
}
