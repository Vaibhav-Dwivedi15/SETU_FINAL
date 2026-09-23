"""Cross-language signature vector -- PYTHON side (BLOCK 1, Phase 16).

Verifies the wire packets exported by setu_app/test/cross_language_signature_test.dart
(run with SETU_XLANG_OUT=<dir>) using the backend's REAL
app.services.signature_service.verify_signature.

    python3 tools/cross_lang/verify_python.py <dir>

Fidelity note: /ingest validates each packet through pydantic's PacketIn
before verify_signature sees it. pydantic is not required here; instead a
minimal stand-in exposes the same attributes verify_signature reads
(str fields, float latitude/longitude parsed by json.loads exactly as
pydantic parses them, and `.value` on type/priority). Everything from
that point on -- payload construction and Ed25519 verification -- is the
production code, unmodified.
"""
import json
import pathlib
import sys
from types import SimpleNamespace

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "Backend"))
from app.services.signature_service import verify_signature  # noqa: E402


def as_packet(d: dict) -> SimpleNamespace:
    def enum(value):
        return None if value is None else SimpleNamespace(value=value)

    return SimpleNamespace(
        packet_id=d.get("packet_id"),
        sender_id=d.get("sender_id"),
        type=enum(d.get("type")),
        timestamp=d.get("timestamp"),
        nonce=d.get("nonce"),
        signature=d.get("signature"),
        emergency_id=d.get("emergency_id"),
        latitude=d.get("latitude"),
        longitude=d.get("longitude"),
        message=d.get("message"),
        priority=enum(d.get("priority")),
        responder_id=d.get("responder_id"),
    )


def main(directory: str) -> int:
    root = pathlib.Path(directory)
    failures = 0
    for line in (root / "manifest.tsv").read_text().splitlines():
        name, expected = line.split("\t")
        expected_ok = expected == "true"
        data = json.loads((root / f"{name}.json").read_text(encoding="utf-8"))
        # The backend only accepts emergency and termination packets
        # (schemas/packet.py PacketType); ack/alert are mesh-only.
        if data["type"] not in ("emergency", "termination"):
            print(f"SKIP  {name}: type '{data['type']}' is not accepted by /ingest")
            continue
        actual = verify_signature(as_packet(data))
        status = "ok   " if actual == expected_ok else "FAIL "
        if actual != expected_ok:
            failures += 1
        print(f"{status} {name}: expected={expected_ok} actual={actual}")
    print("RESULT:", "PASS" if failures == 0 else f"{failures} FAILURE(S)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
