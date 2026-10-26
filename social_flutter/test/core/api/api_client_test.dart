// test/core/api/api_client_test.dart — Unit tests for extractErrorMessage().
//
// extractErrorMessage() is the single helper that every screen routes
// DioException through. The offline-support work makes it responsible for
// turning connection-type errors into the user-facing
// "No internet connection..." message instead of leaking the raw
// "DioException [connection error]..." text. Because it's a pure function,
// it's worth pinning down so future regressions show up here.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/api/api_client.dart';

void main() {
  // A request the DioException needs as scaffolding — value doesn't matter,
  // only `type` and `response.data` are inspected by the helper.
  final requestOptions = RequestOptions(path: '/whatever');

  group('extractErrorMessage', () {
    group('connection errors', () {
      const offlineMessage =
          'No internet connection. Please check your network and try again.';

      test(
          'Given DioExceptionType.connectionError, '
          'When extractErrorMessage called, '
          'Then returns offline message', () {
        final e = DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.connectionError,
        );

        expect(extractErrorMessage(e), offlineMessage);
      });

      test(
          'Given DioExceptionType.connectionTimeout, '
          'When extractErrorMessage called, '
          'Then returns offline message', () {
        final e = DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.connectionTimeout,
        );

        expect(extractErrorMessage(e), offlineMessage);
      });

      test(
          'Given DioExceptionType.receiveTimeout, '
          'When extractErrorMessage called, '
          'Then returns offline message', () {
        final e = DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.receiveTimeout,
        );

        expect(extractErrorMessage(e), offlineMessage);
      });

      test(
          'Given DioExceptionType.sendTimeout, '
          'When extractErrorMessage called, '
          'Then returns offline message', () {
        final e = DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.sendTimeout,
        );

        expect(extractErrorMessage(e), offlineMessage);
      });

      test(
          'Given connectionError with a response body containing detail, '
          'When extractErrorMessage called, '
          'Then offline message wins over detail extraction', () {
        // A connection-type error should never look at response.data — the
        // offline message is more accurate than whatever stale body Dio may
        // have attached.
        final e = DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.connectionError,
          response: Response(
            requestOptions: requestOptions,
            data: {'detail': 'Server says hi'},
          ),
        );

        expect(extractErrorMessage(e), offlineMessage);
      });
    });

    group('API errors with response body', () {
      test(
          'Given DioException with {detail: "..."}, '
          'When extractErrorMessage called, '
          'Then returns the detail string', () {
        final e = DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: requestOptions,
            statusCode: 400,
            data: {'detail': 'Username already taken'},
          ),
        );

        expect(extractErrorMessage(e), 'Username already taken');
      });

      test(
          'Given DioException with empty map response, '
          'When extractErrorMessage called, '
          'Then returns generic "An error occurred." fallback', () {
        // Map exists but has no `detail` key → null detail → fallback.
        final e = DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: requestOptions,
            statusCode: 500,
            data: const <String, dynamic>{},
          ),
        );

        expect(extractErrorMessage(e), 'An error occurred.');
      });

      test(
          'Given DioException with non-map response body (e.g. HTML), '
          'When extractErrorMessage called, '
          'Then returns the "please try again" fallback', () {
        // Some upstream proxy returned HTML — body is a String, not a Map.
        // Helper must not crash and must surface a friendly message.
        final e = DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: requestOptions,
            statusCode: 502,
            data: '<html>Bad Gateway</html>',
          ),
        );

        expect(extractErrorMessage(e), 'An error occurred. Please try again.');
      });

      test(
          'Given DioException with no response at all, '
          'When extractErrorMessage called, '
          'Then returns the "please try again" fallback', () {
        final e = DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.badResponse,
        );

        expect(extractErrorMessage(e), 'An error occurred. Please try again.');
      });

      test(
          'Given DioException with non-string detail value, '
          'When extractErrorMessage called, '
          'Then coerces it via toString', () {
        // FastAPI's HTTPException can carry a list/dict in detail when
        // validation errors are involved. Helper should not crash.
        final e = DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: requestOptions,
            statusCode: 422,
            data: const {
              'detail': [
                {'msg': 'field required'}
              ]
            },
          ),
        );

        // We don't assert the exact stringification — only that it's
        // non-empty and not the generic fallback, so future Dart changes to
        // List.toString don't break the test.
        final result = extractErrorMessage(e);
        expect(result, isNot('An error occurred.'));
        expect(result, isNot('An error occurred. Please try again.'));
        expect(result, contains('field required'));
      });
    });

    group('non-Dio inputs', () {
      test(
          'Given a plain Exception, '
          'When extractErrorMessage called, '
          'Then returns its toString()', () {
        final e = Exception('something blew up');
        expect(extractErrorMessage(e), 'Exception: something blew up');
      });

      test(
          'Given a String error, '
          'When extractErrorMessage called, '
          'Then returns the string itself', () {
        expect(extractErrorMessage('boom'), 'boom');
      });

      test(
          'Given null, '
          'When extractErrorMessage called, '
          'Then returns the generic fallback', () {
        expect(extractErrorMessage(null), 'An error occurred.');
      });
    });
  });

  // A reload that gets one of these replaces the content with the error view;
  // any other failure leaves the content on screen (ReloadKeepsContent).
  group('refusesContent', () {
    DioException answered(int status) => DioException.badResponse(
          statusCode: status,
          requestOptions: requestOptions,
          response: Response(requestOptions: requestOptions, statusCode: status),
        );

    for (final status in kNeverServeStaleFor) {
      test(
          'Given the server answered $status, '
          'When refusesContent called, '
          'Then the content is refused', () {
        expect(refusesContent(answered(status)), isTrue);
      });
    }

    for (final status in [400, 408, 409, 422, 429, 500, 502, 503]) {
      test(
          'Given the server answered $status, '
          'When refusesContent called, '
          'Then the content stays', () {
        expect(refusesContent(answered(status)), isFalse);
      });
    }

    test(
        'Given no answer at all (offline, a timeout), '
        'When refusesContent called, '
        'Then the content stays', () {
      for (final type in [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
      ]) {
        expect(
          refusesContent(DioException(requestOptions: requestOptions, type: type)),
          isFalse,
          reason: '$type',
        );
      }
    });

    test(
        'Given an error that is not an HTTP answer, '
        'When refusesContent called, '
        'Then the content stays', () {
      expect(refusesContent(const FormatException('bad body')), isFalse);
      expect(refusesContent(StateError('parse')), isFalse);
      expect(refusesContent(null), isFalse);
    });
  });
}
