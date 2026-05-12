"""
test/test_etag_value_hash.py — _etag_value() / _normalize_etag() contract.

Pinned because the value format is part of the wire contract for
optimistic-concurrency mutations: clients echo it back as If-Match, and
require_etag byte-compares (after _normalize_etag stripping). A regression
that changes the format silently breaks every mutation client.

The concurrency ETag is a quoted ISO datetime — clients format it
differently (`Z` vs `+00:00`), so _normalize_etag is the single point that
collapses the formats before byte comparison.
"""

from dataclasses import dataclass
from datetime import datetime, timezone

from app.dependencies import _etag_value, _normalize_etag


@dataclass
class _FakeItinerary:
    """Minimal stand-in — _etag_value only reads `updated_at`."""

    updated_at: datetime


class TestEtagValue:
    def test_format_is_quoted_iso_string(self):
        e = _etag_value(_FakeItinerary(datetime(2026, 5, 12, 14, 23, 11, tzinfo=timezone.utc)))
        assert e == '"2026-05-12T14:23:11+00:00"'

    def test_same_updated_at_produces_same_value(self):
        ts = datetime(2026, 5, 12, 14, 23, 11, tzinfo=timezone.utc)
        assert _etag_value(_FakeItinerary(ts)) == _etag_value(_FakeItinerary(ts))

    def test_different_updated_at_produces_different_value(self):
        a = _etag_value(
            _FakeItinerary(datetime(2026, 5, 12, 14, 23, 11, tzinfo=timezone.utc))
        )
        b = _etag_value(
            _FakeItinerary(datetime(2026, 5, 12, 14, 23, 12, tzinfo=timezone.utc))
        )
        assert a != b


class TestNormalizeEtag:
    def test_strips_surrounding_quotes(self):
        assert _normalize_etag('"abcd1234"') == "abcd1234"

    def test_strips_whitespace(self):
        assert _normalize_etag('  "abcd1234"  ') == "abcd1234"

    def test_strips_weak_prefix(self):
        # Cloudflare downgrades strong → weak when it recompresses the body.
        # `W/"…"` must compare equal to `"…"`.
        assert _normalize_etag('W/"abcd1234"') == "abcd1234"

    def test_normalizes_z_to_plus_offset(self):
        # Dart's `toIso8601String()` emits `…Z`; Python's `isoformat()`
        # emits `…+00:00`. They must collapse to the same value.
        assert (
            _normalize_etag('"2026-05-12T14:23:11Z"')
            == _normalize_etag('"2026-05-12T14:23:11+00:00"')
        )

    def test_passes_through_unquoted(self):
        assert _normalize_etag("abcd1234") == "abcd1234"

    def test_roundtrip_with_etag_value(self):
        # The whole point: a client that echoes back what the server sent
        # (whether reformatted by intermediaries or not) must still match.
        e = _etag_value(
            _FakeItinerary(datetime(2026, 5, 12, 14, 23, 11, tzinfo=timezone.utc))
        )
        # Three forms a client might send back:
        client_native = e  # exact echo
        client_dart = '"2026-05-12T14:23:11Z"'  # Dart format
        client_weak = f'W/{e}'  # CF-downgraded
        assert _normalize_etag(e) == _normalize_etag(client_native)
        assert _normalize_etag(e) == _normalize_etag(client_dart)
        assert _normalize_etag(e) == _normalize_etag(client_weak)
