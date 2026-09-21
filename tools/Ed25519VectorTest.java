import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters;
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters;
import org.bouncycastle.crypto.signers.Ed25519Signer;

import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;

/**
 * Standalone, non-Android, non-Gradle test harness. Run directly with
 * javac/java against the locally-available BouncyCastle jar
 * (/usr/share/java/bcprov-1.77.jar, Maven coords org.bouncycastle:bcprov:1.77)
 * to GENERATE and VERIFY a real, deterministic Ed25519 test vector using
 * the exact same low-level primitives (Ed25519PrivateKeyParameters /
 * Ed25519PublicKeyParameters / Ed25519Signer) proposed for the native
 * Kotlin verifier design in NATIVE_SIGNATURE_VERIFICATION_DESIGN.md.
 *
 * IMPORTANT SCOPE NOTE: this proves the BouncyCastle Ed25519 primitive
 * itself works correctly for SETU's raw 32-byte-seed / 32-byte-pubkey /
 * 64-byte-signature, hex-encoded wire format. It does NOT prove
 * byte-identical interop with Dart's actual `cryptography` package output
 * -- the Dart SDK is unavailable in this sandbox (confirmed in Sprint 3),
 * so no signature was ever actually produced by the real Dart
 * SigningService to compare against. This vector is entirely
 * Java+BouncyCastle-generated, clearly labeled as such wherever it's
 * used, not claimed as cross-verified against Dart.
 */
public class Ed25519VectorTest {

    static String toHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) sb.append(String.format("%02x", b));
        return sb.toString();
    }

    static byte[] fromHex(String hex) {
        int len = hex.length();
        byte[] out = new byte[len / 2];
        for (int i = 0; i < len; i += 2) {
            out[i / 2] = (byte) ((Character.digit(hex.charAt(i), 16) << 4)
                    + Character.digit(hex.charAt(i + 1), 16));
        }
        return out;
    }

    /** Mirrors SigningService.verify()'s contract: never throws, returns
     * false on any malformed input. This is exactly the defensive shape
     * the Kotlin port needs. */
    static boolean verify(String payload, String publicKeyHex, String signatureHex) {
        try {
            byte[] pubBytes = fromHex(publicKeyHex);
            byte[] sigBytes = fromHex(signatureHex);
            if (pubBytes.length != 32) return false;
            if (sigBytes.length != 64) return false;
            Ed25519PublicKeyParameters pub = new Ed25519PublicKeyParameters(pubBytes, 0);
            Ed25519Signer verifier = new Ed25519Signer();
            verifier.init(false, pub);
            byte[] msg = payload.getBytes(StandardCharsets.UTF_8);
            verifier.update(msg, 0, msg.length);
            return verifier.verifySignature(sigBytes);
        } catch (Exception e) {
            return false;
        }
    }

    public static void main(String[] args) {
        // ---- Fixed, deterministic 32-byte seed (test fixture ONLY --
        // never a production key). Bytes 0x00..0x1f, nothing random. ----
        byte[] seed = new byte[32];
        for (int i = 0; i < 32; i++) seed[i] = (byte) i;

        Ed25519PrivateKeyParameters priv = new Ed25519PrivateKeyParameters(seed, 0);
        Ed25519PublicKeyParameters pub = priv.generatePublicKey();
        String senderId = toHex(pub.getEncoded()); // this IS the sender_id, per SigningService's own scheme

        System.out.println("seed_hex=" + toHex(seed));
        System.out.println("sender_id(public_key_hex)=" + senderId);
        System.out.println("sender_id_length=" + senderId.length());

        // ---- Fixed packet fields, matching EmergencyPacketBuilder's
        // exact generation scheme (emergency_packet_builder.dart):
        //   packetId = senderId.substring(0,8) + "-" + microsecondsSinceEpoch
        //   nonce = 16 random bytes, hex (32 hex chars)
        //   emergencyId = packetId
        // Fixed here instead of actually random/time-based, since this is
        // a deterministic test fixture, not a real packet. ----
        String shortSender = senderId.substring(0, 8);
        String packetId = shortSender + "-1767225600000000"; // fixed fake micros
        String nonce = "000102030405060708090a0b0c0d0e0f"; // 16 fixed bytes, hex
        String timestamp = "2026-01-01T00:00:00.000Z"; // matches Dart's DateTime.toUtc().toIso8601String() format for zero ms/us
        String emergencyId = packetId;
        String latitude = "12.9716";
        String longitude = "77.5946";
        String message = "Test SOS message";
        String priority = "critical";

        // EXACT field order from EmergencyPacket.signaturePayload
        // (emergency_packet.dart):
        //   '$packetId|$senderId|${type.name}|${timestamp.toIso8601String()}|'
        //   '$nonce|$emergencyId|$latitude|$longitude|$message|${priority.name}'
        String payload = packetId + "|" + senderId + "|" + "emergency" + "|" + timestamp
                + "|" + nonce + "|" + emergencyId + "|" + latitude + "|" + longitude
                + "|" + message + "|" + priority;

        System.out.println("\npayload_string=" + payload);
        System.out.println("payload_utf8_byte_length=" + payload.getBytes(StandardCharsets.UTF_8).length);

        // ---- Sign ----
        Ed25519Signer signer = new Ed25519Signer();
        signer.init(true, priv);
        byte[] msgBytes = payload.getBytes(StandardCharsets.UTF_8);
        signer.update(msgBytes, 0, msgBytes.length);
        byte[] signature = signer.generateSignature();
        String signatureHex = toHex(signature);

        System.out.println("\nsignature_hex=" + signatureHex);
        System.out.println("signature_length=" + signatureHex.length());

        // ---- Case 1: VALID packet -> expect true ----
        boolean validResult = verify(payload, senderId, signatureHex);
        System.out.println("\n[CASE 1] valid packet -> verify() = " + validResult + " (expected true)");

        // ---- Case 2: modified message (payload tamper) -> expect false ----
        String tamperedPayload = payload.replace("Test SOS message", "Tampered message!");
        boolean tamperedResult = verify(tamperedPayload, senderId, signatureHex);
        System.out.println("[CASE 2] modified message -> verify() = " + tamperedResult + " (expected false)");

        // ---- Case 3: modified location -> expect false ----
        String tamperedLocation = payload.replace("12.9716", "99.9999");
        boolean tamperedLocResult = verify(tamperedLocation, senderId, signatureHex);
        System.out.println("[CASE 3] modified latitude -> verify() = " + tamperedLocResult + " (expected false)");

        // ---- Case 4: modified timestamp -> expect false ----
        String tamperedTs = payload.replace("2026-01-01T00:00:00.000Z", "2026-01-01T00:00:01.000Z");
        boolean tamperedTsResult = verify(tamperedTs, senderId, signatureHex);
        System.out.println("[CASE 4] modified timestamp -> verify() = " + tamperedTsResult + " (expected false)");

        // ---- Case 5: modified sender_id (attacker claims a different key,
        // but signs with the original private key -- classic identity
        // substitution attempt) -> expect false ----
        byte[] otherSeed = new byte[32];
        for (int i = 0; i < 32; i++) otherSeed[i] = (byte) (i + 1);
        String otherSenderId = toHex(new Ed25519PrivateKeyParameters(otherSeed, 0).generatePublicKey().getEncoded());
        String payloadWithOtherSender = payload.replace(senderId, otherSenderId);
        boolean wrongSenderResult = verify(payloadWithOtherSender, otherSenderId, signatureHex);
        System.out.println("[CASE 5] modified sender_id -> verify() = " + wrongSenderResult + " (expected false)");

        // ---- Case 6: modified signature (flip one hex char) -> expect false ----
        char[] sigChars = signatureHex.toCharArray();
        sigChars[0] = sigChars[0] == 'a' ? 'b' : 'a';
        String tamperedSig = new String(sigChars);
        boolean tamperedSigResult = verify(payload, senderId, tamperedSig);
        System.out.println("[CASE 6] modified signature -> verify() = " + tamperedSigResult + " (expected false)");

        // ---- Case 7: malformed public key (wrong length) -> expect false, no throw ----
        boolean malformedPubResult = verify(payload, "deadbeef", signatureHex);
        System.out.println("[CASE 7] malformed public key (short) -> verify() = " + malformedPubResult + " (expected false, no exception)");

        // ---- Case 8: malformed signature (wrong length) -> expect false, no throw ----
        boolean malformedSigResult = verify(payload, senderId, "deadbeef");
        System.out.println("[CASE 8] malformed signature (short) -> verify() = " + malformedSigResult + " (expected false, no exception)");

        // ---- Case 9: non-hex public key -> expect false, no throw ----
        boolean nonHexPubResult = verify(payload, "not-a-valid-hex-string-at-all-zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", signatureHex);
        System.out.println("[CASE 9] non-hex public key -> verify() = " + nonHexPubResult + " (expected false, no exception)");

        // ---- Case 10: empty/missing signature -> expect false, no throw ----
        boolean emptySigResult = verify(payload, senderId, "");
        System.out.println("[CASE 10] empty signature -> verify() = " + emptySigResult + " (expected false, no exception)");

        System.out.println("\nALL_CASES_COMPLETED_NO_CRASH=true");
    }
}
