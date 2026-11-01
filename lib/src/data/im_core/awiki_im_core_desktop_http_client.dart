import 'dart:async';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'awiki_im_core_desktop_network_preference.dart';

/// Native transport adapter; application authentication remains with its owner.
typedef DesktopNetworkSend =
    Future<core.AwikiNetworkResponse> Function({
      required String method,
      required String url,
      required Map<String, String> headers,
      required List<int> body,
      bool followRedirects,
      Future<void>? abortTrigger,
    });

class DesktopRuntimeHttpClient extends http.BaseClient {
  DesktopRuntimeHttpClient()
    : _initialize = DesktopNetworkPreference.instance.initialize,
      _transmit = core.AwikiDesktopNetwork.send;
  @visibleForTesting
  DesktopRuntimeHttpClient.forTesting({
    required Future<void> Function() initialize,
    required DesktopNetworkSend transmit,
  }) : _initialize = initialize,
       _transmit = transmit;
  final Future<void> Function() _initialize;
  final DesktopNetworkSend _transmit;
  bool _closed = false;
  final Set<Completer<void>> _aborters = {};
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Client closed');
    final abort = Completer<void>();
    _aborters.add(abort);
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(
        abortTrigger.then((_) {
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }
    try {
      await _initialize();
      final body = await request.finalize().toBytes();
      if (_closed || abort.isCompleted) {
        throw http.RequestAbortedException(request.url);
      }
      final response = await _transmit(
        method: request.method,
        url: request.url.toString(),
        headers: request.headers,
        body: body,
        followRedirects: request.followRedirects,
        abortTrigger: abort.future,
      );
      Stream<List<int>> chunks() async* {
        try {
          yield* response.body;
        } catch (_) {
          if (abort.isCompleted) {
            throw http.RequestAbortedException(request.url);
          }
          rethrow;
        } finally {
          _aborters.remove(abort);
          await response.close();
        }
      }

      return http.StreamedResponse(
        chunks(),
        response.statusCode,
        headers: response.headers,
        contentLength: int.tryParse(response.headers['content-length'] ?? ''),
        request: request,
      );
    } catch (_) {
      _aborters.remove(abort);
      if (abort.isCompleted) throw http.RequestAbortedException(request.url);
      rethrow;
    }
  }

  @override
  void close() {
    _closed = true;
    for (final abort in _aborters.toList()) {
      if (!abort.isCompleted) abort.complete();
    }
    _aborters.clear();
  }
}
