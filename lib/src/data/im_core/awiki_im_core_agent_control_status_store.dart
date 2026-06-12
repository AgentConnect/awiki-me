import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../application/agent/agent_control_status_store.dart';
import '../../domain/entities/agent/agent_control_payloads.dart';

class AwikiImCoreAgentControlStatusStore implements AgentControlStatusStore {
  const AwikiImCoreAgentControlStatusStore({required this.sqlitePath});

  final String sqlitePath;

  @override
  Future<Map<String, Object?>?> findStatusPayload({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String requestId,
    required String statusScope,
  }) async {
    Database? db;
    try {
      db = await openReadOnlyDatabase(sqlitePath);
      final rows = await db.query(
        'messages',
        columns: const <String>['content'],
        where: '''
content_type = ?
AND direction = ?
AND sender_did = ?
AND content LIKE ?
AND content LIKE ?
''',
        whereArgs: <Object?>[
          'application/json',
          0,
          daemonAgentDid,
          '%$statusScope%',
          '%$requestId%',
        ],
        limit: 10,
      );
      for (final row in rows) {
        final payload = _decodePayload(row['content']);
        if (payload == null) {
          continue;
        }
        if (_matchesStatusPayload(
          payload,
          daemonAgentDid: daemonAgentDid,
          runtimeAgentDid: runtimeAgentDid,
          requestId: requestId,
          statusScope: statusScope,
        )) {
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

bool _matchesStatusPayload(
  Map<String, Object?> payload, {
  required String daemonAgentDid,
  required String runtimeAgentDid,
  required String requestId,
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
  if (payloadRequestId != requestId) {
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

String? _string(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
