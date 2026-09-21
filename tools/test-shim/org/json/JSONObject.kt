package org.json

/**
 * Sep 21 2026 (Vib, Bulk Sprint 5) — TEST-ONLY, HAND-WRITTEN JSON SHIM.
 *
 * ============================================================================
 * READ THIS BEFORE TRUSTING ANY RESULT PRODUCED USING THIS FILE.
 * ============================================================================
 *
 * THIS IS NOT THE REAL org.json LIBRARY. It is a minimal, from-scratch
 * reimplementation of the small subset of `org.json.JSONObject`'s public API
 * that SETU's native mesh code (`PacketRelayEngine.kt`, `SignatureVerifier.kt`,
 * `PacketRelayEngineTest.kt`) actually calls: the `JSONObject(String)`
 * constructor, `optString`, `optInt`, `has`, `put`, `remove`, and `toString`.
 *
 * WHY THIS EXISTS: Sprint 4 confirmed, and Sprint 5 re-confirmed by
 * exhaustively re-checking (Gradle's dependency cache, ~/.m2, the OS package
 * repository that supplied BouncyCastle, and the network itself — see
 * docs/mesh/SPRINT5_INTEGRATION_VALIDATION.md §5 for the exact evidence),
 * that the real `org.json:json` Maven artifact is not resolvable anywhere in
 * this sandbox. Sprint 4's response was to test only the two functions in
 * `PacketRelayEngine.kt` that don't need `org.json` at all, and to leave the
 * `org.json`-dependent code entirely uncompiled. Sprint 5's brief explicitly
 * asks for that gap to be closed with REAL compiled-and-executed evidence,
 * not more design reasoning, and explicitly forbids faking a test result.
 *
 * The approach taken here is the narrowest thing that satisfies both
 * constraints: compile the REAL, UNMODIFIED production files
 * (`SignatureVerifier.kt`, `PacketRelayEngine.kt`) — copied verbatim, byte-
 * for-byte, from `setu_app/android/app/src/main/kotlin/com/setu/mesh/` for
 * this standalone compile, not retyped or altered in any way — against this
 * package-compatible substitute, so the compiler and JVM actually execute the
 * real production control flow (verification-before-dedup ordering, TTL
 * clamping, exception-swallowing behavior, etc.), rather than a copy of the
 * logic reimplemented by hand (as Sprint 4's `tools/NativeLogicTest.kt` did
 * for the two functions it could reach).
 *
 * WHAT THIS PROVES: that the real Kotlin source of
 * `SignatureVerifier.kt`/`PacketRelayEngine.kt` compiles without error under
 * a real Kotlin compiler, and that its logic — control flow, ordering,
 * exception handling — behaves as intended for well-formed and malformed
 * JSON input, for the flat, scalar-only JSON shape every real SETU packet
 * actually has (no nested objects/arrays anywhere in the wire format).
 *
 * WHAT THIS DOES NOT PROVE: that the exact same source would compile
 * against the REAL `org.json:json` artifact without changes (though the API
 * surface used is small, stable, and unchanged across `org.json` versions
 * for decades, so this risk is low but not zero), and it does NOT prove
 * behavioral equivalence to real `org.json` on inputs this shim was not
 * exercised against. Known, stated differences from the real library:
 *   - Real org.json rejects duplicate keys within one object by default in
 *     some versions / keeps the last occurrence in others (this has
 *     genuinely varied across org.json releases) -- this shim keeps the LAST
 *     occurrence, unconditionally. SETU packets never contain duplicate
 *     keys in practice, so this is not expected to matter, but it is not
 *     verified against the real library.
 *   - Real org.json's `JSONObject.NULL` sentinel handling, `JSONArray`
 *     support, and `getX`/`optX` overloads for every type are NOT
 *     implemented here at all -- only what the production files actually
 *     call. Any change to those files that calls an org.json method not
 *     listed above will fail to compile against this shim and needs a
 *     supported method added here (with the same "documented, not assumed"
 *     rigor as everything else in this file), NOT a silent workaround.
 *   - Number formatting on `toString()` (e.g., whether `5.0` serializes as
 *     `5.0` or `5`) is NOT guaranteed to match real org.json's Number
 *     formatting rules exactly. This specifically does NOT affect the
 *     signature-verification security path, because `SignatureVerifier`
 *     never reads `latitude`/`longitude` through `JSONObject` at all — it
 *     deliberately reads them from the RAW, UNPARSED JSON TEXT via regex
 *     (see `SignatureVerifier.extractRawNumberField`'s own doc comment for
 *     why), specifically to avoid depending on ANY JSON library's number
 *     formatting, real or shimmed. This shim's number formatting only
 *     affects `PacketRelayEngine.process()`'s own `json.put("ttl", ...)`/
 *     `json.put("hop_count", ...)` re-serialization of the OUTGOING relay
 *     message, which is newly constructed by this codebase itself, not
 *     read back with format-sensitive parsing by anything in this test.
 *
 * This file is NEVER referenced by `setu_app/android/app/build.gradle.kts`
 * or any real production source set. It exists solely under `tools/` for
 * this sandbox's standalone `kotlinc` test compilation, and is documented in
 * `docs/mesh/SPRINT5_INTEGRATION_VALIDATION.md` alongside the exact command
 * used to compile and run it.
 */
class JSONObject {
    private val fields = LinkedHashMap<String, Any?>()

    constructor()

    constructor(source: String) {
        val parser = Parser(source)
        parser.skipWhitespace()
        parser.expect('{')
        parser.skipWhitespace()
        if (parser.peek() != '}') {
            while (true) {
                parser.skipWhitespace()
                val key = parser.parseString()
                parser.skipWhitespace()
                parser.expect(':')
                parser.skipWhitespace()
                val value = parser.parseValue()
                fields[key] = value
                parser.skipWhitespace()
                val c = parser.next()
                if (c == ',') {
                    continue
                } else if (c == '}') {
                    break
                } else {
                    throw JSONShimParseException("Expected ',' or '}' at position ${parser.pos}")
                }
            }
        } else {
            parser.next() // consume '}'
        }
    }

    fun has(key: String): Boolean = fields.containsKey(key)

    fun optString(key: String, defaultValue: String): String {
        val v = fields[key] ?: return defaultValue
        return when (v) {
            is String -> v
            else -> v.toString()
        }
    }

    fun optInt(key: String, defaultValue: Int): Int {
        val v = fields[key] ?: return defaultValue
        return when (v) {
            is Int -> v
            is Long -> v.toInt()
            is Double -> v.toInt()
            is String -> v.toIntOrNull() ?: defaultValue
            else -> defaultValue
        }
    }

    /** Matches real org.json's `optInt(String)` single-arg overload, which
     * defaults to 0 (not caught until this sprint's real compile attempt --
     * see docs/mesh/SPRINT5_INTEGRATION_VALIDATION.md §6 for how this exact
     * gap was found and fixed in the SHIM, not in production code). */
    fun optInt(key: String): Int = optInt(key, 0)

    fun put(key: String, value: Any?): JSONObject {
        fields[key] = value
        return this
    }

    fun remove(key: String): Any? = fields.remove(key)

    override fun toString(): String {
        val sb = StringBuilder()
        sb.append('{')
        var first = true
        for ((k, v) in fields) {
            if (!first) sb.append(',')
            first = false
            sb.append(quote(k))
            sb.append(':')
            sb.append(serializeValue(v))
        }
        sb.append('}')
        return sb.toString()
    }

    private fun serializeValue(v: Any?): String = when (v) {
        null -> "null"
        is String -> quote(v)
        is Boolean -> v.toString()
        is Int, is Long -> v.toString()
        is Double -> {
            // Matches Kotlin's normal Double.toString() -- explicitly NOT
            // claimed to match real org.json's number formatting; see the
            // class doc comment's "Known, stated differences" section.
            if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()
        }
        else -> quote(v.toString())
    }

    private fun quote(s: String): String {
        val sb = StringBuilder()
        sb.append('"')
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> sb.append(c)
            }
        }
        sb.append('"')
        return sb.toString()
    }

    /** Minimal hand-written recursive-descent parser for the FLAT,
     * scalar-only JSON object shape SETU packets actually use. Does not
     * support nested objects/arrays -- no SETU packet type needs them,
     * confirmed by reviewing every toJson()/fromJson() in the Dart packet
     * model files this sprint and every prior one. */
    private class Parser(private val s: String) {
        var pos = 0

        fun peek(): Char {
            if (pos >= s.length) throw JSONShimParseException("Unexpected end of input at position $pos")
            return s[pos]
        }

        fun next(): Char {
            val c = peek()
            pos++
            return c
        }

        fun expect(c: Char) {
            val actual = next()
            if (actual != c) throw JSONShimParseException("Expected '$c' but found '$actual' at position ${pos - 1}")
        }

        fun skipWhitespace() {
            while (pos < s.length && s[pos].isWhitespace()) pos++
        }

        fun parseString(): String {
            expect('"')
            val sb = StringBuilder()
            while (true) {
                if (pos >= s.length) throw JSONShimParseException("Unterminated string at position $pos")
                val c = s[pos]
                pos++
                if (c == '"') break
                if (c == '\\') {
                    if (pos >= s.length) throw JSONShimParseException("Unterminated escape at position $pos")
                    val esc = s[pos]
                    pos++
                    when (esc) {
                        '"' -> sb.append('"')
                        '\\' -> sb.append('\\')
                        '/' -> sb.append('/')
                        'b' -> sb.append('\b')
                        'f' -> sb.append('\u000C')
                        'n' -> sb.append('\n')
                        'r' -> sb.append('\r')
                        't' -> sb.append('\t')
                        'u' -> {
                            if (pos + 4 > s.length) throw JSONShimParseException("Invalid unicode escape at position $pos")
                            val hex = s.substring(pos, pos + 4)
                            pos += 4
                            sb.append(hex.toInt(16).toChar())
                        }
                        else -> throw JSONShimParseException("Invalid escape '\\$esc' at position $pos")
                    }
                } else {
                    sb.append(c)
                }
            }
            return sb.toString()
        }

        fun parseValue(): Any? {
            skipWhitespace()
            if (pos >= s.length) throw JSONShimParseException("Unexpected end of input at position $pos")
            return when (s[pos]) {
                '"' -> parseString()
                't' -> { expectLiteral("true"); true }
                'f' -> { expectLiteral("false"); false }
                'n' -> { expectLiteral("null"); null }
                '{' -> throw JSONShimParseException("Nested objects not supported by this test-only shim (position $pos) -- no SETU packet type needs one")
                '[' -> throw JSONShimParseException("Arrays not supported by this test-only shim (position $pos) -- no SETU packet type needs one")
                else -> parseNumber()
            }
        }

        private fun expectLiteral(lit: String) {
            if (pos + lit.length > s.length || s.substring(pos, pos + lit.length) != lit) {
                throw JSONShimParseException("Expected literal '$lit' at position $pos")
            }
            pos += lit.length
        }

        private fun parseNumber(): Any {
            val start = pos
            if (pos < s.length && s[pos] == '-') pos++
            var isDouble = false
            while (pos < s.length && s[pos].isDigit()) pos++
            if (pos < s.length && s[pos] == '.') {
                isDouble = true
                pos++
                while (pos < s.length && s[pos].isDigit()) pos++
            }
            if (pos < s.length && (s[pos] == 'e' || s[pos] == 'E')) {
                isDouble = true
                pos++
                if (pos < s.length && (s[pos] == '+' || s[pos] == '-')) pos++
                while (pos < s.length && s[pos].isDigit()) pos++
            }
            val text = s.substring(start, pos)
            if (text.isEmpty() || text == "-") throw JSONShimParseException("Invalid number at position $start")
            return if (isDouble) text.toDouble() else (text.toLongOrNull()?.let {
                if (it in Int.MIN_VALUE..Int.MAX_VALUE) it.toInt() else it
            } ?: text.toDouble())
        }
    }
}

/** Thrown on malformed JSON -- a RuntimeException so it's caught by every
 * production `catch (e: Exception)` block exactly as the real
 * `org.json.JSONException` would be (production code never catches
 * `JSONException` by name, only generic `Exception`, so this class does not
 * need to match that name or type hierarchy for the production code paths
 * exercised by these tests). */
class JSONShimParseException(message: String) : RuntimeException(message)
