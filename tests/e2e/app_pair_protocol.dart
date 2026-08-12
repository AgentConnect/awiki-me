// [INPUT]: Loopback-authenticated App role checkpoints and transient SAS submissions.
// [OUTPUT]: In-memory Join/functional coordination and redacted subprocess diagnostics without persisting secrets.
// [POS]: Test orchestration only; it never calls AWiki product APIs or advances product state.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const Set<String> appPairRoles = <String>{'admin', 'joiner'};
const Set<String> _forbiddenCheckpointKeys = <String>{
  'otp',
  'sas',
  'token',
  'proof',
  'challenge',
  'authorization',
};
const Map<String, Set<String>> _checkpointFieldsByRoute = <String, Set<String>>{
  'admin\u0000ready': <String>{'did', 'handle', 'adminDeviceId'},
  'joiner\u0000pending': <String>{'joinSessionId', 'joinedDeviceId'},
  'admin\u0000verification_started': <String>{},
  'joiner\u0000authorized': <String>{'adminDeviceId', 'joinedDeviceId'},
  'admin\u0000complete': <String>{},
  'joiner\u0000functional_ready': <String>{},
  'admin\u0000content_fixture_ready': <String>{
    'peerDid',
    'directConversationId',
    'groupDid',
    'groupConversationId',
    'preGroupMessageId',
    'preAttachmentMessageId',
    'preAttachmentId',
  },
  'joiner\u0000content_prejoin_absent': <String>{},
  'admin\u0000content_postjoin_sent': <String>{
    'groupMessageId',
    'attachmentMessageId',
    'attachmentId',
  },
  'joiner\u0000content_group_reverse_sent': <String>{'messageId'},
  'joiner\u0000content_unread_baseline_ready': <String>{},
  'admin\u0000content_incoming_sent': <String>{
    'directMessageId',
    'groupMessageId',
  },
  'joiner\u0000content_direct_read_committed': <String>{},
  'admin\u0000content_direct_read_converged': <String>{},
  'joiner\u0000content_group_read_committed': <String>{},
  'admin\u0000content_group_read_converged': <String>{},
  'joiner\u0000functional_tail_only_verified': <String>{},
  'admin\u0000functional_agents_created': <String>{
    'daemonDid',
    'daemonHandle',
    'codexDid',
    'codexHandle',
    'claudeDid',
    'claudeHandle',
    'archiveDid',
    'archiveHandle',
  },
  'joiner\u0000functional_agents_converged': <String>{},
  'joiner\u0000functional_agent_prompt_sent': <String>{
    'conversationId',
    'messageId',
  },
  'admin\u0000functional_agent_prompt_visible': <String>{},
  'admin\u0000functional_peer_ready': <String>{
    'peerDid',
    'peerHandle',
    'conversationId',
    'historicalMessageId',
    'historicalText',
  },
  'admin\u0000functional_outbound_sent': <String>{
    'conversationId',
    'messageId',
  },
  'joiner\u0000functional_own_sync_visible': <String>{},
  'joiner\u0000functional_joiner_outbound_sent': <String>{'messageId'},
  'admin\u0000functional_joiner_outbound_visible': <String>{},
  'admin\u0000functional_reply_sent': <String>{'messageId'},
  'joiner\u0000functional_reply_visible': <String>{},
  'admin\u0000functional_read_observer_ready': <String>{},
  'joiner\u0000functional_read_observer_ready': <String>{},
  'admin\u0000functional_read_message_sent': <String>{'messageId'},
  'joiner\u0000functional_read_unread_visible': <String>{},
  'joiner\u0000functional_read_committed': <String>{},
  'admin\u0000functional_read_converged': <String>{},
  'joiner\u0000functional_offline_ready': <String>{},
  'admin\u0000functional_recovery_gap_prepared': <String>{'messageId'},
  'joiner\u0000functional_recovery_completed': <String>{},
  'admin\u0000functional_post_anchor_sent': <String>{'messageId'},
  'joiner\u0000functional_post_anchor_visible': <String>{},
  'joiner\u0000functional_agent_observer_ready': <String>{},
  'joiner\u0000account_state_stage4_baseline_ready': <String>{},
  'admin\u0000account_state_agent_renamed': <String>{'agentDid', 'displayName'},
  'joiner\u0000account_state_agent_rename_converged': <String>{},
  'admin\u0000account_state_agent_unbound': <String>{'agentDid'},
  'joiner\u0000account_state_agent_unbind_converged': <String>{},
  'admin\u0000account_state_archive_fixture_ready': <String>{
    'agentDid',
    'displayName',
    'handle',
  },
  'joiner\u0000account_state_archive_fixture_converged_active': <String>{},
  'admin\u0000account_state_archive_product_delete_completed': <String>{
    'agentDid',
  },
  'joiner\u0000account_state_archive_converged': <String>{},
  'admin\u0000account_state_agent_deleted': <String>{'agentDid'},
  'joiner\u0000account_state_agent_delete_converged': <String>{},
  'admin\u0000account_state_profile_updated': <String>{'displayName', 'bio'},
  'joiner\u0000account_state_profile_converged': <String>{},
  'admin\u0000account_state_isolation_fixture_ready': <String>{
    'agentDid',
    'displayName',
  },
  'joiner\u0000account_state_isolation_fixture_converged': <String>{},
  'admin\u0000account_state_isolation_mutated': <String>{
    'agentDid',
    'oldDisplayName',
    'newDisplayName',
    'profileDisplayName',
    'messageId',
    'receiptId',
  },
  'joiner\u0000account_state_isolation_recovered': <String>{},
  'admin\u0000account_state_registry_ready': <String>{},
  'joiner\u0000account_state_registry_observer_ready': <String>{},
  'admin\u0000account_state_registry_revoked': <String>{},
  'joiner\u0000account_state_registry_fence_observed': <String>{},
  'admin\u0000account_state_post_revoke_message_committed': <String>{
    'messageId',
  },
  'joiner\u0000account_state_revoked_device_auth_fenced': <String>{},
};

String safeCliFailureDiagnostic({
  required int exitCode,
  required Object? stdout,
  required Object? stderr,
}) {
  String? errorCode;
  String? serviceCode;
  for (final output in <Object?>[stderr, stdout]) {
    if (output == null || output.toString().trim().isEmpty) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(output.toString());
    } on FormatException {
      continue;
    }
    if (decoded is! Map || decoded['error'] is! Map) continue;
    final error = decoded['error'] as Map;
    final candidateCode = error['code']?.toString();
    if (_isSafeDiagnosticCode(candidateCode, requireNamespace: false)) {
      errorCode = candidateCode;
    }
    final details = error['details'];
    final candidateServiceCode = details is Map
        ? details['service_code']?.toString()
        : null;
    if (_isSafeDiagnosticCode(candidateServiceCode, requireNamespace: true)) {
      serviceCode = candidateServiceCode;
    }
    break;
  }
  return <String>[
    'exit=$exitCode',
    if (errorCode != null) 'code=$errorCode',
    if (serviceCode != null) 'serviceCode=$serviceCode',
  ].join(', ');
}

bool _isSafeDiagnosticCode(String? value, {required bool requireNamespace}) {
  if (value == null || value.isEmpty || value.length > 96) return false;
  if (!RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(value)) return false;
  return !requireNamespace || value.contains('.');
}

class AppPairCoordinatorServer {
  AppPairCoordinatorServer._(this._server, this.token);

  final HttpServer _server;
  final String token;
  final Map<String, Map<String, Object?>> _checkpoints =
      <String, Map<String, Object?>>{};
  final Map<String, String> _sasByRole = <String, String>{};
  StreamSubscription<HttpRequest>? _subscription;

  Uri get endpoint => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
  );

  static Future<AppPairCoordinatorServer> start({required String token}) async {
    if (token.trim().length < 32) {
      throw const AppPairProtocolException(
        'The App-pair coordinator token is too short.',
      );
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final coordinator = AppPairCoordinatorServer._(server, token);
    coordinator._subscription = server.listen(coordinator._handle);
    return coordinator;
  }

  Future<void> close() async {
    _sasByRole.clear();
    _checkpoints.clear();
    await _subscription?.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.headers.value(HttpHeaders.authorizationHeader) !=
          'Bearer $token') {
        await _json(request.response, HttpStatus.unauthorized, const {
          'error': 'unauthorized',
        });
        return;
      }
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/health') {
        await _json(request.response, HttpStatus.ok, const {'ready': true});
        return;
      }
      if (path == '/v1/checkpoint') {
        if (request.method == 'POST') {
          await _publishCheckpoint(request);
          return;
        }
        if (request.method == 'GET') {
          await _readCheckpoint(request);
          return;
        }
      }
      if (path == '/v1/sas') {
        if (request.method == 'POST') {
          await _submitSas(request);
          return;
        }
        if (request.method == 'GET') {
          await _readSasResult(request);
          return;
        }
      }
      await _json(request.response, HttpStatus.notFound, const {
        'error': 'not_found',
      });
    } on AppPairProtocolException catch (error) {
      await _json(request.response, HttpStatus.badRequest, {
        'error': error.message,
      });
    } on Object {
      await _json(request.response, HttpStatus.internalServerError, const {
        'error': 'internal_error',
      });
    }
  }

  Future<void> _publishCheckpoint(HttpRequest request) async {
    final body = await _readObject(request);
    final role = _role(body['role']);
    final phase = _phase(body['phase']);
    final rawData = body['data'];
    if (rawData is! Map) {
      throw const AppPairProtocolException(
        'Checkpoint data must be an object.',
      );
    }
    final data = <String, Object?>{
      for (final entry in rawData.entries) entry.key.toString(): entry.value,
    };
    _validateCheckpointData(data);
    _validateCheckpointRoute(role, phase, data);
    _checkpoints['$role\u0000$phase'] = Map<String, Object?>.unmodifiable(data);
    await _json(request.response, HttpStatus.ok, const {'accepted': true});
  }

  Future<void> _readCheckpoint(HttpRequest request) async {
    final role = _role(request.uri.queryParameters['role']);
    final phase = _phase(request.uri.queryParameters['phase']);
    final data = _checkpoints['$role\u0000$phase'];
    if (data == null) {
      await _json(request.response, HttpStatus.notFound, const {
        'ready': false,
      });
      return;
    }
    await _json(request.response, HttpStatus.ok, {'ready': true, 'data': data});
  }

  Future<void> _submitSas(HttpRequest request) async {
    final body = await _readObject(request);
    final role = _role(body['role']);
    final sas = body['sas'];
    if (sas is! String || !RegExp(r'^[0-9]{6}$').hasMatch(sas)) {
      throw const AppPairProtocolException('The submitted SAS is invalid.');
    }
    _sasByRole[role] = sas;
    await _json(request.response, HttpStatus.ok, _sasResult());
  }

  Future<void> _readSasResult(HttpRequest request) async {
    await _json(request.response, HttpStatus.ok, _sasResult());
  }

  Map<String, Object?> _sasResult() {
    final admin = _sasByRole['admin'];
    final joiner = _sasByRole['joiner'];
    if (admin == null || joiner == null) {
      return const <String, Object?>{'ready': false};
    }
    return <String, Object?>{
      'ready': true,
      'matched': _constantTimeAsciiEquals(admin, joiner),
    };
  }
}

class AppPairCoordinatorClient {
  const AppPairCoordinatorClient({required this.endpoint, required this.token});

  final Uri endpoint;
  final String token;

  Future<void> publish(
    String role,
    String phase, {
    Map<String, Object?> data = const <String, Object?>{},
  }) async {
    _role(role);
    _phase(phase);
    _validateCheckpointData(data);
    _validateCheckpointRoute(role, phase, data);
    final response = await _request(
      'POST',
      '/v1/checkpoint',
      body: <String, Object?>{'role': role, 'phase': phase, 'data': data},
    );
    if (response.statusCode != HttpStatus.ok) {
      throw const AppPairProtocolException(
        'The App-pair checkpoint was rejected.',
      );
    }
  }

  Future<Map<String, Object?>> waitFor(
    String role,
    String phase, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    _role(role);
    _phase(phase);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final response = await _request(
        'GET',
        '/v1/checkpoint',
        query: <String, String>{'role': role, 'phase': phase},
      );
      if (response.statusCode == HttpStatus.ok) {
        final decoded = _decodeObject(response.body);
        final data = decoded['data'];
        if (data is Map) {
          return <String, Object?>{
            for (final entry in data.entries) entry.key.toString(): entry.value,
          };
        }
        throw const AppPairProtocolException(
          'The App-pair checkpoint response was invalid.',
        );
      }
      if (response.statusCode != HttpStatus.notFound) {
        throw const AppPairProtocolException(
          'The App-pair checkpoint read failed.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw AppPairProtocolException('Timed out waiting for $role/$phase.');
  }

  Future<bool> submitAndCompareSas(
    String role,
    String sas, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    _role(role);
    if (!RegExp(r'^[0-9]{6}$').hasMatch(sas)) {
      throw const AppPairProtocolException('The submitted SAS is invalid.');
    }
    final submitted = await _request(
      'POST',
      '/v1/sas',
      body: <String, Object?>{'role': role, 'sas': sas},
    );
    if (submitted.statusCode != HttpStatus.ok) {
      throw const AppPairProtocolException(
        'The App-pair SAS submission failed.',
      );
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final response = await _request('GET', '/v1/sas');
      if (response.statusCode != HttpStatus.ok) {
        throw const AppPairProtocolException(
          'The App-pair SAS comparison failed.',
        );
      }
      final result = _decodeObject(response.body);
      if (result['ready'] == true) {
        return result['matched'] == true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw const AppPairProtocolException(
      'Timed out waiting for both App SAS submissions.',
    );
  }

  Future<_AppPairHttpResponse> _request(
    String method,
    String path, {
    Map<String, String> query = const <String, String>{},
    Map<String, Object?>? body,
  }) async {
    final client = HttpClient();
    try {
      final uri = endpoint.replace(path: path, queryParameters: query);
      final request = await client.openUrl(method, uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.contentType = ContentType.json;
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();
      return _AppPairHttpResponse(response.statusCode, responseBody);
    } on AppPairProtocolException {
      rethrow;
    } on Object {
      throw const AppPairProtocolException(
        'The App-pair coordinator is unavailable.',
      );
    } finally {
      client.close(force: true);
    }
  }
}

class _AppPairHttpResponse {
  const _AppPairHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

Future<Map<String, Object?>> _readObject(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  if (body.length > 16 * 1024) {
    throw const AppPairProtocolException('The request body is too large.');
  }
  return _decodeObject(body);
}

Map<String, Object?> _decodeObject(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const AppPairProtocolException('The JSON body is invalid.');
  }
  if (decoded is! Map) {
    throw const AppPairProtocolException('The JSON body must be an object.');
  }
  return <String, Object?>{
    for (final entry in decoded.entries) entry.key.toString(): entry.value,
  };
}

String _role(Object? value) {
  if (value is! String || !appPairRoles.contains(value)) {
    throw const AppPairProtocolException('The App-pair role is invalid.');
  }
  return value;
}

String _phase(Object? value) {
  if (value is! String || !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(value)) {
    throw const AppPairProtocolException('The App-pair phase is invalid.');
  }
  return value;
}

void _validateCheckpointData(Map<String, Object?> data) {
  if (data.length > 16 || _containsForbiddenCheckpointValue(data)) {
    throw const AppPairProtocolException(
      'The checkpoint contains an unapproved field.',
    );
  }
  final encoded = jsonEncode(data);
  if (encoded.length > 8 * 1024) {
    throw const AppPairProtocolException('The checkpoint is too large.');
  }
}

void _validateCheckpointRoute(
  String role,
  String phase,
  Map<String, Object?> data,
) {
  final allowed = _checkpointFieldsByRoute['$role\u0000$phase'];
  if (allowed == null ||
      data.length != allowed.length ||
      !data.keys.toSet().containsAll(allowed)) {
    throw const AppPairProtocolException(
      'The checkpoint route or shape is not approved.',
    );
  }
}

bool _containsForbiddenCheckpointValue(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      if (_forbiddenCheckpointKeys.any(key.contains) ||
          _containsForbiddenCheckpointValue(entry.value)) {
        return true;
      }
    }
    return false;
  }
  if (value is Iterable) {
    return value.any(_containsForbiddenCheckpointValue);
  }
  return value is String && RegExp(r'^[0-9]{6}$').hasMatch(value);
}

Future<void> _json(
  HttpResponse response,
  int status,
  Map<String, Object?> body,
) async {
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

bool _constantTimeAsciiEquals(String left, String right) {
  var mismatch = left.length ^ right.length;
  final length = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < length; index += 1) {
    final leftUnit = index < left.length ? left.codeUnitAt(index) : 0;
    final rightUnit = index < right.length ? right.codeUnitAt(index) : 0;
    mismatch |= leftUnit ^ rightUnit;
  }
  return mismatch == 0;
}

class AppPairProtocolException implements Exception {
  const AppPairProtocolException(this.message);

  final String message;
}
