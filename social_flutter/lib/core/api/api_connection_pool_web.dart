// core/api/api_connection_pool_web.dart — on the web the browser keeps its
// own connections open and starts new ones when it needs to; there is nothing
// to tune or retire, so this only hands requests to Dio's browser adapter.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

/// The one [HttpClientAdapter] behind [dio] and [bareDio] (api_client.dart).
class ApiConnectionPool with WidgetsBindingObserver
    implements HttpClientAdapter {
  final HttpClientAdapter _adapter = HttpClientAdapter();

  void retire() {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      _adapter.fetch(options, requestStream, cancelFuture);

  @override
  void close({bool force = false}) => _adapter.close(force: force);
}
