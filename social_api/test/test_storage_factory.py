"""
test_storage_factory.py — backend selection must fail loudly, not fall back.

With STORAGE_BACKEND=r2, a missing R2_* var used to degrade silently to the
filesystem backend — writing to a path production no longer serves (the
/uploads mount is filesystem-only) and taking images out from behind
Cloudflare's CSAM scanning. Now it raises, and main.py's startup storage() call
turns that into a failed boot instead of a quietly broken deploy.
"""

import logging

import pytest

from app.config import get_settings
from app.storage.factory import storage
from app.storage.filesystem import FilesystemStorage
from app.storage.r2_storage import R2Storage


@pytest.fixture(autouse=True)
def _fresh_factory():
    # storage() is a process-lifetime singleton; each test needs its own build,
    # and the cache must be dropped again so later tests rebuild the default.
    storage.cache_clear()
    yield
    storage.cache_clear()


def _configure_r2(monkeypatch, **overrides):
    settings = get_settings()
    values = {
        "STORAGE_BACKEND": "r2",
        "R2_ACCESS_KEY_ID": "key",
        "R2_SECRET_ACCESS_KEY": "secret",
        "R2_BUCKET": "bucket",
        "R2_ENDPOINT": "https://account.r2.cloudflarestorage.com",
        "R2_PUBLIC_URL": "https://images.ntripi.app",
        **overrides,
    }
    for name, value in values.items():
        monkeypatch.setattr(settings, name, value)


def test_filesystem_is_the_default():
    assert isinstance(storage(), FilesystemStorage)


def test_r2_with_full_config_builds_r2(monkeypatch):
    _configure_r2(monkeypatch)
    assert isinstance(storage(), R2Storage)


@pytest.mark.parametrize("missing", [
    "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET",
    "R2_ENDPOINT", "R2_PUBLIC_URL",
])
def test_r2_with_a_missing_var_refuses_to_build(monkeypatch, missing):
    _configure_r2(monkeypatch, **{missing: None})
    with pytest.raises(ValueError, match=missing):
        storage()


def test_r2_dev_domain_warns_that_csam_scanning_is_blind(monkeypatch, caplog):
    """r2.dev serves outside the Cloudflare zone, so the scanner never sees the
    images — allowed (local experiments), but never silently."""
    _configure_r2(monkeypatch, R2_PUBLIC_URL="https://pub-abc123.r2.dev")
    with caplog.at_level(logging.WARNING):
        backend = storage()
    assert isinstance(backend, R2Storage)
    assert any("CSAM" in record.message for record in caplog.records)


def test_unknown_backend_raises(monkeypatch):
    monkeypatch.setattr(get_settings(), "STORAGE_BACKEND", "s3")
    with pytest.raises(ValueError, match="Unknown STORAGE_BACKEND"):
        storage()
