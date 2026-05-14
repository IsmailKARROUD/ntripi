// test/repositories/profile_repository_test.dart
//
// Unit tests for ProfileRepository — the three travel identity fields
// (passport_countries, resident_country, languages) and the existing
// PATCH /users/me body-building logic.
//
// All HTTP is intercepted by DioAdapter — no real network.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/profile/data/profile_repository.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// Minimal valid user JSON returned by PATCH /users/me.
Map<String, dynamic> _userJson({
  String? residentCountry,
  List<String>? passportCountries,
  List<String>? languages,
}) =>
    {
      'id': 'user-1',
      'username': 'ismauo',
      'email': 'ismail@test.com',
      'display_name': 'Ismail',
      'bio': null,
      'avatar_url': null,
      'is_private': true,
      'followers_count': 0,
      'following_count': 0,
      'is_active': true,
      'created_at': '2025-01-01T00:00:00.000Z',
      'updated_at': '2025-01-01T00:00:00.000Z',
      if (passportCountries != null) 'passport_countries': passportCountries,
      if (residentCountry != null) 'resident_country': residentCountry,
      if (languages != null) 'languages': languages,
    };

(Dio, DioAdapter) _makeDio() {
  final dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
  final adapter = DioAdapter(dio: dio);
  return (dio, adapter);
}

// ---------------------------------------------------------------------------

void main() {
  group('ProfileRepository.updateMyProfile', () {
    // ── passport_countries ─────────────────────────────────────────────────

    group('passport_countries', () {
      test(
          'Given passportCountriesChanged=true, '
          'When updateMyProfile called, '
          'Then PATCH body includes passport_countries', () async {
        final (dio, adapter) = _makeDio();

        adapter.onPatch(
          kMyProfileEndpoint,
          (server) => server.reply(
            200,
            _userJson(passportCountries: ['MA', 'FR']),
          ),
          data: {'passport_countries': ['MA', 'FR']},
        );

        final repo = ProfileRepository(dio);
        final user = await repo.updateMyProfile(
          passportCountries: ['MA', 'FR'],
          passportCountriesChanged: true,
        );

        expect(user.passportCountries, ['MA', 'FR']);
      });

      test(
          'Given passportCountriesChanged=false, '
          'When updateMyProfile called, '
          'Then PATCH body does NOT include passport_countries', () async {
        final (dio, adapter) = _makeDio();

        // Adapter matches a body WITHOUT passport_countries
        adapter.onPatch(
          kMyProfileEndpoint,
          (server) => server.reply(200, _userJson()),
          data: <String, dynamic>{},
        );

        final repo = ProfileRepository(dio);
        // passportCountriesChanged defaults to false — field should be omitted
        final user = await repo.updateMyProfile();

        expect(user.passportCountries, isNull);
      });

      test(
          'Given passportCountriesChanged=true with empty list, '
          'When updateMyProfile called, '
          'Then PATCH body sends empty array (clears all passports)', () async {
        final (dio, adapter) = _makeDio();

        adapter.onPatch(
          kMyProfileEndpoint,
          (server) => server.reply(200, _userJson()),
          data: {'passport_countries': <String>[]},
        );

        final repo = ProfileRepository(dio);
        final user = await repo.updateMyProfile(
          passportCountries: [],
          passportCountriesChanged: true,
        );

        expect(user.passportCountries, isNull); // server returned null
      });
    });

    // ── resident_country ───────────────────────────────────────────────────

    group('resident_country', () {
      test(
          'Given residentCountry set, '
          'When updateMyProfile called, '
          'Then PATCH body includes resident_country', () async {
        final (dio, adapter) = _makeDio();

        adapter.onPatch(
          kMyProfileEndpoint,
          (server) => server.reply(
            200,
            _userJson(residentCountry: 'BE'),
          ),
          data: {'resident_country': 'BE'},
        );

        final repo = ProfileRepository(dio);
        final user = await repo.updateMyProfile(residentCountry: 'BE');

        expect(user.residentCountry, 'BE');
      });

      test(
          'Given clearResidentCountry=true, '
          'When updateMyProfile called, '
          'Then PATCH body sends resident_country: null', () async {
        final (dio, adapter) = _makeDio();

        adapter.onPatch(
          kMyProfileEndpoint,
          (server) => server.reply(200, _userJson()),
          data: {'resident_country': null},
        );

        final repo = ProfileRepository(dio);
        final user = await repo.updateMyProfile(clearResidentCountry: true);

        expect(user.residentCountry, isNull);
      });

      test(
          'Given neither residentCountry nor clearResidentCountry, '
          'When updateMyProfile called, '
          'Then PATCH body omits resident_country key entirely', () async {
        final (dio, adapter) = _makeDio();

        adapter.onPatch(
          kMyProfileEndpoint,
          (server) => server.reply(200, _userJson()),
          data: <String, dynamic>{},
        );

        final repo = ProfileRepository(dio);
        await repo.updateMyProfile(); // no resident args → field omitted
      });
    });

    // ── languages ──────────────────────────────────────────────────────────

    group('languages', () {
      test(
          'Given languagesChanged=true, '
          'When updateMyProfile called, '
          'Then PATCH body includes languages list', () async {
        final (dio, adapter) = _makeDio();

        adapter.onPatch(
          kMyProfileEndpoint,
          (server) => server.reply(
            200,
            _userJson(languages: ['FR', 'AR', 'EN']),
          ),
          data: {'languages': ['FR', 'AR', 'EN']},
        );

        final repo = ProfileRepository(dio);
        final user = await repo.updateMyProfile(
          languages: ['FR', 'AR', 'EN'],
          languagesChanged: true,
        );

        expect(user.languages, ['FR', 'AR', 'EN']);
      });

      test(
          'Given languagesChanged=true with empty list, '
          'When updateMyProfile called, '
          'Then PATCH body sends empty array (removes all languages)', () async {
        final (dio, adapter) = _makeDio();

        adapter.onPatch(
          kMyProfileEndpoint,
          (server) => server.reply(200, _userJson()),
          data: {'languages': <String>[]},
        );

        final repo = ProfileRepository(dio);
        await repo.updateMyProfile(languages: [], languagesChanged: true);
      });

      test(
          'Given languagesChanged=false, '
          'When updateMyProfile called, '
          'Then PATCH body omits languages key', () async {
        final (dio, adapter) = _makeDio();

        adapter.onPatch(
          kMyProfileEndpoint,
          (server) => server.reply(200, _userJson()),
          data: <String, dynamic>{},
        );

        final repo = ProfileRepository(dio);
        await repo.updateMyProfile(); // languagesChanged defaults to false
      });
    });

    // ── combined fields ────────────────────────────────────────────────────

    group('combined travel identity update', () {
      test(
          'Given all three travel identity fields changed, '
          'When updateMyProfile called, '
          'Then PATCH body includes all three fields together', () async {
        final (dio, adapter) = _makeDio();

        adapter.onPatch(
          kMyProfileEndpoint,
          (server) => server.reply(
            200,
            _userJson(
              passportCountries: ['MA', 'FR'],
              residentCountry: 'BE',
              languages: ['FR', 'AR'],
            ),
          ),
          data: {
            'passport_countries': ['MA', 'FR'],
            'resident_country': 'BE',
            'languages': ['FR', 'AR'],
          },
        );

        final repo = ProfileRepository(dio);
        final user = await repo.updateMyProfile(
          passportCountries: ['MA', 'FR'],
          passportCountriesChanged: true,
          residentCountry: 'BE',
          languages: ['FR', 'AR'],
          languagesChanged: true,
        );

        expect(user.passportCountries, ['MA', 'FR']);
        expect(user.residentCountry, 'BE');
        expect(user.languages, ['FR', 'AR']);
      });

      test(
          'Given travel identity fields alongside existing display_name, '
          'When updateMyProfile called, '
          'Then PATCH body combines both correctly', () async {
        final (dio, adapter) = _makeDio();

        adapter.onPatch(
          kMyProfileEndpoint,
          (server) => server.reply(
            200,
            _userJson(residentCountry: 'MA'),
          ),
          data: {
            'display_name': 'Ismail',
            'resident_country': 'MA',
          },
        );

        final repo = ProfileRepository(dio);
        final user = await repo.updateMyProfile(
          displayName: 'Ismail',
          residentCountry: 'MA',
        );

        expect(user.residentCountry, 'MA');
      });
    });

    // ── error handling ─────────────────────────────────────────────────────

    group('error handling', () {
      test(
          'Given server returns 422 (invalid country code), '
          'When updateMyProfile called, '
          'Then throws DioException', () async {
        final (dio, adapter) = _makeDio();

        adapter.onPatch(
          kMyProfileEndpoint,
          (server) => server.reply(
            422,
            {'detail': 'must be a 2-letter ISO country code'},
          ),
          data: {'resident_country': 'INVALID'},
        );

        final repo = ProfileRepository(dio);
        expect(
          () => repo.updateMyProfile(residentCountry: 'INVALID'),
          throwsA(isA<DioException>()),
        );
      });
    });
  });
}
