"""
Tests for app.core.config.

Verifies that settings load correctly and that expected fields/types are
present, so a broken .env or typo in a field name fails fast in CI rather
than silently at request time.
"""

from app.core.config import Settings, get_settings


def test_settings_load_from_env(monkeypatch):
    """Settings should read values from environment variables."""
    monkeypatch.setenv("APP_NAME", "Test App")
    monkeypatch.setenv("DEBUG", "true")
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg2://u:p@localhost:5432/testdb")

    # Bypass the .env file for this test and read only from env vars.
    test_settings = Settings(_env_file=None)

    assert test_settings.app_name == "Test App"
    assert test_settings.debug is True
    assert test_settings.database_url == "postgresql+psycopg2://u:p@localhost:5432/testdb"


def test_settings_have_sane_defaults():
    """Settings should have working defaults even without a .env file."""
    test_settings = Settings(_env_file=None)

    assert test_settings.app_name
    assert test_settings.app_version
    assert isinstance(test_settings.debug, bool)
    assert test_settings.database_url.startswith("postgresql")


def test_get_settings_is_cached():
    """get_settings() should return the same instance on repeated calls."""
    assert get_settings() is get_settings()
