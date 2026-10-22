// test/support/recording_dio.dart — a Dio on http_mock_adapter that logs every
// request it sends.
//
// The log is what turns "one request" and "no GET after the save" into exact
// assertions rather than an absence of errors.

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:ntripi/core/api/api_endpoints.dart';

class RecordingDio {
  RecordingDio() : dio = Dio(BaseOptions(baseUrl: kApiBaseUrl)) {
    adapter = DioAdapter(dio: dio);
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sent.add(options);
      handler.next(options);
    }));
  }

  final Dio dio;
  late final DioAdapter adapter;

  /// Every request sent, in order.
  final List<RequestOptions> sent = [];

  /// `'<METHOD> <path>'` per request sent, in order.
  List<String> get lines => [for (final o in sent) '${o.method} ${o.path}'];
}
