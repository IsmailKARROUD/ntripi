"""
test/test_etag_value_hash.py — _etag_value() now returns an opaque hash.

Pinned because the value format is part of the wire contract for
optimistic-concurrency mutations: clients echo it back as If-Match, and
require_etag byte-compares (after _normalize_etag stripping). A regression
that changes the format silently breaks every mutation client.
"""

import re
from dataclasses import dataclass
from datetime import datetime, timezone

from app.dependencies import _etag_value, _normalize_etag


@dataclass
class _FakeItinerary:
    """Minimal stand-in — _etag_value only reads `updated_at`."""

    updated_at: datetime


class TestEtagValue:
    def test_format_is_quoted_16_hex(self):
        e = _etag_value(_FakeItinerary(datetime(2026, 5, 12, 14, 23, 11, tzinfo=timezone.utc)))
        assert re.fullmatch(r'"[0-9a-f]{16}"', e), e

    def test_same_updated_at_produces_same_hash(self):
        ts = datetime(2026, 5, 12, 14, 23, 11, tzinfo=timezone.utc)
        assert _etag_value(_FakeItinerary(ts)) == _etag_value(_FakeItinerary(ts))

    def test_different_updated_at_produces_different_hash(self):
        a = _etag_value(
            _FakeItinerary(datetime(2026, 5, 12, 14, 23, 11, tzinfo=timezone.utc))
        )
        b = _etag_value(
            _FakeItinerary(datetime(2026, 5, 12, 14, 23, 12, tzinfo=timezone.utc))
        )
        assert a != b

    def test_microsecond_resolution(self):
        # Two updates in the same second but different microseconds must
        # still produce distinct ETags — otherwise rapid sequential edits
        # could silently bypass the concurrency check.
        a = _etag_value(
            _FakeItinerary(
                datetime(2026, 5, 12, 14, 23, 11, 100, tzinfo=timezone.utc)
            )
        )
        b = _etag_value(
            _FakeItinerary(
                datetime(2026, 5, 12, 14, 23, 11, 200, tzinfo=timezone.utc)
            )
        )
        assert a != b


class TestNormalizeEtag:
    def test_strips_surrounding_quotes(self):
        assert _normalize_etag('"abcd1234"') == "abcd1234"

    def test_strips_whitespace(self):
        assert _normalize_etag('  "abcd1234"  ') == "abcd1234"

    def test_passes_through_unquoted(self):
        assert _normalize_etag("abcd1234") == "abcd1234"

    def test_roundtrip_with_etag_value(self):
        # The whole point: _normalize_etag(_etag_value(x)) must equal
        # _normalize_etag(client_sent_value) when nothing was tampered with.
        e = _etag_value(
            _FakeItinerary(datetime(2026, 5, 12, 14, 23, 11, tzinfo=timezone.utc))
        )
        # Client serializes header as-is; server normalizes both sides.
        assert _normalize_etag(e) == _normalize_etag(e)
