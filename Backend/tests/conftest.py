"""
Backend-wide pytest fixtures.

FIX (Aug 4 2026 debug pass): test_nearby_same_type_reports_merge_into_one_incident
was failing whenever it ran as part of the suite, but passing 100% of the
time in isolation -- a classic test-isolation bug, not a real dedup bug.

Root cause: incident dedup goes through app/services/ai_analysis_service.py
-> setu_ai_service's duplicate_detector.check_duplicate(), which keeps its
cluster state in a plain in-memory list at module scope (see that file's
own docstring -- this is a known, already-documented operational risk,
not new). Earlier tests in the same pytest session leave residual
clusters behind, so a later test can spuriously match (or fail to match)
an incident based on state from a completely unrelated test.

The AI team already solved exactly this in their own suite
(setu_ai_service/tests/test_models.py has an autouse
_reset_duplicate_clusters fixture) -- this backend's tests never adopted
the same pattern, even though handle_sos_packet() depends on the same
shared state indirectly through analyze(). This fixture applies the
identical fix here, for the same reason.

Uses the backend's own existing sys.path guard (ensure_setu_ai_service_
importable) instead of manually reaching into Backend/setu_ai_service/,
so this stays correct even if that vendoring path ever changes.
"""

import pytest

from app.utils.setu_ai_import_guard import ensure_setu_ai_service_importable

ensure_setu_ai_service_importable()

from models.duplicate_detector import reset_clusters  # noqa: E402  (see path guard above)


@pytest.fixture(autouse=True)
def _reset_duplicate_clusters():
    """AI dedup keeps in-memory state across the whole process -- isolate every test."""
    reset_clusters()
    yield
    reset_clusters()
