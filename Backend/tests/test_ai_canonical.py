"""
Block 2 -- exactly ONE canonical AI implementation.

The repo used to carry two trees: Backend/setu_ai_service/ (imported at runtime,
newer: geo + embedding dedup, confidence, explainability, voice, tests) and a
stale copy at the repository root (no geo dedup, empty test file, empty
incident_data.json, imported by nothing). The root copy was removed; its history
remains in git.
"""

import pathlib
import subprocess

REPO = pathlib.Path(__file__).resolve().parents[2]


def tracked(prefix):
    out = subprocess.run(["git", "ls-files", prefix], capture_output=True, text=True, cwd=REPO).stdout
    return [line for line in out.splitlines() if line]


def test_no_second_ai_tree_is_tracked():
    assert tracked("setu_ai_service") == []


def test_only_one_duplicate_detector_exists_in_tracked_sources():
    detectors = [f for f in tracked(".") if f.endswith("duplicate_detector.py")]
    assert detectors == ["Backend/setu_ai_service/models/duplicate_detector.py"]


def test_runtime_import_resolves_to_the_canonical_tree():
    from app.utils.setu_ai_import_guard import ensure_setu_ai_service_importable
    ensure_setu_ai_service_importable()
    import models.duplicate_detector as detector
    assert pathlib.Path(detector.__file__).resolve() == REPO / "Backend/setu_ai_service/models/duplicate_detector.py"


def test_active_ai_has_geo_dedup_and_tests():
    from app.utils.setu_ai_import_guard import ensure_setu_ai_service_importable
    ensure_setu_ai_service_importable()
    import inspect
    from models.duplicate_detector import check_duplicate
    assert "latitude" in inspect.signature(check_duplicate).parameters
    assert (REPO / "Backend/setu_ai_service/tests/test_models.py").stat().st_size > 1000
