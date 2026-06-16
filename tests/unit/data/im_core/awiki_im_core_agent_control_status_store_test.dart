import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/data/im_core/awiki_im_core_agent_control_status_store.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDir;
  late String databasePath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDir = await Directory.systemTemp.createTemp(
      'awiki_agent_control_status_store_test_',
    );
    await databaseFactory.setDatabasesPath(databaseDir.path);
    databasePath = '${databaseDir.path}/messages.db';
  });

  tearDown(() async {
    if (await databaseDir.exists()) {
      await databaseDir.delete(recursive: true);
    }
  });

  test('finds matching daemon status payload from message cache', () async {
    await _withMessagesDatabase(databasePath, (db) async {
      await _insertMessage(
        db,
        content: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime.command',
          'command_id': 'cmd-1',
          'daemon_agent_did': 'did:daemon',
          'runtime_agent_did': 'did:runtime',
          'state': 'running',
        },
      );
    });

    final payload =
        await AwikiImCoreAgentControlStatusStore(
          sqlitePath: databasePath,
        ).findStatusPayload(
          daemonAgentDid: 'did:daemon',
          runtimeAgentDid: 'did:runtime',
          requestId: 'cmd-1',
          statusScope: 'runtime.command',
        );

    expect(payload, isNotNull);
    expect(payload?['schema'], AgentControlPayloads.statusSchema);
    expect(payload?['state'], 'running');
  });

  test('skips malformed and unrelated cached messages', () async {
    await _withMessagesDatabase(databasePath, (db) async {
      await _insertMessage(db, content: 'not-json runtime.command cmd-1');
      await _insertMessage(
        db,
        senderDid: 'did:other-daemon',
        content: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime.command',
          'request_id': 'cmd-1',
          'daemon_agent_did': 'did:other-daemon',
          'runtime_agent_did': 'did:runtime',
        },
      );
      await _insertMessage(
        db,
        direction: 1,
        content: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime.command',
          'request_id': 'cmd-1',
          'daemon_agent_did': 'did:daemon',
          'runtime_agent_did': 'did:runtime',
        },
      );
      await _insertMessage(
        db,
        contentType: 'text/plain',
        content: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime.command',
          'request_id': 'cmd-1',
          'daemon_agent_did': 'did:daemon',
          'runtime_agent_did': 'did:runtime',
        },
      );
      await _insertMessage(
        db,
        content: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime.command',
          'request_id': 'cmd-1',
          'daemon_agent_did': 'did:daemon',
          'runtime_agent_did': 'did:other-runtime',
        },
      );
      await _insertMessage(
        db,
        content: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime.command',
          'request_id': 'cmd-1',
          'daemon_agent_did': 'did:daemon',
          'runtime_agent_did': 'did:runtime',
          'state': 'done',
        },
      );
    });

    final payload =
        await AwikiImCoreAgentControlStatusStore(
          sqlitePath: databasePath,
        ).findStatusPayload(
          daemonAgentDid: 'did:daemon',
          runtimeAgentDid: 'did:runtime',
          requestId: 'cmd-1',
          statusScope: 'runtime.command',
        );

    expect(payload?['state'], 'done');
  });

  test('returns null when no status payload matches', () async {
    await _withMessagesDatabase(databasePath, (db) async {
      await _insertMessage(
        db,
        content: <String, Object?>{
          'schema': AgentControlPayloads.commandSchema,
          'status_scope': 'runtime.command',
          'request_id': 'cmd-1',
          'daemon_agent_did': 'did:daemon',
          'runtime_agent_did': 'did:runtime',
        },
      );
      await _insertMessage(
        db,
        content: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime.other',
          'request_id': 'cmd-1',
          'daemon_agent_did': 'did:daemon',
          'runtime_agent_did': 'did:runtime',
        },
      );
    });

    final payload =
        await AwikiImCoreAgentControlStatusStore(
          sqlitePath: databasePath,
        ).findStatusPayload(
          daemonAgentDid: 'did:daemon',
          runtimeAgentDid: 'did:runtime',
          requestId: 'cmd-1',
          statusScope: 'runtime.command',
        );

    expect(payload, isNull);
  });

  test('returns null when sqlite cache cannot be opened', () async {
    final payload =
        await AwikiImCoreAgentControlStatusStore(
          sqlitePath: databasePath,
        ).findStatusPayload(
          daemonAgentDid: 'did:daemon',
          runtimeAgentDid: 'did:runtime',
          requestId: 'cmd-1',
          statusScope: 'runtime.command',
        );

    expect(payload, isNull);
  });
}

Future<void> _withMessagesDatabase(
  String path,
  Future<void> Function(Database db) callback,
) async {
  final db = await openDatabase(
    path,
    version: 1,
    onCreate: (database, _) async {
      await database.execute('''
        CREATE TABLE messages (
          content_type TEXT NOT NULL,
          direction INTEGER NOT NULL,
          sender_did TEXT NOT NULL,
          content TEXT
        )
      ''');
    },
  );
  try {
    await callback(db);
  } finally {
    await db.close();
  }
}

Future<void> _insertMessage(
  Database db, {
  String contentType = 'application/json',
  int direction = 0,
  String senderDid = 'did:daemon',
  required Object content,
}) async {
  await db.insert('messages', <String, Object?>{
    'content_type': contentType,
    'direction': direction,
    'sender_did': senderDid,
    'content': content is String ? content : jsonEncode(content),
  });
}
