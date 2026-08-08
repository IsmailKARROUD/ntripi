// core/auth/google_people_client.dart
//
// Reads the Google profile birthday for ONE purpose: prefilling the consent
// sheet so someone who granted the scope does not then get asked for a date
// Google already told us.
//
// This is not the authority and must never be treated as one. The server calls
// the same endpoint with the same access token, checks the result belongs to
// the ID token's subject, and stores its own answer. A client that lied here
// would change nothing.
//
// Every failure returns null and the user is simply asked. Null is the
// ordinary case, not an error: plenty of Google accounts have no birthday set
// or hide the year, and the scope is refusable.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class GooglePeopleClient {
  static const _url = 'https://people.googleapis.com/v1/people/me';

  static Future<DateTime?> fetchBirthdate(String accessToken) async {
    // A bare Dio, never the app's: ours carries the AuthInterceptor, which
    // would attach the Ntripi bearer token to a request to Google.
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      // Read the status ourselves rather than having Dio throw on 401/403,
      // which is the ordinary shape of a declined scope.
      validateStatus: (_) => true,
    ));
    try {
      final response = await dio.get(
        _url,
        queryParameters: {'personFields': 'birthdays'},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode != 200) return null;

      final body = response.data;
      if (body is! Map<String, dynamic>) return null;
      final birthdays = body['birthdays'];
      if (birthdays is! List) return null;

      // Only entries carrying a year are usable — Google publishes month and
      // day with the year hidden for a great many accounts, and that cannot
      // answer an age question. ACCOUNT beats PROFILE: it is the birthday set
      // on the account itself, which is what Google's own age checks use.
      Map<String, dynamic>? best;
      for (final entry in birthdays) {
        if (entry is! Map<String, dynamic>) continue;
        final d = entry['date'];
        if (d is! Map || d['year'] == null) continue;
        final type = (entry['metadata']?['source']?['type']) as String?;
        if (type == 'ACCOUNT') return _toDate(d);
        best ??= entry;
      }
      return best == null ? null : _toDate(best['date'] as Map);
    } catch (e) {
      debugPrint('People API prefill unavailable: $e');
      return null;
    }
  }

  static DateTime? _toDate(Map d) {
    final y = d['year'], m = d['month'], day = d['day'];
    if (y is! int || m is! int || day is! int) return null;
    return DateTime(y, m, day);
  }
}
