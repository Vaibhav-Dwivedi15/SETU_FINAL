"""
Application configuration.

Centralizes all environment-driven settings for the SETU backend so that no
other module reads os.environ or .env directly. Every other part of the app
(database setup, main.py, future services) should import `settings` from
here instead of re-parsing environment variables.

Values are loaded from the .env file at the project root, with safe
defaults for local development so the app still boots if .env is missing
a value.
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