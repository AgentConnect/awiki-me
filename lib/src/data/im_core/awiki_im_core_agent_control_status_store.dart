import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../application/agent/agent_control_status_store.dart';
import '../local/sqflite_desktop_init.dart';
import '../../domain/entities/agent/agent_control_payloads.dart';

class AwikiImCoreAgentControlStatusStore implements AgentControlStatusStore {
  const AwikiImCoreAgentControlStatusStore({required this.sqlitePath});

  final String sqlitePath;

  @override
  Future<Map<String, Object?>?> findLatestDaemonStatusPayload({
    required String daemonAgentDid,
  }) {
    return _findStatusPayload(
      daemonAgentDid: daemonAgentDid,
      statusScopes: const <String>{'daemon', 'snapshot'},
      matches: (payload) =>
          _matchesDaemonStatusPayload(payload, daemonAgentDid: daemonAgentDid),
    );
  }

  @override
  Future<Map<String, Object?>?> findDaemonStatusPayload({
    required String daemonAgentDid,
    required String requestId,
  }) {
    return _findStatusPayload(
      daemonAgentDid: daemonAgentDid,
      requestId: requestId,
      statusScopes: const <String>{'daemon', 'snapshot'},
      matches: (payload) =>
          _matchesDaemonStatusPayload(payload, daemonAgentDid: daemonAgentDid),
    );
  }

  @override
  Future<Map<String, Object?>?> findStatusPayload({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String requestId,
    required String statusScope,
  }) {
    return _findStatusPayload(
      daemonAgentDid: daemonAgentDid,
      requestId: requestId,
      statusScopes: <String>{statusScope},
      matches: (payload) => _matchesRuntimeStatusPayload(
        payload,
        daemonAgentDid: daemonAgentDid,
        runtimeAgentDid: runtimeAgentDid,
        requestId: requestId,
        statusScope: statusScope,
      ),
    );
  }

  Future<Map<String, Object?>?> _findStatusPayload({
    required String daemonAgentDid,
    String? requestId,
    required Set<String> statusScopes,
    required bool Function(Map<String, Object?> payload) matches,
  }) async {
    Database? db;
    try {
      ensureSqfliteDesktopInitialized();
      db = await openReadOnlyDatabase(sqlitePath);
      final rows = await db.query(
        'messages',
        columns: const <String>['content'],
        where:
            '''
content_type = ?
AND direction = ?
AND sender_did = ?
${requestId == null ? '' : 'AND content LIKE ?'}
''',
        whereArgs: <Object?>[
          'application/json',
          0,
          daemonAgentDid,
          if (requestId != null) '%$requestId%',
        ],
        orderBy: 'COALESCE(sent_at, stored_at) DESC',
        limit: 50,
      );
      for (final row in rows) {
        final payload = _decodePayload(row['content']);
        if (payload == null) {
          continue;
        }
        final statusScope = _string(payload['status_scope']);
        if (statusScope != null &&
            statusScopes.contains(statusScope) &&
            _matchesBaseStatusPayload(
              payload,
              requestId: requestId,
              statusScope: statusScope,
            ) &&
            matches(payload)) {
          return payload;
        }
      }
      return null;
    } on Object {
      return null;
    } finally {
      await db?.close();
    }
  }
}

Map<String, Object?>? _decodePayload(Object? content) {
  final raw = content?.toString();
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    return decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  } on Object {
    return null;
  }
}

bool _matchesBaseStatusPayload(
  Map<String, Object?> payload, {
  String? requestId,
  required String statusScope,
}) {
  if (_string(payload['schema']) != AgentControlPayloads.statusSchema) {
    return false;
  }
  if (_string(payload['status_scope']) != statusScope) {
    return false;
  }
  final payloadRequestId =
      _string(payload['request_id']) ?? _string(payload['command_id']);
  if (requestId != null && payloadRequestId != requestId) {
    return false;
  }
  return true;
}

bool _matchesDaemonStatusPayload(
  Map<String, Object?> payload, {
  required String daemonAgentDid,
}) {
  final payloadDaemonDid =
      _string(payload['daemon_agent_did']) ??
      _string(_readMap(payload['daemon'])['agent_did']);
  return payloadDaemonDid == daemonAgentDid;
}

bool _matchesRuntimeStatusPayload(
  Map<String, Object?> payload, {
  required String daemonAgentDid,
  required String runtimeAgentDid,
  required String requestId,
  required String statusScope,
}) {
  if (!_matchesBaseStatusPayload(
    payload,
    requestId: requestId,
    statusScope: statusScope,
  )) {
    return false;
  }
  if (_string(payload['daemon_agent_did']) != daemonAgentDid) {
    return false;
  }
  if (_string(payload['runtime_agent_did']) != runtimeAgentDid) {
    return false;
  }
  return true;
}

Map<String, Object?> _readMap(Object? value) {
  if (value is Map) {
    return value.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  return const <String, Object?>{};
}

String? _string(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
