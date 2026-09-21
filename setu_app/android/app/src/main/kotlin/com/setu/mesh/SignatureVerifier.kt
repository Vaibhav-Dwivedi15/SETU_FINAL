package com.setu.mesh

import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import org.json.JSONObject
import java.nio.charset.StandardCharsets

/**
 * Sep 21 2026 (Vib, Bulk Sprint 4): native Ed25519 signature verification,
 * closing the top security gap flagged across Sprints 2/3
 * (docs/security/NATIVE_SIGNATURE_VERIFICATION_DESIGN.md).
 *
 * This is a byte-precise Kotlin port of the low-level BouncyCastle calls
 * validated (compiled AND run, real output captured) in
 * docs/security/NATIVE_SIGNATURE_TEST_VECTOR.md's standalone Java harness
 * -- `Ed25519PublicKeyParameters` + `Ed25519Signer` used identically,
 * same raw 32-byte-key / 64-byte-signature / hex-encoded wire format as
 * SigningService (Dart) already uses. This class has NOT itself been
 * compiled via the real Android/Gradle build (blocked -- no Flutter/
 * Android SDK in this sandbox, see the final report), but the exact same
 * BouncyCastle API calls it makes were proven correct by that standalone
 * harness, against the same bcprov version family (1.77 locally tested;
 * build.gradle.kts declares bcprov-jdk18on:1.78.1, a real Maven Central
 * artifact -- same public API across that version range).
 *
 * CRITICAL, do-not-regress detail: [signaturePayload] below intentionally
 * does NOT reformat `latitude`/`longitude` from parsed JSON numbers.
 * org.json.JSONObject boxes a JSON number as a Double/Long and any
 * *.toString() on that boxed value goes through Kotlin/Java's own
 * number-formatting, which is not guaranteed to produce byte-identical
 * output to Dart's `double.toString()` for the same value (see the
 * design doc's "double.toString() interop risk"). Instead,
 * [extractRawNumberField] pulls the ORIGINAL, unparsed numeric text
 * straight out of the raw JSON string, exactly as it arrived on the
 * wire -- this sidesteps the formatting-divergence risk entirely rather
 * than gambling that both languages format the same double identically.
 */
object SignatureVerifier {

    private fun toBytesFromHex(hex: String): ByteArray? {
        if (hex.length % 2 != 0) return null
        return try {
            ByteArray(hex.length / 2) { i ->
                val idx = i * 2
                val hi = Character.digit(hex[idx], 16)
                val lo = Character.digit(hex[idx + 1], 16)
                if (hi < 0 || lo < 0) return null
                ((hi shl 4) + lo).toByte()
            }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Mirrors SigningService.verify()'s contract exactly: never throws,
     * returns false on any malformed input (wrong-length key/signature,
     * non-hex characters, an invalid curve point, anything) -- a
     * malformed or forged packet must be indistinguishable, from the
     * caller's point of view, from a merely-invalid-signature packet.
     */
    fun verify(payload: String, publicKeyHex: String?, signatureHex: String?): Boolean {
        if (publicKeyHex.isNullOrEmpty() || signatureHex.isNullOrEmpty()) return false
        return try {
            val pubBytes = toBytesFromHex(publicKeyHex) ?: return false
            val sigBytes = toBytesFromHex(signatureHex) ?: return false
            if (pubBytes.size != 32) return false
            if (sigBytes.size != 64) return false
            val pub = Ed25519PublicKeyParameters(pubBytes, 0)
            val verifier = Ed25519Signer()
            verifier.init(false, pub)
            val msg = payload.toByteArray(StandardCharsets.UTF_8)
            verifier.update(msg, 0, msg.size)
            verifier.verifySignature(sigBytes)
        } catch (e: Exception) {
            // Any exception (malformed curve point, etc.) is a
            // verification failure, never a crash -- matches
            // SigningService.verify()'s own documented behavior.
            false
        }
    }

    /**
     * Extracts the raw, un-reparsed JSON text for a numeric field. See
     * the class doc comment for why this matters. Returns null if the
     * key isn't present or isn't followed by a bare (unquoted) JSON
     * number token -- callers must treat null as "cannot safely verify
     * this packet's signature" and reject, never guess a fallback value.
     */
    private fun extractRawNumberField(rawJson: String, key: String): String? {
        val pattern = Regex("\"" + Regex.escape(key) + "\"\\s*:\\s*(-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)")
        return pattern.find(rawJson)?.groupValues?.get(1)
    }

    /**
     * Reconstructs the EXACT signaturePayload string for the packet's
     * `type`, mirroring each Dart packet subclass's own signaturePayload
     * getter field-for-field (see NATIVE_SIGNATURE_VERIFICATION_DESIGN.md
     * §5 for the verbatim Dart source this must match). Returns null for
     * an unrecognized type, or if any required field is missing -- the
     * caller treats null exactly like a failed verification (reject, do
     * not relay, do not crash).
     *
     * String fields are read via [JSONObject.optString], which returns
     * the field's own string content verbatim for a JSON string value --
     * no reformatting risk there (unlike the numeric lat/lon fields,
     * which go through [extractRawNumberField] instead).
     */
    fun buildSignaturePayload(rawJson: String, json: JSONObject): String? {
        val packetId = json.optString("packet_id", "")
        val senderId = json.optString("sender_id", "")
        val type = json.optString("type", "")
        val timestamp = json.optString("timestamp", "")
        val nonce = json.optString("nonce", "")
        if (packetId.isEmpty() || senderId.isEmpty() || type.isEmpty() || timestamp.isEmpty() || nonce.isEmpty()) {
            return null
        }

        return when (type) {
            "emergency" -> {
                val emergencyId = json.optString("emergency_id", "")
                val message = json.optString("message", "")
                val priority = json.optString("priority", "")
                val latitude = extractRawNumberField(rawJson, "latitude")
                val longitude = extractRawNumberField(rawJson, "longitude")
                if (emergencyId.isEmpty() || priority.isEmpty() || latitude == null || longitude == null) return null
                "$packetId|$senderId|$type|$timestamp|$nonce|$emergencyId|$latitude|$longitude|$message|$priority"
            }
            "ack" -> {
                val originalPacketId = json.optString("original_packet_id", "")
                val emergencyId = json.optString("emergency_id", "")
                if (originalPacketId.isEmpty() || emergencyId.isEmpty()) return null
                "$packetId|$senderId|$type|$timestamp|$nonce|$originalPacketId|$emergencyId"
            }
            "alert" -> {
                val incidentType = json.optString("incident_type", "")
                val latitude = extractRawNumberField(rawJson, "latitude")
                val longitude = extractRawNumberField(rawJson, "longitude")
                // radius_meters is an integer on both sides -- Dart int
                // and Kotlin Int always format identically (no fractional
                // shortest-round-trip ambiguity), so reading it back via
                // optInt/toString (rather than the raw-text extractor) is
                // safe here, unlike latitude/longitude.
                val hasRadius = json.has("radius_meters")
                if (incidentType.isEmpty() || latitude == null || longitude == null || !hasRadius) return null
                val radiusMeters = json.optInt("radius_meters")
                "$packetId|$senderId|$type|$timestamp|$nonce|$incidentType|$latitude|$longitude|$radiusMeters"
            }
            "termination" -> {
                val emergencyId = json.optString("emergency_id", "")
                val responderId = json.optString("responder_id", "")
                if (emergencyId.isEmpty() || responderId.isEmpty()) return null
                "$packetId|$senderId|$type|$timestamp|$nonce|$emergencyId|$responderId"
            }
            else -> null // unrecognized packet type -- reject, don't guess a payload shape
        }
    }

    /**
     * Convenience entry point combining payload reconstruction + verify.
     * Returns false (never throws) for any packet this function cannot
     * confidently reconstruct a signature payload for.
     */
    fun verifyPacket(rawJson: String, json: JSONObject): Boolean {
        val payload = buildSignaturePayload(rawJson, json) ?: return false
        val senderId = json.optString("sender_id", "").ifEmpty { null }
        val signature = json.optString("signature", "").ifEmpty { null }
        return verify(payload, senderId, signature)
    }
}
