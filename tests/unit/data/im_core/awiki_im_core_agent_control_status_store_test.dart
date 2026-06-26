import 'dart:convert';

import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/ports/message_core_port.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_agent_control_status_store.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('finds matching daemon status payload from message history', () async {
    final messages = _FakeMessages(<ChatMessage>[
      _message(
        payload: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime.command',
          'command_id': 'cmd-1',
          'daemon_agent_did': 'did:daemon',
          'runtime_agent_did': 'did:runtime',
          'state': 'running',
        },
      ),
    ]);

    final payload = await AwikiImCoreAgentControlStatusStore(messages: messages)
        .findStatusPayload(
          daemonAgentDid: 'did:daemon',
          runtimeAgentDid: 'did:runtime',
          requestId: 'cmd-1',
          statusScope: 'runtime.command',
        );

    expect(messages.requests.single.includeControlPayloads, isTrue);
    expect(messages.requests.single.thread, isA<AppDirectThreadRef>());
    expect(
      (messages.requests.single.thread as AppDirectThreadRef).peerDidOrHandle,
      'did:daemon',
    );
    expect(payload, isNotNull);
    expect(payload?['schema'], AgentControlPayloads.statusSchema);
    expect(payload?['state'], 'running');
  });

  test('skips malformed and unrelated cached messages', () async {
    final messages = _FakeMessages(<ChatMessage>[
      _message(rawPayload: 'not-json runtime.command cmd-1'),
      _message(
        senderDid: 'did:other-daemon',
        payload: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime.command',
          'request_id': 'cmd-1',
          'daemon_agent_did': 'did:other-daemon',
          'runtime_agent_did': 'did:runtime',
        },
      ),
      _message(
        payload: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime.command',
          'request_id': 'cmd-1',
          'daemon_agent_did': 'did:daemon',
          'runtime_agent_did': 'did:other-runtime',
        },
      ),
      _message(
        payload: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime.command',
          'request_id': 'cmd-1',
          'daemon_agent_did': 'did:daemon',
          'runtime_agent_did': 'did:runtime',
          'state': 'done',
        },
      ),
    ]);

    final payload = await AwikiImCoreAgentControlStatusStore(messages: messages)
        .findStatusPayload(
          daemonAgentDid: 'did:daemon',
          runtimeAgentDid: 'did:runtime',
          requestId: 'cmd-1',
          statusScope: 'runtime.command',
        );

    expect(payload?['state'], 'done');
  });

  test('returns null when no status payload matches', () async {
    final messages = _FakeMessages(<ChatMessage>[
      _message(
        payload: <String, Object?>{
          'schema': AgentControlPayloads.commandSchema,
          'status_scope': 'runtime.command',
          'request_id': 'cmd-1',
          'daemon_agent_did': 'did:daemon',
          'runtime_agent_did': 'did:runtime',
        },
      ),
      _message(
        payload: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime.other',
          'request_id': 'cmd-1',
          'daemon_agent_did': 'did:daemon',
          'runtime_agent_did': 'did:runtime',
        },
      ),
    ]);

    final payload = await AwikiImCoreAgentControlStatusStore(messages: messages)
        .findStatusPayload(
          daemonAgentDid: 'did:daemon',
          runtimeAgentDid: 'did:runtime',
          requestId: 'cmd-1',
          statusScope: 'runtime.command',
        );

    expect(payload, isNull);
  });

  test('returns null when message history cannot be loaded', () async {
    final payload =
        await AwikiImCoreAgentControlStatusStore(
          messages: _ThrowingMessages(),
        ).findStatusPayload(
          daemonAgentDid: 'did:daemon',
          runtimeAgentDid: 'did:runtime',
          requestId: 'cmd-1',
          statusScope: 'runtime.command',
        );

    expect(payload, isNull);
  });
}

ChatMessage _message({
  String senderDid = 'did:daemon',
  Map<String, Object?>? payload,
  String? rawPayload,
}) {
  final payloadJson = rawPayload ?? jsonEncode(payload);
  return ChatMessage(
    localId: 'msg-${payloadJson.hashCode}',
    threadId: 'dm:did:daemon',
    senderDid: senderDid,
    receiverDid: 'did:controller',
    content: '',
    originalType: 'application/json',
    payloadJson: payloadJson,
    createdAt: DateTime.now().toUtc(),
    isMine: false,
    sendState: MessageSendState.sent,
  );
}

class _HistoryRequest {
  const _HistoryRequest({
    required this.thread,
    required this.limit,
    required this.cursor,
    required this.includeControlPayloads,
  });

  final AppThreadRef thread;
  final int limit;
  final String? cursor;
  final bool includeControlPayloads;
}

class _FakeMessages implements MessageCorePort {
  _FakeMessages(this.history);

  final List<ChatMessage> history;
  final List<_HistoryRequest> requests = <_HistoryRequest>[];

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) async {
    requests.add(
      _HistoryRequest(
        thread: thread,
        limit: limit,
        cursor: cursor,
        includeControlPayloads: includeControlPayloads,
      ),
    );
    return history;
  }

  @override
  Future<AttachmentDownloadResult> downloadAttachment({
    required AppThreadRef thread,
    required String messageId,
    String? attachmentId,
    String? localPath,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) {
    throw UnimplementedError();
  }

  @override
  Future<ChatMessage> sendAttachment({
    required AppThreadRef thread,
    required AttachmentDraft attachment,
    String? caption,
    String? idempotencyKey,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) {
    throw UnimplementedError();
  }
}

class _ThrowingMessages extends _FakeMessages {
  _ThrowingMessages() : super(const <ChatMessage>[]);

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) async {
    throw StateError('history unavailable');
  }
}
