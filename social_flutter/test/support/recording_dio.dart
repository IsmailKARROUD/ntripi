// test/support/recording_dio.dart — a Dio on http_mock_adapter that logs every
// request it sends, and can hold one until the test lets it through.
//
// The log is what turns "one request" and "no GET after the save" into exact
// assertions rather than an absence of errors; a held request is what lets a
// test look at the screen while a reply has not landed yet.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:ntripi/core/api/api_endpoints.dart';

class RecordingDio {
  RecordingDio() : dio = Dio(BaseOptions(baseUrl: kApiBaseUrl)) {
    adapter = DioAdapter(dio: dio);
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) async {
        sent.add(options);
        final held = _held.indexWhere((h) => _matches(h.path, options.path));
        if (held >= 0) await _held.removeAt(held).gate.future;
        handler.next(options);
      }),
    );
  }

  final Dio dio;
  late final DioAdapter adapter;

  final List<({Pattern path, Completer<void> gate})> _held = [];

  /// Holds the next request to [path] — exact for a String, any match for a
  /// RegExp — until the returned completer completes. Its reply is whatever
  /// the adapter answers that route with at that moment.
  Completer<void> hold(Pattern path) {
    final gate = Completer<void>();
    _held.add((path: path, gate: gate));
    return gate;
  }

  static bool _matches(Pattern pattern, String path) =>
      pattern is RegExp ? pattern.hasMatch(path) : pattern == path;

  /// Every request sent, in order.
  final List<RequestOptions> sent = [];

  /// `'<METHOD> <path>'` per request sent, in order.
  List<String> get lines => [for (final o in sent) '${o.method} ${o.path}'];
}
