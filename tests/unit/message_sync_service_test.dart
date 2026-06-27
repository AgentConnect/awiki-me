import 'package:awiki_me/src/application/message_sync_service.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/ports/message_sync_core_port.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('syncNow delegates only app-safe controls to core port', () async {
    final core = _FakeMessageSyncCore();
    final service = ImCoreMessageSyncService(sync: core);

    await service.syncNow(reason: 'app_resumed', limit: 50);

    expect(core.deltaReasons, ['app_resumed']);
    expect(core.deltaLimits, [50]);
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

class _FakeMessageSyncCore implements MessageSyncCorePort {
  _FakeMessageSyncCore({
    this.threadAfterResult = const MessageSyncThreadAfterResult(
      messages: <ChatMessage>[],
      hasMore: false,
    ),
  });

  final MessageSyncThreadAfterResult threadAfterResult;
  final List<String?> deltaReasons = <String?>[];
  final List<int?> deltaLimits = <int?>[];
  final List<AppThreadRef> threadAfterThreads = <AppThreadRef>[];
  final List<String?> threadAfterSeqs = <String?>[];
  final List<int?> threadAfterLimits = <int?>[];

  @override
  Future<MessageSyncDeltaResult> syncDelta({
    int? limit,
    String? deviceId,
    String? reason,
  }) async {
    deltaReasons.add(reason);
    deltaLimits.add(limit);
    return const MessageSyncDeltaResult(
      eventsApplied: 0,
      pagesFetched: 0,
      hasMore: false,
      snapshotRequired: false,
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
}

ChatMessage _message(String id, {int? serverSequence}) {
  return ChatMessage(
    localId: id,
    remoteId: id,
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
