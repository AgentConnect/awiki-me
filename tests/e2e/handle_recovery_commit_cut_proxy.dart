// A test-only, exact-operation Commit proxy. It never emulates a backend result
// or records a request body; successful Commit is forwarded from awiki.info.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class HandleRecoveryCommitCutProxy {
  HandleRecoveryCommitCutProxy._(
    this._server,
    this._client,
    this._upstream,
    this._operationId,
    this._handle,
  );

  final HttpServer _server;
  final http.Client _client;
  final Uri _upstream;
  final String _operationId;
  final String _handle;
  bool committed = false;
  bool localCutObserved = false;
  int commitRequests = 0;
  int? upstreamStatus;
  String upstreamCode = 'none';
  String get safeDiagnostic =>
      'requests=$commitRequests,committed=$committed,local_cut=$localCutObserved,status=$upstreamStatus,code=$upstreamCode';

  String get endpoint => 'http://127.0.0.1:${_server.port}';

  static Future<HandleRecoveryCommitCutProxy> start({
    required Uri upstream,
    required String operationId,
    required String handle,
    http.Client? client,
  }) async {
    if (upstream.scheme != 'https' ||
        upstream.host != 'awiki.info' ||
        upstream.userInfo.isNotEmpty ||
        upstream.hasQuery ||
        upstream.hasFragment ||
        !RegExp(r'^[a-z0-9-]{2,32}$').hasMatch(handle) ||
        operationId.isEmpty) {
      throw StateError('recovery_cut_target_invalid');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = HandleRecoveryCommitCutProxy._(
      server,
      client ?? IOClient(HttpClient()..findProxy = (_) => 'DIRECT'),
      upstream,
      operationId,
      handle,
    );
    server.listen((request) => unawaited(proxy._handleRequest(request)));
    return proxy;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (committed &&
          request.method == 'GET' &&
          request.uri.path == '/.well-known/handle/$_handle') {
        localCutObserved = true;
        request.response.statusCode = HttpStatus.badGateway;
        return;
      }
      if (committed ||
          request.method != 'POST' ||
          request.uri.path != '/user-service/v1/did-auth/rpc') {
        request.response.statusCode = HttpStatus.badGateway;
        return;
      }
      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
        if (bytes.length > 262144) throw StateError('request_too_large');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map ||
          decoded['method'] != 'handle_recovery_commit_v4' ||
          decoded['params'] is! Map ||
          decoded['params']['intent'] is! Map ||
          decoded['params']['intent']['operation_id'] != _operationId) {
        request.response.statusCode = HttpStatus.badGateway;
        return;
      }
      commitRequests++;
      final response = await _client.post(
        _upstream.resolve(request.uri.path),
        body: bytes,
        headers: {
          'Content-Type': 'application/json',
          if (request.headers.value('x-awiki-client-version')
              case final version?)
            'X-AWiki-Client-Version': version,
        },
      );
      upstreamStatus = response.statusCode;
      final body = jsonDecode(response.body);
      final error = body is Map ? body['error'] : null;
      final data = error is Map ? error['data'] : null;
      final code = data is Map ? data['code'] : null;
      const known = {
        'invalid_request',
        'capability_disabled',
        'grant_expired',
        'grant_invalid',
        'proof_invalid',
        'temporarily_unavailable',
        'state_changed_requires_new_operation',
        'intent_conflict',
      };
      upstreamCode = known.contains(code)
          ? code as String
          : error == null
          ? 'none'
          : 'other';
      committed =
          response.statusCode == 200 &&
          body is Map &&
          body['error'] == null &&
          body['result'] is Map &&
          body['result']['operation_id'] == _operationId;
      request.response.statusCode = response.statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.add(response.bodyBytes);
    } catch (_) {
      request.response.statusCode = HttpStatus.badGateway;
    } finally {
      await request.response.close();
    }
  }

  Future<void> close() async {
    await _server.close(force: true);
    _client.close();
  }
}
