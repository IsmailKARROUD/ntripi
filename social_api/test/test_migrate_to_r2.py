"""
test_migrate_to_r2.py — URL rewriting for the filesystem→R2 cutover.

Only the pure helper is tested here; the upload half needs a live bucket. The
rewrite is the risky half anyway: the /uploads static mount only exists while
STORAGE_BACKEND=filesystem, so a URL this function skips becomes a 404 the
moment the backend flips.
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.migrate_to_r2 import URL_COLUMNS, rewrite_url

_R2 = "https://images.ntripi.app"


def test_rewrites_a_filesystem_url():
    assert rewrite_url("/uploads/itineraries/abc.jpg", ["/uploads"], _R2) == (
        f"{_R2}/itineraries/abc.jpg"
    )


def test_preserves_the_cache_buster():
    """Avatar and user-cover URLs carry ?v=<ms>; dropping it would make every
    client treat the image as a new version and refetch."""
    assert rewrite_url("/uploads/avatars/u1.jpg?v=1755012345678", ["/uploads"], _R2) == (
        f"{_R2}/avatars/u1.jpg?v=1755012345678"
    )


def test_repoints_an_existing_r2_domain():
    """The r2.dev → custom-domain move is what puts images behind Cloudflare's
    CSAM scanning, so it must be rewritable too."""
    old = "https://pub-abc123.r2.dev"
    assert rewrite_url(f"{old}/avatars/u1.jpg?v=1", [old], _R2) == (
        f"{_R2}/avatars/u1.jpg?v=1"
    )


@pytest.mark.parametrize("url", [
    "", "   ", None,
    "https://cdn.example.com/avatars/u1.jpg",   # not one of ours
    "/uploads",                                  # prefix with no key
    "/uploads/",
])
def test_leaves_unrelated_or_empty_urls_alone(url):
    assert rewrite_url(url, ["/uploads"], _R2) is None


def test_already_migrated_urls_are_skipped():
    # The target base is never in old_bases, so a second run is a no-op.
    assert rewrite_url(f"{_R2}/avatars/u1.jpg", ["/uploads"], _R2) is None


def test_covers_every_column_that_stores_an_image_url():
    """A column missing here silently keeps a dead /uploads URL after cutover."""
    assert set(URL_COLUMNS) == {
        ("itineraries", "id", "cover_image_url"),
        ("users", "id", "avatar_url"),
        ("users", "id", "cover_image_url"),
    }
