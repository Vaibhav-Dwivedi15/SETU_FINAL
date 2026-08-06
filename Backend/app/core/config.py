"""
Application configuration.

Centralizes all environment-driven settings for the SETU backend so that no
other module reads os.environ or .env directly. Every other part of the app
(database setup, main.py, future services) should import `settings` from
here instead of re-parsing environment variables.

Values are loaded from the .env file at the project root, with safe
defaults for local development so the app still boots if .env is missing
a value.

Aug 6 2026: added cors_allowed_origins_raw. WHY THIS EXISTS: an env var
named CORS_ALLOWED_ORIGINS_RAW was set on Render at some point, but no
field with that name ever existed on this Settings class -- and
model_config has extra="ignore", meaning Pydantic silently DROPPED that
env var on every boot rather than erroring. There was never any actual
CORS-handling code anywhere in the app (confirmed by directly grepping
main.py and every router/service file). Whatever cross-origin behavior
was previously observed working from the dashboard was NOT this env var
doing anything -- see main.py for the real CORSMiddleware wiring added
alongside this field.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """
    Typed application settings.

    Field names map to environment variables of the same name
    (case-insensitive), e.g. `database_url` <-> DATABASE_URL in .env.
    """

    # --- Application metadata ---
    app_name: str = "SETU Backend"
    app_version: str = "1.0.0"
    debug: bool = False

    # --- Database ---
    # Format: postgresql+psycopg2://<user>:<password>@<host>:<port>/<db_name>
    database_url: str = "postgresql+psycopg2://postgres:postgres@localhost:5432/setu"
    responder_api_key: str = "changeme-dev-key"

    # --- SMS (SMS Gateway for Android, Cloud Server mode) ---
    # Auto-generated after installing https://sms-gate.app on a phone and
    # toggling Cloud Server -> "Online". See app/services/sms_service.py
    # for why this replaced Fast2SMS (free, no card, no registration).
    sms_gateway_username: str = ""
    sms_gateway_password: str = ""

    # --- CORS (Aug 6 2026, actually wired now -- see main.py) ---
    # Comma-separated list of allowed origins, e.g.
    # "https://setu-sih-dashboard.vercel.app,http://localhost:5173"
    # Defaults to the known production dashboard + common local Vite dev
    # ports, so the app is never accidentally CORS-broken with an unset
    # env var -- but Render should still set this explicitly for
    # anything beyond the default.
    cors_allowed_origins_raw: str = (
        "https://setu-sih-dashboard.vercel.app,"
        "http://localhost:5173,"
        "http://localhost:3000"
    )

    @property
    def cors_allowed_origins(self) -> list[str]:
        return [
            origin.strip()
            for origin in self.cors_allowed_origins_raw.split(",")
            if origin.strip()
        ]

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    """
    Return a cached Settings instance.

    lru_cache guarantees the .env file is read and parsed only once per
    process, and the same Settings object is reused everywhere -- this also
    makes it easy to override settings in tests via FastAPI's dependency
    overrides (`app.dependency_overrides[get_settings] = ...`).
    """
    return Settings()


# Convenience singleton for straightforward imports:
#   from app.core.config import settings
settings = get_settings()
