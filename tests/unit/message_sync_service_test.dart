import 'package:awiki_me/src/application/message_sync_service.dart';
import 'package:awiki_me/src/application/models/app_conversation_read_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/ports/message_sync_core_port.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'receive preserves partial Core outcome and normalizes the trigger',
    () async {
      final core = _ReceiveCore();
      final service = ImCoreMessageSyncService(sync: core);
      final result = await service.receiveNow(
        reason: ' realtime_message ',
        limit: 7,
      );
      expect(core.receiveReason, 'websocket_hint');
      expect(core.receiveLimit, 7);
      expect(result, same(core.outcome));
      expect(result.complete, isFalse);
      expect(result.errorCode, 'transport_unavailable');
    },
  );

  test(
    'processing and local recovery retain Core-owned session and references',
    () async {
      final core = _ReceiveCore();
      final service = ImCoreMessageSyncService(sync: core);
      final references = {'push-opaque-reference', 'message-opaque-reference'};
      expect(await service.openProcessingSession(), same(core.processing));
      final result = await service.findLocalIncoming(references);
      expect(core.references, references);
      expect(result, same(core.incoming));
      expect(result.single.message.remoteId, 'recovered-message');
    },
  );

  test('receive APIs fail closed when the Core capability is absent', () {
    final service = ImCoreMessageSyncService(
      sync: _ThreadOnlyMessageSyncCore(),
    );
    expect(() => service.receiveNow(reason: 'startup'), throwsUnsupportedError);
    expect(service.openProcessingSession, throwsUnsupportedError);
    expect(
      () => service.findLocalIncoming({'reference'}),
      throwsUnsupportedError,
    );
  });

  test(
    'receive failure is propagated without a successful empty result',
    () async {
      final core = _ReceiveCore()..failure = StateError('core-failed');
      final service = ImCoreMessageSyncService(sync: core);
      await expectLater(
        service.receiveNow(reason: 'startup'),
        throwsA(same(core.failure)),
      );
      await expectLater(
        service.openProcessingSession(),
        throwsA(same(core.failure)),
      );
      await expectLater(
        service.findLocalIncoming({'reference'}),
        throwsA(same(core.failure)),
      );
    },
  );

  test('sync without a cursor preserves first-page defaults', () async {
    final core = _FakeMessageSyncCore();
    final service = ImCoreMessageSyncService(sync: core);
    await service.syncThreadAfter(thread: const AppThreadRef.direct('did:bob'));
    await service.syncConversationAfter(
      conversation: AppConversationReadRef.fromConversationId(
        'canonical-conversation',
      ),
    );
    expect(core.threadAfterSeqs, [null]);
    expect(core.threadAfterLimits, [100]);
    expect(core.conversationAfterSeqs, [null]);
    expect(core.conversationAfterLimits, [100]);
    expect(maxServerSequenceForMessages([]), isNull);
    expect(
      maxServerSequenceForMessages([
        _message('a', serverSequence: 4),
        _message('b', serverSequence: 9),
      ]),
      '9',
    );
  });

  test('syncNow delegates only app-safe controls to core port', () async {
    final core = _FakeMessageSyncCore();
    final service = ImCoreMessageSyncService(sync: core);

    await service.syncNow(reason: 'app_resumed', limit: 50);

    expect(core.syncReasons, ['app_resume']);
    expect(core.syncLimits, [50]);
  });

  test('syncNow maps every internal trigger to a frozen Core reason', () async {
    final core = _FakeMessageSyncCore();
    final service = ImCoreMessageSyncService(sync: core);
    const cases = <String, String>{
      'startup': 'session_start',
      'session_start': 'session_start',
      'app_resumed': 'app_resume',
      'app_resume': 'app_resume',
      'realtime_reconnected': 'websocket_reconnect',
      'websocket_reconnect': 'websocket_reconnect',
      'foreground_catch_up': 'foreground_reconcile',
      'foreground_reconcile': 'foreground_reconcile',
      'realtime_message': 'websocket_hint',
      'realtime_dirty': 'websocket_hint',
      'realtime_gap': 'websocket_hint',
      'realtime_persistent_fact': 'websocket_hint',
      'realtime_agent_control': 'websocket_hint',
      'system_notification_changed': 'websocket_hint',
      'websocket_hint': 'websocket_hint',
      'after_mutation': 'after_mutation',
      'manual_refresh': 'manual_refresh',
      'remote_push': 'remote_push',
      'realtime_future_hint': 'websocket_hint',
      'unknown_internal_trigger': 'manual_refresh',
    };

    for (final entry in cases.entries) {
      await service.syncNow(reason: entry.key);
    }

    expect(core.syncReasons, cases.values);
  });

  test(
    'thread-after delegates thread-local sequence and returns messages',
    () async {
      final message = _message('msg-2', serverSequence: 2);
      final core = _FakeMessageSyncCore(
        threadAfterResult: MessageSyncThreadAfterResult(
          messages: <ChatMessage>[message],
          nextAfterServerSeq: '2',
          hasMore: false,
        ),
      );
      final service = ImCoreMessageSyncService(sync: core);

      final result = await service.syncThreadAfter(
        thread: const AppThreadRef.direct('did:bob'),
        afterServerSeq: '1',
        limit: 25,
      );

      expect(core.threadAfterThreads.single.stableId, 'dm:did:bob');
      expect(core.threadAfterSeqs, ['1']);
      expect(core.threadAfterLimits, [25]);
      expect(result.messages.single.localId, 'msg-2');
    },
  );

  test('conversation-after delegates canonical conversation id', () async {
    final message = _message(
      'msg-conversation',
      conversationId: 'dm:peer-scope:v1:bob',
      serverSequence: 3,
    );
    final core = _FakeMessageSyncCore(
      conversationAfterResult: MessageSyncThreadAfterResult(
        messages: <ChatMessage>[message],
        nextAfterServerSeq: '3',
        hasMore: false,
      ),
    );
    final service = ImCoreMessageSyncService(sync: core);

    final result = await service.syncConversationAfter(
      conversation: AppConversationReadRef.fromConversationId(
        'dm:peer-scope:v1:bob',
      ),
      afterServerSeq: '2',
      limit: 10,
    );

    expect(core.conversationAfterIds, ['dm:peer-scope:v1:bob']);
    expect(core.conversationAfterSeqs, ['2']);
    expect(core.conversationAfterLimits, [10]);
    expect(result.messages.single.conversationId, 'dm:peer-scope:v1:bob');
  });

  test('conversation-after fails clearly without core capability', () {
    final service = ImCoreMessageSyncService(
      sync: _ThreadOnlyMessageSyncCore(),
    );

    expect(
      () => service.syncConversationAfter(
        conversation: AppConversationReadRef.fromConversationId('conversation'),
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test(
    'maxServerSequenceForMessages returns highest thread-local sequence',
    () {
      expect(
        maxServerSequenceForMessages(<ChatMessage>[
          _message('msg-no-seq'),
          _message('msg-9', serverSequence: 9),
          _message('msg-4', serverSequence: 4),
        ]),
        '9',
      );
    },
  );
}

class _FakeMessageSyncCore
    implements MessageSyncCorePort, ConversationMessageSyncCorePort {
  _FakeMessageSyncCore({
    this.threadAfterResult = const MessageSyncThreadAfterResult(
      messages: <ChatMessage>[],
      hasMore: false,
    ),
    this.conversationAfterResult = const MessageSyncThreadAfterResult(
      messages: <ChatMessage>[],
      hasMore: false,
    ),
  });

  final MessageSyncThreadAfterResult threadAfterResult;
  final MessageSyncThreadAfterResult conversationAfterResult;
  final List<String?> syncReasons = <String?>[];
  final List<int?> syncLimits = <int?>[];
  final List<AppThreadRef> threadAfterThreads = <AppThreadRef>[];
  final List<String?> threadAfterSeqs = <String?>[];
  final List<int?> threadAfterLimits = <int?>[];
  final List<String> conversationAfterIds = <String>[];
  final List<String?> conversationAfterSeqs = <String?>[];
  final List<int?> conversationAfterLimits = <int?>[];

  @override
  Future<MessageSyncOutcome> syncNow({
    int? limit,
    required String reason,
  }) async {
    syncReasons.add(reason);
    syncLimits.add(limit);
    return const MessageSyncOutcome(
      status: MessageSyncStatus.idle,
      eventsApplied: 0,
      pagesFetched: 0,
    );
  }

  @override
  Future<MessageSyncThreadAfterResult> syncThreadAfter({
    required AppThreadRef thread,
    String? afterServerSeq,
    int? limit,
  }) async {
    threadAfterThreads.add(thread);
    threadAfterSeqs.add(afterServerSeq);
    threadAfterLimits.add(limit);
    return threadAfterResult;
  }

  @override
  Future<MessageSyncThreadAfterResult> syncConversationAfter({
    required AppConversationReadRef conversation,
    String? afterServerSeq,
    int? limit,
  }) async {
    conversationAfterIds.add(conversation.conversationId);
    conversationAfterSeqs.add(afterServerSeq);
    conversationAfterLimits.add(limit);
    return conversationAfterResult;
  }
}

class _ThreadOnlyMessageSyncCore implements MessageSyncCorePort {
  @override
  Future<MessageSyncOutcome> syncNow({
    int? limit,
    required String reason,
  }) async {
    return const MessageSyncOutcome(
      status: MessageSyncStatus.idle,
      eventsApplied: 0,
      pagesFetched: 0,
    );
  }

  @override
  Future<MessageSyncThreadAfterResult> syncThreadAfter({
    required AppThreadRef thread,
    String? afterServerSeq,
    int? limit,
  }) async {
    return const MessageSyncThreadAfterResult(
      messages: <ChatMessage>[],
      hasMore: false,
    );
  }
}

class _ReceiveCore extends _FakeMessageSyncCore
    implements MessageReceiveCorePort {
  String? receiveReason;
  int? receiveLimit;
  Set<String>? references;
  Object? failure;
  final processing = _ProcessingSession();
  final outcome = const MessageReceiveOutcome(
    status: MessageSyncStatus.retryableFailure,
    complete: false,
    eventsReceived: 2,
    pagesFetched: 1,
    errorCode: 'transport_unavailable',
  );
  final incoming = [
    LocalIncomingMessage(
      message: _message('recovered-message'),
      opaqueMessageReferences: {'push-opaque-reference'},
    ),
  ];

  @override
  Future<MessageReceiveOutcome> receiveNow({
    int? limit,
    required String reason,
  }) async {
    if (failure case final error?) throw error;
    receiveReason = reason;
    receiveLimit = limit;
    return outcome;
  }

  @override
  Future<MessageProcessingSession> openProcessingSession() async {
    if (failure case final error?) throw error;
    return processing;
  }

  @override
  Future<List<LocalIncomingMessage>> findLocalIncoming(
    Set<String> references,
  ) async {
    if (failure case final error?) throw error;
    this.references = references;
    return incoming;
  }
}

class _ProcessingSession implements MessageProcessingSession {
  @override
  Stream<MessageProcessingUpdate> get updates => const Stream.empty();
  @override
  Future<void> close() async {}
  @override
  Future<MessageProcessingOutcome> waitUntilSettled() async =>
      const MessageProcessingOutcome(
        complete: true,
        pendingCount: 0,
        blockedCount: 0,
        discardedCount: 0,
      );
}

ChatMessage _message(String id, {String? conversationId, int? serverSequence}) {
  return ChatMessage(
    localId: id,
    remoteId: id,
    conversationId: conversationId,
    threadId: 'dm:did:alice:did:bob',
    senderDid: 'did:bob',
    receiverDid: 'did:alice',
    content: 'hello',
    createdAt: DateTime.utc(2026, 6, 27, 9),
    isMine: false,
    serverSequence: serverSequence,
    sendState: MessageSendState.sent,
  );
}
