import 'dart:async';
import 'dart:convert';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/app_conversation_read_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_config.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_message_adapter.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_paths.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_runtime.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_secret_storage.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

const _testScopeValue = '44444444-4444-4444-8444-444444444444';

void main() {
  test(
    'loadLocalHistory forwards limit and reuses owner did per client',
    () async {
      final client = _FakeClient(ownerDid: 'did:alice');
      final runtime = _FakeRuntime(client);
      final adapter = AwikiImCoreMessageAdapter(runtime: runtime);

      final first = await adapter.loadLocalHistory(
        const AppThreadRef.direct('did:bob'),
        limit: 50,
      );
      final second = await adapter.loadLocalHistory(
        const AppThreadRef.direct('did:bob'),
        limit: 30,
      );

      expect(client.identity.currentCalls, 1);
      expect(client.messages.localHistoryCalls, 2);
      expect(client.messages.localHistoryLimits, <int>[50, 30]);
      expect(first.single.content, 'hello from did:bob');
      expect(second.single.isMine, isFalse);
    },
  );

  test(
    'loadConversationTimeline calls SDK conversation timeline API',
    () async {
      final client = _FakeClient(ownerDid: 'did:alice');
      final runtime = _FakeRuntime(client);
      final adapter = AwikiImCoreMessageAdapter(runtime: runtime);

      final messages = await adapter.loadConversationTimeline(
        AppConversationReadRef.fromConversationId('dm:peer-scope:v1:bob'),
        limit: 20,
        cursor: 'cursor-1',
      );

      expect(client.identity.currentCalls, 1);
      expect(client.messages.localConversationTimelineCalls, 1);
      expect(client.messages.lastConversationId, 'dm:peer-scope:v1:bob');
      expect(client.messages.localConversationTimelineLimits, <int>[20]);
      expect(client.messages.lastConversationTimelineCursor, 'cursor-1');
      expect(messages.single.content, 'hello from did:bob');
    },
  );

  test('conversation timeline patch APIs use conversation read ref', () async {
    final client = _FakeClient(ownerDid: 'did:alice');
    final runtime = _FakeRuntime(client);
    final adapter = AwikiImCoreMessageAdapter(runtime: runtime);

    final patchFuture = adapter
        .watchConversationTimelinePatches(
          AppConversationReadRef.fromConversationId('dm:peer-scope:v1:bob'),
          limit: 12,
        )
        .first;
    await Future<void>.delayed(Duration.zero);
    client.messages.emitConversationTimelinePatch(
      core.ThreadMessageStorePatch(
        kind: core.ThreadMessageStorePatchKind.upsert,
        ownerIdentityId: 'alice-id',
        ownerDid: 'did:alice',
        version: 2,
        threadKind: 'thread',
        threadId: 'dm:peer-scope:v1:bob',
        conversationIdentity: _conversationIdentity(),
        message: _messageForOwner('did:alice'),
      ),
    );
    final watched = await patchFuture.timeout(const Duration(seconds: 1));
    final repaired = await adapter.repairConversationTimelineStore(
      AppConversationReadRef.fromConversationId('dm:peer-scope:v1:bob'),
      limit: 13,
    );

    expect(client.messages.watchConversationTimelinePatchCalls, 1);
    expect(client.messages.repairConversationTimelineStoreCalls, 1);
    expect(client.messages.lastWatchConversationTimelineLimit, 12);
    expect(client.messages.lastRepairConversationTimelineLimit, 13);
    expect(watched.conversationId, 'dm:peer-scope:v1:bob');
    expect(watched.message?.conversationId, 'dm:peer-scope:v1:bob');
    expect(repaired.conversationId, 'dm:peer-scope:v1:bob');
  });

  test(
    'sendConversationText forwards conversation id and durable ids',
    () async {
      final client = _FakeClient(ownerDid: 'did:alice');
      final runtime = _FakeRuntime(client);
      final adapter = AwikiImCoreMessageAdapter(runtime: runtime);

      final sent = await adapter.sendConversationText(
        conversation: AppConversationReadRef.fromConversationId(
          'dm:peer-scope:v1:bob',
        ),
        content: 'durable hello',
        clientMessageId: 'client-1',
        idempotencyKey: 'op-client-1',
      );

      expect(client.messages.sendConversationTextCalls, 1);
      expect(client.messages.lastConversationId, 'dm:peer-scope:v1:bob');
      expect(client.messages.lastSentText, 'durable hello');
      expect(client.messages.lastClientMessageId, 'client-1');
      expect(client.messages.lastIdempotencyKey, 'op-client-1');
      expect(sent.localId, 'client-1');
      expect(sent.conversationId, 'dm:peer-scope:v1:bob');
    },
  );

  test(
    'sendConversationPayload forwards payload json and durable ids',
    () async {
      final client = _FakeClient(ownerDid: 'did:alice');
      final runtime = _FakeRuntime(client);
      final adapter = AwikiImCoreMessageAdapter(runtime: runtime);

      final sent = await adapter.sendConversationPayload(
        conversation: AppConversationReadRef.fromConversationId(
          'dm:peer-scope:v1:bob',
        ),
        payload: <String, Object?>{'text': 'payload hello'},
        clientMessageId: 'client-payload',
        idempotencyKey: 'op-client-payload',
      );

      expect(client.messages.sendConversationPayloadCalls, 1);
      expect(client.messages.lastConversationId, 'dm:peer-scope:v1:bob');
      expect(client.messages.lastPayloadJson, contains('payload hello'));
      expect(client.messages.lastClientMessageId, 'client-payload');
      expect(client.messages.lastIdempotencyKey, 'op-client-payload');
      expect(sent.localId, 'client-payload');
      expect(sent.payloadJson, contains('payload hello'));
    },
  );

  test(
    'sendConversationAttachment forwards conversation id and durable ids',
    () async {
      final client = _FakeClient(ownerDid: 'did:alice');
      final runtime = _FakeRuntime(client);
      final adapter = AwikiImCoreMessageAdapter(runtime: runtime);

      final sent = await adapter.sendConversationAttachment(
        conversation: AppConversationReadRef.fromConversationId(
          'dm:peer-scope:v1:bob',
        ),
        attachment: const AttachmentDraft(
          filename: 'report.pdf',
          mimeType: 'application/pdf',
          localPath: '/tmp/report.pdf',
          sizeBytes: 3,
        ),
        caption: 'see attachment',
        clientMessageId: 'client-attachment',
        idempotencyKey: 'op-client-attachment',
      );

      expect(client.attachments.sendConversationCalls, 1);
      expect(client.attachments.sendCalls, 0);
      expect(client.attachments.lastConversationId, 'dm:peer-scope:v1:bob');
      expect(client.attachments.lastCaption, 'see attachment');
      expect(client.attachments.lastFilename, 'report.pdf');
      expect(client.attachments.lastMimeType, 'application/pdf');
      expect(client.attachments.lastClientMessageId, 'client-attachment');
      expect(client.attachments.lastIdempotencyKey, 'op-client-attachment');
      expect(sent.localId, 'client-attachment');
      expect(sent.conversationId, 'dm:peer-scope:v1:bob');
      expect(sent.attachment?.filename, 'report.pdf');
    },
  );

  test('owner did cache is invalidated when current client changes', () async {
    final firstClient = _FakeClient(ownerDid: 'did:alice');
    final secondClient = _FakeClient(ownerDid: 'did:carol');
    final runtime = _FakeRuntime(firstClient);
    final adapter = AwikiImCoreMessageAdapter(runtime: runtime);

    await adapter.loadLocalHistory(const AppThreadRef.direct('did:bob'));
    runtime.client = secondClient;
    final messages = await adapter.loadLocalHistory(
      const AppThreadRef.direct('did:bob'),
    );

    expect(firstClient.identity.currentCalls, 1);
    expect(secondClient.identity.currentCalls, 1);
    expect(messages.single.isMine, isFalse);
    expect(messages.single.receiverDid, 'did:carol');
  });

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

class _FakeRuntime extends AwikiImCoreRuntime {
  _FakeRuntime(this.client)
    : super(
        config: const AwikiImCoreEnvironmentConfig(
          serviceBaseUrl: 'https://awiki.info',
          didDomain: 'awiki.info',
        ),
        paths: AwikiImCorePathLayout.fromRoots(
          appSupportRoot: '/tmp/awiki-me-test/support',
          cacheRoot: '/tmp/awiki-me-test/cache',
          tempRoot: '/tmp/awiki-me-test/tmp',
          scopeId: StorageScopeId.parse(_testScopeValue),
        ),
        scopeId: StorageScopeId.parse(_testScopeValue),
        vaultSecretProvider: _FakeVaultSecretProvider(),
      );

  _FakeClient client;

  @override
  Future<T> withCurrentClient<T>(
    Future<T> Function(core.AwikiImClient client) action,
  ) {
    return action(client);
  }

  @override
  Future<core.AwikiImClient> currentClient() async {
    return client;
  }
}

class _FakeClient implements core.AwikiImClient {
  _FakeClient({required String ownerDid})
    : identity = _FakeIdentityApi(ownerDid),
      messages = _FakeMessageApi(() => ownerDid),
      attachments = _FakeAttachmentApi(() => ownerDid);

  @override
  final _FakeIdentityApi identity;

  @override
  final _FakeMessageApi messages;

  @override
  final _FakeAttachmentApi attachments;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIdentityApi implements core.IdentityApi {
  _FakeIdentityApi(this.ownerDid);

  final String ownerDid;
  int currentCalls = 0;

  @override
  Future<core.IdentitySummary> current() async {
    currentCalls += 1;
    return core.IdentitySummary(
      id: '$ownerDid-id',
      did: ownerDid,
      isDefault: true,
      readyForAuth: true,
      readyForMessaging: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMessageApi implements core.MessageApi {
  _FakeMessageApi(this._ownerDid);

  final String Function() _ownerDid;
  final StreamController<core.ThreadMessageStorePatch>
  _conversationTimelinePatches =
      StreamController<core.ThreadMessageStorePatch>.broadcast(sync: true);
  int localHistoryCalls = 0;
  int localConversationTimelineCalls = 0;
  int watchConversationTimelinePatchCalls = 0;
  int repairConversationTimelineStoreCalls = 0;
  int sendConversationTextCalls = 0;
  int sendConversationPayloadCalls = 0;
  final List<int> localHistoryLimits = <int>[];
  final List<int> localConversationTimelineLimits = <int>[];
  String? lastConversationId;
  String? lastConversationTimelineCursor;
  int? lastWatchConversationTimelineLimit;
  int? lastRepairConversationTimelineLimit;
  String? lastSentText;
  String? lastPayloadJson;
  String? lastClientMessageId;
  String? lastIdempotencyKey;

  void emitConversationTimelinePatch(core.ThreadMessageStorePatch patch) {
    _conversationTimelinePatches.add(patch);
  }

  @override
  Future<core.MessagePage> localHistory(
    core.ThreadRef thread, {
    required int limit,
    String? cursor,
  }) async {
    localHistoryCalls += 1;
    localHistoryLimits.add(limit);
    return core.MessagePage(
      items: <core.Message>[_messageForOwner(_ownerDid())],
      hasMore: false,
    );
  }

  @override
  Future<core.MessagePage> localConversationTimeline(
    core.ConversationReadRef conversation, {
    required int limit,
    String? cursor,
  }) async {
    localConversationTimelineCalls += 1;
    localConversationTimelineLimits.add(limit);
    lastConversationId = conversation.conversationId;
    lastConversationTimelineCursor = cursor;
    return core.MessagePage(
      items: <core.Message>[_messageForOwner(_ownerDid())],
      hasMore: false,
    );
  }

  @override
  Stream<core.ThreadMessageStorePatch> watchConversationTimelinePatches(
    core.ConversationReadRef conversation, {
    int limit = 100,
  }) {
    watchConversationTimelinePatchCalls += 1;
    lastConversationId = conversation.conversationId;
    lastWatchConversationTimelineLimit = limit;
    return _conversationTimelinePatches.stream;
  }

  @override
  Future<core.ThreadMessageStorePatch> repairConversationTimelineStore(
    core.ConversationReadRef conversation, {
    int limit = 100,
  }) async {
    repairConversationTimelineStoreCalls += 1;
    lastConversationId = conversation.conversationId;
    lastRepairConversationTimelineLimit = limit;
    return core.ThreadMessageStorePatch(
      kind: core.ThreadMessageStorePatchKind.reset,
      ownerIdentityId: '${_ownerDid()}-id',
      ownerDid: _ownerDid(),
      version: 3,
      threadKind: 'thread',
      threadId: conversation.conversationId,
      conversationIdentity: _conversationIdentity(),
      items: <core.Message>[_messageForOwner(_ownerDid())],
    );
  }

  @override
  Future<core.SendMessageResult> sendConversationText(
    core.SendConversationTextRequest request,
  ) async {
    sendConversationTextCalls += 1;
    lastConversationId = request.conversation.conversationId;
    lastSentText = request.text;
    lastClientMessageId = request.clientMessageId;
    lastIdempotencyKey = request.idempotencyKey;
    return core.SendMessageResult(
      deliveryState: 'sent',
      message: _messageForOwner(
        _ownerDid(),
        id: request.clientMessageId ?? 'sent-conversation-text',
        conversationId: request.conversation.conversationId,
        text: request.text,
      ),
    );
  }

  @override
  Future<core.SendMessageResult> sendConversationPayload(
    core.SendConversationPayloadRequest request,
  ) async {
    sendConversationPayloadCalls += 1;
    lastConversationId = request.conversation.conversationId;
    lastPayloadJson = request.payloadJson;
    lastClientMessageId = request.clientMessageId;
    lastIdempotencyKey = request.idempotencyKey;
    return core.SendMessageResult(
      deliveryState: 'sent',
      message: _messageForOwner(
        _ownerDid(),
        id: request.clientMessageId ?? 'sent-conversation-payload',
        conversationId: request.conversation.conversationId,
        text: 'payload hello',
        kind: 'application/json',
        payloadJson: request.payloadJson,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAttachmentApi implements core.AttachmentApi {
  _FakeAttachmentApi(this._ownerDid);

  final String Function() _ownerDid;
  int sendCalls = 0;
  int sendConversationCalls = 0;
  String? lastConversationId;
  String? lastCaption;
  String? lastFilename;
  String? lastMimeType;
  String? lastClientMessageId;
  String? lastIdempotencyKey;

  @override
  Future<core.AttachmentSendResult> send(core.AttachmentSendRequest request) {
    sendCalls += 1;
    throw StateError('Legacy attachment send should not be used in this test.');
  }

  @override
  Future<core.AttachmentSendResult> sendConversation(
    core.SendConversationAttachmentRequest request,
  ) async {
    sendConversationCalls += 1;
    lastConversationId = request.conversation.conversationId;
    lastCaption = request.caption;
    lastFilename = request.filename;
    lastMimeType = request.mimeType;
    lastClientMessageId = request.clientMessageId;
    lastIdempotencyKey = request.idempotencyKey;
    final attachmentId = request.clientMessageId ?? 'attachment-1';
    final filename = request.filename ?? 'attachment.bin';
    final mimeType = request.mimeType ?? 'application/octet-stream';
    final manifestJson = jsonEncode(<String, Object?>{
      'caption': request.caption,
      'primary_attachment_id': attachmentId,
      'attachments': <Object?>[
        <String, Object?>{
          'attachment_id': attachmentId,
          'filename': filename,
          'mime_type': mimeType,
          'size_bytes': 3,
          'object_uri': 'memory://attachment',
        },
      ],
    });
    return core.AttachmentSendResult(
      message: core.SendMessageResult(
        deliveryState: 'sent',
        message: _messageForOwner(
          _ownerDid(),
          id: request.clientMessageId ?? 'sent-conversation-attachment',
          conversationId: request.conversation.conversationId,
          text: manifestJson,
          kind: 'application/anp-attachment-manifest+json',
          payloadJson: manifestJson,
          contentType: 'application/anp-attachment-manifest+json',
        ),
      ),
      targetKind: 'conversation',
      targetDid: request.conversation.conversationId,
      attachment: core.UploadedAttachment(
        attachmentId: attachmentId,
        filename: filename,
        mimeType: mimeType,
        sizeBytes: 3,
        size: '3',
        digestB64u: 'digest',
        objectUri: 'memory://attachment',
      ),
      manifestJson: manifestJson,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

core.Message _messageForOwner(
  String ownerDid, {
  String id = 'msg-1',
  String conversationId = 'dm:peer-scope:v1:bob',
  String text = 'hello from did:bob',
  String kind = 'text',
  String? payloadJson,
  String? contentType,
}) {
  return core.Message(
    id: id,
    threadKind: 'direct',
    threadId: conversationId,
    direction: core.MessageDirection.incoming,
    sender: 'did:bob',
    receiver: ownerDid,
    body: core.MessageBodyView(
      text: text,
      kind: kind,
      payloadJson: payloadJson,
    ),
    sentAt: '2026-06-28T00:00:00Z',
    metadata: core.MessageMetadata(
      serverSequence: 1,
      conversationIdentity: _conversationIdentity(conversationId),
      contentType: contentType,
    ),
  );
}

core.ConversationIdentity _conversationIdentity([
  String conversationId = 'dm:peer-scope:v1:bob',
]) {
  return core.ConversationIdentity(
    conversationId: conversationId,
    canonicalThreadKind: 'thread',
    canonicalThreadId: conversationId,
    storageThreadRef: core.ConversationStorageThreadRef(
      kind: 'thread',
      id: conversationId,
    ),
    identityScope: core.ConversationIdentityScope.direct,
    migrationState: core.ConversationMigrationState.canonical,
  );
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
      scopeId: StorageScopeId.parse(_testScopeValue),
    ),
    scopeId: StorageScopeId.parse(_testScopeValue),
    vaultSecretProvider: _FakeVaultSecretProvider(),
  );
}

class _FakeVaultSecretProvider implements AwikiImCoreVaultSecretProvider {
  @override
  Future<AwikiImCoreVaultSecrets> openExisting(StorageScopeId scopeId) async {
    expect(scopeId.value, _testScopeValue);
    return AwikiImCoreVaultSecrets(
      rootKey: core.DeviceVaultRootKey.fromList(List<int>.filled(32, 1)),
    );
  }
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
