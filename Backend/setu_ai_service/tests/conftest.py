"""
Ensures the setu_ai_service project root is on sys.path regardless of how
pytest is invoked (plain `pytest`, `python -m pytest`, or run from a
different working directory). Without this, `from models.xxx import ...`
in test_models.py can fail depending on invocation, because pytest's
default import mode inserts the tests/ directory onto sys.path, not the
project root.
"""

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))
