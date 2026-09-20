"""
One-time sys.path fix for setu_ai_service.

setu_ai_service is vendored at Backend/setu_ai_service/ (a sibling of
Backend/app/, NOT inside app/ -- keeping Vaishnavi's AI/ML code
physically separate from the backend's own package makes it trivial to
pull her updates in later without merge conflicts inside app/).

Every module inside setu_ai_service uses bare absolute imports assuming
its OWN folder is the sys.path root (e.g. `from models.pipeline import
process_message`, `from config import GEMINI_ENABLED`) -- it was never
written to be imported as a namespaced subpackage. So importing
`setu_ai_service.service.ai_service` the normal way fails; instead we
add setu_ai_service/'s own path to sys.path, once, so its internal
`models`, `config`, `service`, `utils`, `prompts` imports resolve
exactly as they do when the AI team runs it standalone.

Checked for collisions against this backend's own top-level names before
adding this: this backend's own modules all live under the `app.`
namespace (app.models, app.services, app.core.config, app.utils --
never bare `models`/`config`/`service`/`utils`), so adding
setu_ai_service's bare-name modules to sys.path does not shadow
anything here. If that ever stops being true (e.g. someone adds a bare
top-level `config.py` to this backend), re-check this file first.
"""

import sys
from pathlib import Path

_SETU_AI_SERVICE_PATH = Path(__file__).resolve().parents[2] / "setu_ai_service"

_added = False


def ensure_setu_ai_service_importable() -> None:
    """
    Idempotent -- safe to call from every module that needs the AI
    service; only touches sys.path once per process.
    """
    global _added
    if _added:
        return

    path_str = str(_SETU_AI_SERVICE_PATH)
    if not _SETU_AI_SERVICE_PATH.is_dir():
        raise FileNotFoundError(
            f"setu_ai_service not found at {path_str} -- expected it as a "
            f"sibling of app/ (Backend/setu_ai_service/). Copy Vaishnavi's "
            f"setu_ai_service folder there before calling analyze()."
        )

    if path_str not in sys.path:
        sys.path.insert(0, path_str)

    _added = True
