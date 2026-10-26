// core/api/api_connection_pool_io.dart — the connections every request to the
// API travels on, kept open between requests.
//
// A request needs an open, encrypted connection, and opening one costs a TCP
// and a TLS handshake: 90–125 ms to the first byte through Cloudflare's
// Brussels edge, against 40–60 ms on a connection already open (2026-10-24).
// Dio's own adapter closes an unused connection after 3 s, so nearly every
// save, every lock heartbeat and every notification poll paid for a new one.
//
// Keeping connections longer has a price, paid by retire(). dart:io drops a
// pooled connection only when its socket reports closing, never checks one
// before reusing it, and never retries a request: a connection that died
// without a word (the phone asleep, the app suspended, another network) takes
// the next request down with it. The pool therefore starts over whenever the
// app leaves the screen or the device changes network (main.dart).

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// How long an unused connection to the API stays open.
///
/// Longer than the 30 s lock heartbeat and the 60 s notification poll, so
/// either keeps the connection warm. Shorter than Cloudflare's HTTP/1.1
/// keep-alive (400 s, not configurable), so the app always closes first: at the
/// same moment, a request sent as Cloudflare closes would fail instead of
/// merely being slow. A constant, not a `--dart-define`, because it follows
/// Cloudflare's limit, which is the same for every build.
const kApiConnectionIdleTimeout = Duration(seconds: 120);

/// The one [HttpClientAdapter] behind [dio] and [bareDio] (api_client.dart).
class ApiConnectionPool with WidgetsBindingObserver
    implements HttpClientAdapter {
  ApiConnectionPool() {
    _open();
  }

  late HttpClient _client;
  late IOHttpClientAdapter _adapter;

  void _open() {
    final client = HttpClient()..idleTimeout = kApiConnectionIdleTimeout;
    _client = client;
    _adapter = IOHttpClientAdapter(createHttpClient: () => client);
  }

  @visibleForTesting
  Duration get idleTimeout => _client.idleTimeout;

  /// Sends later requests down new connections. Requests already under way
  /// finish on theirs, which then close.
  void retire() {
    // Not close(): it cancels a request still connecting, even force: false.
    _client.idleTimeout = Duration.zero;
    _open();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving and returning both pass hidden; the second finds an empty pool.
    if (state == AppLifecycleState.hidden) retire();
  }

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
