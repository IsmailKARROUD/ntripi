// test/core/storage/secure_storage_test.dart — Unit tests for isJwtExpired.
//
// isJwtExpired is the core gate in appRouter's redirect function:
//   hasAuth = token != null && token.isNotEmpty && !isJwtExpired(token)
// Testing it here covers the router's auth decisions without requiring
// a full widget tree.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';

/// Build a 3-part JWT whose payload contains exactly {"exp": exp}.
String _makeJwt({required int exp}) {
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': exp})));
  // Header and signature are irrelevant — only the payload is decoded locally.
  return 'eyJhbGciOiJIUzI1NiJ9.$payload.sig';
}

int get _nowSeconds => DateTime.now().millisecondsSinceEpoch ~/ 1000;

void main() {
  group('isJwtExpired', () {
    group('valid token', () {
      test('Given exp is in the future, returns false', () {
        final token = _makeJwt(exp: _nowSeconds + 3600);
        expect(isJwtExpired(token), isFalse);
      });

      test('Given token with no exp claim, returns false (non-expiring token)',
          () {
        // A JWT with only a subject claim — treated as non-expiring.
        final payload = base64Url.encode(
          utf8.encode(jsonEncode({'sub': 'user-1', 'iat': _nowSeconds})),
        );
        expect(isJwtExpired('h.$payload.s'), isFalse);
      });
    });

    group('expired token', () {
      test('Given exp is in the past, returns true', () {
        final token = _makeJwt(exp: _nowSeconds - 1);
        expect(isJwtExpired(token), isTrue);
      });

      test('Given exp equals now (boundary), returns true', () {
        // Expiry at exactly now is treated as expired (>=).
        final token = _makeJwt(exp: _nowSeconds);
        expect(isJwtExpired(token), isTrue);
      });
    });

    group('malformed tokens', () {
      test('Given empty string, returns true', () {
        expect(isJwtExpired(''), isTrue);
      });

      test('Given only two parts, returns true', () {
        expect(isJwtExpired('header.payload'), isTrue);
      });

      test('Given four or more parts, returns true', () {
        expect(isJwtExpired('a.b.c.d'), isTrue);
      });

      test('Given non-base64 payload, returns true', () {
        expect(isJwtExpired('h.!!!invalid_base64!!!.s'), isTrue);
      });

      test('Given payload that is not a JSON object, returns true', () {
        final payload = base64Url.encode(utf8.encode('"just a string"'));
        expect(isJwtExpired('h.$payload.s'), isTrue);
      });
    });
  });
}
