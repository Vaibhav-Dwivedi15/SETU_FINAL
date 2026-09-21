// SETU — Cross-language Ed25519 signature fixture verifier (Kotlin/JVM side)
// Sep 21 2026 (Vib, Bulk Sprint 5, Phase 4).
//
// STATUS: written, NOT executed against real Dart output -- there is no
// real Dart-produced signature to feed it yet (dart_sign_fixture.dart has
// never been run, see that file's own header for why). This has been
// compiled and smoke-tested against a KNOWN-GOOD locally-generated
// (Java/BouncyCastle) vector, using the exact same BouncyCastle primitives
// SignatureVerifier.kt uses, to confirm the verifier plumbing itself works
// -- see docs/mesh/CROSS_LANGUAGE_SIGNATURE_VALIDATION.md §3 for that
// smoke-test's real captured output. It has NOT been run against anything
// Dart actually produced.
//
// USAGE, once dart_sign_fixture.dart has been run on a real Flutter/Dart
// environment:
//   javac -cp bcprov-1.77.jar VerifyDartSignature.java
//   java -cp .:bcprov-1.77.jar VerifyDartSignature \
//       <payload_string> <sender_id_hex> <signature_hex>
//
// (Copy `payload_string`, `sender_id(public_key_hex)`, and `signature_hex`
// straight out of dart_sign_fixture.dart's printed output -- do not
// retype/reformat them by hand, to avoid introducing a transcription error
// that would produce a false negative unrelated to real interop.)
//
// This program calls SignatureVerifier's exact `verify()` logic (Ed25519
// primitive calls only -- it does not import SignatureVerifier.kt itself,
// since that requires a Kotlin runtime this plain-Java program does not
// use; the verification math is identical either way, see
// SignatureVerifier.kt's own doc comment for the same BouncyCastle API
// calls). If `dart_ok=true` below when run against real Dart output, that
// is the real, executed, cross-language proof this engagement has been
// missing since Sprint 3. If false, that is real evidence of an actual
// interop bug (most likely candidate: the double.toString()-style
// formatting risk already flagged and worked around for latitude/longitude
// specifically in SignatureVerifier -- but this fixture's latitude/
// longitude are fixed literal strings threaded through unchanged on both
// sides, precisely to rule that specific risk out of this first test; a
// failure here would point somewhere else, e.g. UTF-8 encoding, key
// derivation from seed, or byte order).

import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters;
import org.bouncycastle.crypto.signers.Ed25519Signer;

import java.nio.charset.StandardCharsets;

public class VerifyDartSignature {

    static byte[] fromHex(String hex) {
        int len = hex.length();
        byte[] out = new byte[len / 2];
        for (int i = 0; i < len; i += 2) {
            out[i / 2] = (byte) ((Character.digit(hex.charAt(i), 16) << 4)
                    + Character.digit(hex.charAt(i + 1), 16));
        }
        return out;
    }

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
            System.out.println("exception: " + e);
            return false;
        }
    }

    public static void main(String[] args) {
        if (args.length != 3) {
            System.out.println("Usage: VerifyDartSignature <payload_string> <sender_id_hex> <signature_hex>");
            System.exit(2);
        }
        String payload = args[0];
        String senderIdHex = args[1];
        String signatureHex = args[2];

        System.out.println("payload_string=" + payload);
        System.out.println("sender_id_hex=" + senderIdHex);
        System.out.println("signature_hex=" + signatureHex);

        boolean ok = verify(payload, senderIdHex, signatureHex);
        System.out.println();
        System.out.println("dart_ok=" + ok + "  <-- if true, this is real Dart-signed -> Kotlin-verified proof");
    }
}
