#!/usr/bin/env bash
# Cross-language signature SECURITY GATE (Block 3): Dart signs -> Python verifies -> Kotlin verifies.
#   genuine vectors must pass; every tamper (message, timestamp, latitude, longitude, sender_id,
#   signature, nonce, packet_id, emergency_id, priority) must fail; a relay rewrite of the UNSIGNED
#   fields (ttl, hop_count) must still verify. The Kotlin test must actually RUN (a skipped JUnit
#   test is a gate failure, not a pass). signaturePayload is never modified to make this pass.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${SETU_XLANG_OUT:-$(mktemp -d)}"
PY="${PYTHON:-python3}"
cd "$ROOT/setu_app"

echo "== 1/3 Dart: sign and self-verify, export wire packets to $OUT"
SETU_XLANG_OUT="$OUT" flutter test test/cross_language_signature_test.dart

echo "== 2/3 Python: real backend verify_signature over the Dart wire packets"
"$PY" "$ROOT/tools/cross_lang/verify_python.py" "$OUT"

echo "== 3/3 Kotlin: production SignatureVerifier + PacketRelayEngine over the same packets"
( cd android && SETU_XLANG_DIR="$OUT" ./gradlew :app:cleanTestDebugUnitTest :app:testDebugUnitTest --tests '*CrossLanguageVectorTest*' --no-daemon )
REPORT="$ROOT/setu_app/build/app/test-results/testDebugUnitTest/TEST-com.setu.mesh.CrossLanguageVectorTest.xml"
"$PY" - "$REPORT" <<'PYEOF'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
tests, skipped, failures, errors = (int(root.get(k, 0)) for k in ("tests", "skipped", "failures", "errors"))
print(f"Kotlin CrossLanguageVectorTest: tests={tests} skipped={skipped} failures={failures} errors={errors}")
if tests < 1 or skipped or failures or errors:
    sys.exit("GATE FAILED: the Kotlin cross-language test did not run and pass")
PYEOF
echo "CROSS-LANGUAGE GATE: PASS"
