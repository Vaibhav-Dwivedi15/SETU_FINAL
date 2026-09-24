"""
Production-configuration self-check (Block 3). Logged loudly at boot; it never blocks
startup (an SOS backend that refuses to boot because of a missing optional setting is
worse than one that warns), but every finding is something REQUIRED before a public
deployment. Values are never logged -- only names and lengths' sufficiency.
"""

import os
from typing import List

from app.core.config import settings


def production_config_findings() -> List[str]:
    findings: List[str] = []
    if settings.debug:
        findings.append("DEBUG=true: interactive docs, localhost CORS origins and placeholder credentials are enabled. Never in production.")
        return findings
    if not settings.responder_api_key or settings.responder_api_key == "changeme-dev-key":
        findings.append("RESPONDER_API_KEY is unset/placeholder: every responder endpoint answers 500.")
    if not settings.admin_api_key:
        findings.append("ADMIN_API_KEY is unset: provisioning/revoking responders is disabled (503).")
    elif settings.admin_api_key == settings.responder_api_key:
        findings.append("ADMIN_API_KEY equals RESPONDER_API_KEY: dashboard operators could promote responder keys.")
    if len(settings.session_secret) < 32:
        findings.append("SESSION_SECRET is unset or shorter than 32 chars: dashboard login answers 503.")
    if "TRUSTED_PROXY_COUNT" not in os.environ:
        findings.append(
            f"TRUSTED_PROXY_COUNT is not set explicitly (using {settings.trusted_proxy_count}). "
            "REQUIRED: set it to the number of reverse proxies verified in front of this app (0 if directly exposed); "
            "a wrong value either lets clients spoof their IP or collapses every client into one rate-limit bucket."
        )
    if not settings.database_url.startswith(("postgresql", "postgres")):
        findings.append("DATABASE_URL is not PostgreSQL: production must not run on SQLite.")
    if not settings.cors_allowed_origins:
        findings.append("CORS_ALLOWED_ORIGINS_RAW yields no origin: the dashboard cannot call this API.")
    return findings
