import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_config.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_message_adapter.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_paths.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_runtime.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retry resends failed direct text to the message peer', () async {
    final adapter = _RetrySpyMessageAdapter();
    final failed = _failedMessage(
      localId: 'failed-direct',
      senderDid: 'did:alice',
      receiverDid: 'did:bob',
      isMine: true,
      content: 'retry direct',
    );

    final retried = await adapter.retryByResendOriginalContent(failed);

    expect(adapter.sentTextContent, 'retry direct');
    expect(adapter.sentTextThread, isA<AppDirectThreadRef>());
    expect(
      (adapter.sentTextThread! as AppDirectThreadRef).peerDidOrHandle,
      'did:bob',
    );
    expect(adapter.sentPayload, isNull);
    expect(retried.localId, 'resent-text');
  });

  test('retry resends failed incoming direct text to sender', () async {
    final adapter = _RetrySpyMessageAdapter();
    final failed = _failedMessage(
      localId: 'failed-incoming-direct',
      senderDid: 'did:bob',
      receiverDid: 'did:alice',
      isMine: false,
      content: 'retry incoming peer',
    );

    await adapter.retryByResendOriginalContent(failed);

    expect(adapter.sentTextThread, isA<AppDirectThreadRef>());
    expect(
      (adapter.sentTextThread! as AppDirectThreadRef).peerDidOrHandle,
      'did:bob',
    );
  });

  test('retry resends failed group text to the original group', () async {
    final adapter = _RetrySpyMessageAdapter();
    final failed = _failedMessage(
      localId: 'failed-group',
      threadId: 'group:did:group',
      senderDid: 'did:alice',
      groupId: 'did:group',
      isMine: true,
      content: 'retry group',
    );

    await adapter.retryByResendOriginalContent(failed);

    expect(adapter.sentTextThread, isA<AppGroupThreadRef>());
    expect(
      (adapter.sentTextThread! as AppGroupThreadRef).groupDid,
      'did:group',
    );
    expect(adapter.sentTextContent, 'retry group');
  });

  test(
    'retry resends valid mention payload without upgrading security',
    () async {
      final adapter = _RetrySpyMessageAdapter();
      const payloadJson =
          '{"text":"@agents retry","mentions":[{"id":"men_agents","range":{"start":0,"end":7,"unit":"unicode_code_point"},"target":{"kind":"group_selector","selector":"agents"},"mention_role":"addressee"}]}';
      final failed = _failedMessage(
        localId: 'failed-mention',
        threadId: 'group:did:group',
        senderDid: 'did:alice',
        groupId: 'did:group',
        isMine: true,
        content: '@agents retry',
        originalType: 'application/json',
        payloadJson: payloadJson,
      );

      final retried = await adapter.retryByResendOriginalContent(failed);

      expect(adapter.sentPayloadThread, isA<AppGroupThreadRef>());
      expect(
        (adapter.sentPayloadThread! as AppGroupThreadRef).groupDid,
        'did:group',
      );
      expect(adapter.sentPayload?['text'], '@agents retry');
      expect(adapter.sentPayloadSecure, isFalse);
      expect(adapter.sentPayloadIdempotencyKey, 'failed-mention');
      expect(adapter.sentTextContent, isNull);
      expect(retried.localId, 'resent-payload');
    },
  );

  test('retry fails clearly when direct peer cannot be recovered', () async {
    final adapter = _RetrySpyMessageAdapter();
    final failed = _failedMessage(
      localId: 'failed-no-peer',
      threadId: 'dm:unknown',
      senderDid: 'did:alice',
      isMine: true,
      content: 'cannot retry',
    );

    expect(
      () => adapter.retryByResendOriginalContent(failed),
      throwsA(isA<StateError>()),
    );
    expect(adapter.sentTextContent, isNull);
    expect(adapter.sentPayload, isNull);
  });
}

class _RetrySpyMessageAdapter extends AwikiImCoreMessageAdapter {
  _RetrySpyMessageAdapter() : super(runtime: _unusedRuntime());

  AppThreadRef? sentTextThread;
  String? sentTextContent;
  AppThreadRef? sentPayloadThread;
  Map<String, Object?>? sentPayload;
  bool? sentPayloadSecure;
  String? sentPayloadIdempotencyKey;

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) async {
    sentTextThread = thread;
    sentTextContent = content;
    return _sentMessage(
      localId: 'resent-text',
      thread: thread,
      content: content,
    );
  }

  @override
  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  }) async {
    sentPayloadThread = thread;
    sentPayload = payload;
    sentPayloadSecure = secure;
    sentPayloadIdempotencyKey = idempotencyKey;
    return _sentMessage(
      localId: 'resent-payload',
      thread: thread,
      content: payload['text']?.toString() ?? '',
      payloadJson: payload.toString(),
    );
  }
}

AwikiImCoreRuntime _unusedRuntime() {
  return AwikiImCoreRuntime(
    config: const AwikiImCoreEnvironmentConfig(
      serviceBaseUrl: 'https://awiki.info',
      didDomain: 'awiki.info',
    ),
    paths: AwikiImCorePathLayout.fromRoots(
      appSupportRoot: '/tmp/awiki-me-test/support',
      cacheRoot: '/tmp/awiki-me-test/cache',
      tempRoot: '/tmp/awiki-me-test/tmp',
    ),
  );
}

ChatMessage _failedMessage({
  required String localId,
  String threadId = 'dm:did:alice:did:bob',
  required String senderDid,
  String? receiverDid,
  String? groupId,
  required bool isMine,
  required String content,
  String originalType = 'text',
  String? payloadJson,
}) {
  return ChatMessage(
    localId: localId,
    threadId: threadId,
    senderDid: senderDid,
    receiverDid: receiverDid,
    groupId: groupId,
    content: content,
    originalType: originalType,
    createdAt: DateTime.utc(2026, 6, 15),
    isMine: isMine,
    sendState: MessageSendState.failed,
    payloadJson: payloadJson,
  );
}

ChatMessage _sentMessage({
  required String localId,
  required AppThreadRef thread,
  required String content,
  String? payloadJson,
}) {
  final groupDid = thread is AppGroupThreadRef ? thread.groupDid : null;
  final receiverDid = thread is AppDirectThreadRef
      ? thread.peerDidOrHandle
      : null;
  return ChatMessage(
    localId: localId,
    threadId: thread.stableId,
    senderDid: 'did:alice',
    receiverDid: receiverDid,
    groupId: groupDid,
    content: content,
    originalType: payloadJson == null ? 'text' : 'application/json',
    createdAt: DateTime.utc(2026, 6, 15, 1),
    isMine: true,
    sendState: MessageSendState.sent,
    payloadJson: payloadJson,
  );
}
