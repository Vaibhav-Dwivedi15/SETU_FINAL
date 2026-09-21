import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Validates the raw-JSON-number-extraction regex used by
 * SignatureVerifier.kt's extractRawNumberField(), translated 1:1 (Kotlin
 * Regex and java.util.regex.Pattern share identical syntax here, so this
 * is a faithful behavioral check even without a Kotlin compiler
 * available in this sandbox). org.json itself is not locally available
 * (it ships inside the real Android SDK's android.jar, absent here), so
 * this checks the regex against raw JSON text directly rather than via
 * an actual JSONObject -- narrower than a full integration test, but it
 * is the part carrying the actual double.toString() interop risk.
 */
public class RawFieldExtractTest {
    static String extractRawNumberField(String rawJson, String key) {
        String pattern = "\"" + Pattern.quote(key) + "\"\\s*:\\s*(-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)";
        Matcher m = Pattern.compile(pattern).matcher(rawJson);
        return m.find() ? m.group(1) : null;
    }

    static void check(String label, String expected, String actual) {
        boolean pass = expected == null ? actual == null : expected.equals(actual);
        System.out.println("[" + (pass ? "PASS" : "FAIL") + "] " + label + " -> " + actual + " (expected " + expected + ")");
    }

    public static void main(String[] args) {
        String json1 = "{\"packet_id\":\"abc-123\",\"latitude\":12.9716,\"longitude\":77.5946,\"message\":\"help\"}";
        check("basic positive decimal", "12.9716", extractRawNumberField(json1, "latitude"));
        check("basic positive decimal 2", "77.5946", extractRawNumberField(json1, "longitude"));

        String json2 = "{\"latitude\":-33.8688,\"longitude\":151.2093}";
        check("negative decimal", "-33.8688", extractRawNumberField(json2, "latitude"));

        String json3 = "{\"latitude\": 0.0 , \"longitude\":0}";
        check("zero with decimal + whitespace", "0.0", extractRawNumberField(json3, "latitude"));
        check("zero integer, no decimal", "0", extractRawNumberField(json3, "longitude"));

        String json4 = "{\"radius_meters\":500,\"latitude\":90.0}";
        check("integer field", "500", extractRawNumberField(json4, "radius_meters"));

        String json5 = "{\"message\":\"lat is not here literally 12.34 inside text\",\"latitude\":45.5}";
        // Ensures the regex anchors on the actual key, not any substring
        // elsewhere in the JSON that happens to look like a number near
        // similar text.
        check("does not false-match inside unrelated string value", "45.5", extractRawNumberField(json5, "latitude"));

        String json6 = "{\"other\":1}";
        check("missing key returns null", null, extractRawNumberField(json6, "latitude"));

        String json7 = "{\"latitude\":\"12.9716\"}"; // quoted (string) -- should NOT match, since it's not a bare number token
        check("quoted string value does not match bare-number pattern", null, extractRawNumberField(json7, "latitude"));

        String json8 = "{\"a\":1,\"latitude\":12.9716,\"b\":2}";
        check("field among siblings", "12.9716", extractRawNumberField(json8, "latitude"));
    }
}
