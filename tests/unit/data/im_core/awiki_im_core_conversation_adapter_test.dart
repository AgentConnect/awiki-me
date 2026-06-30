import 'dart:async';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_read_watermark.dart';
import 'package:awiki_me/src/application/models/conversation_patch.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_config.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_conversation_adapter.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_paths.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mark-read resolves canonical direct and group thread refs', () {
    final direct = coreThreadRefForMarkRead(
      const AppThreadRef.thread('dm:did:alice:did:bob'),
      'did:alice',
    );
    final group = coreThreadRefForMarkRead(
      const AppThreadRef.thread('group:did:group'),
      'did:alice',
    );

    expect(direct, isA<core.DirectThreadRef>());
    expect((direct as core.DirectThreadRef).peer, 'did:bob');
    expect(group, isA<core.GroupThreadRef>());
    expect((group as core.GroupThreadRef).group, 'did:group');
  });

  test(
    'mark-read preserves peer-scope and unknown thread ids for SDK lookup',
    () {
      final peerScope = coreThreadRefForMarkRead(
        const AppThreadRef.thread('dm:peer-scope:v1:abc'),
        'did:alice',
      );
      final unknown = coreThreadRefForMarkRead(
        const AppThreadRef.thread('custom-thread'),
        'did:alice',
      );

      expect(peerScope, isA<core.MessageThreadRef>());
      expect(
        (peerScope as core.MessageThreadRef).threadId,
        'dm:peer-scope:v1:abc',
      );
      expect(unknown, isA<core.MessageThreadRef>());
      expect((unknown as core.MessageThreadRef).threadId, 'custom-thread');
    },
  );

  test('mark-read exposes thread kind for metrics', () {
    expect(coreThreadKind(const core.ThreadRef.direct('did:bob')), 'direct');
    expect(coreThreadKind(const core.ThreadRef.group('did:group')), 'group');
    expect(coreThreadKind(const core.ThreadRef.thread('thread-1')), 'thread');
  });

  test(
    'mark-read delegates to SDK thread API without history lookup',
    () async {
      final client = _FakeClient();
      final adapter = AwikiImCoreConversationAdapter(
        runtime: _FakeRuntime(client),
      );

      await adapter.markThreadRead(
        const AppThreadRef.thread('dm:did:alice:did:bob'),
      );

      expect(client.messages.markThreadReadCalls, 1);
      expect(client.messages.historyCalls, 0);
      expect(client.messages.markReadCalls, 0);
      expect(client.messages.lastMarkThreadReadWatermark, isNull);
      expect(
        client.messages.lastMarkThreadReadThread,
        isA<core.DirectThreadRef>(),
      );
      expect(
        (client.messages.lastMarkThreadReadThread! as core.DirectThreadRef)
            .peer,
        'did:bob',
      );
    },
  );

  test('mark-read forwards explicit read watermark to SDK', () async {
    final client = _FakeClient();
    final adapter = AwikiImCoreConversationAdapter(
      runtime: _FakeRuntime(client),
    );
    final readAt = DateTime.utc(2026, 6, 29, 7, 40);

    await adapter.markThreadRead(
      const AppThreadRef.direct('did:bob'),
      watermark: AppThreadReadWatermark(
        lastReadMessageId: 'remote-42',
        lastReadThreadSeq: '42',
        readAt: readAt,
      ),
    );

    final watermark = client.messages.lastMarkThreadReadWatermark;
    expect(watermark, isNotNull);
    expect(watermark!.lastReadMessageId, 'remote-42');
    expect(watermark.lastReadThreadSeq, '42');
    expect(watermark.readAt, readAt);
  });

  test(
    'watchConversationPatches maps SDK upsert patch to app core patch',
    () async {
      final client = _FakeClient();
      final adapter = AwikiImCoreConversationAdapter(
        runtime: _FakeRuntime(client),
      );
      final patchFuture = adapter.watchConversationPatches().first;
      await Future<void>.delayed(Duration.zero);

      client.messages.emitPatch(
        const core.ConversationStorePatch(
          kind: core.ConversationStorePatchKind.upsert,
          ownerIdentityId: 'alice-id',
          ownerDid: 'did:alice',
          version: 1,
          unreadTotal: 2,
          item: core.ConversationSnapshotItem(
            threadKind: 'direct',
            threadId: 'did:bob',
            participants: <String>['did:bob'],
            unreadCount: 2,
            messageCount: 1,
            lastMessageAt: '2026-06-27T00:00:00Z',
            lastMessage: core.ConversationSnapshotMessage(
              id: 'msg-1',
              threadKind: 'direct',
              threadId: 'did:bob',
              direction: 'incoming',
              sender: 'did:bob',
              body: core.ConversationSnapshotMessageBody(
                text: 'hello',
                kind: 'text',
              ),
              sentAt: '2026-06-27T00:00:00Z',
            ),
          ),
        ),
      );

      final patch = await patchFuture.timeout(const Duration(seconds: 1));
      expect(patch.kind.name, 'upsert');
      expect(patch.ownerDid, 'did:alice');
      expect(patch.item?.threadId, 'dm:did:alice:did:bob');
      expect(patch.item?.lastMessagePreview, 'hello');
      expect(patch.item?.unreadCount, 2);
    },
  );

  test('visible control patch updates recents preview', () async {
    final client = _FakeClient();
    final adapter = AwikiImCoreConversationAdapter(
      runtime: _FakeRuntime(client),
    );
    final patchFuture = adapter.watchConversationPatches().first;
    await Future<void>.delayed(Duration.zero);

    client.messages.emitPatch(
      const core.ConversationStorePatch(
        kind: core.ConversationStorePatchKind.upsert,
        ownerIdentityId: 'alice-id',
        ownerDid: 'did:alice',
        version: 3,
        unreadTotal: 1,
        item: core.ConversationSnapshotItem(
          threadKind: 'direct',
          threadId: 'did:agent:runtime',
          participants: <String>['did:agent:runtime'],
          unreadCount: 1,
          messageCount: 1,
          lastMessageAt: '2026-06-27T00:00:00Z',
          lastMessage: core.ConversationSnapshotMessage(
            id: 'msg-control-visible',
            threadKind: 'direct',
            threadId: 'did:agent:runtime',
            direction: 'incoming',
            sender: 'did:agent:runtime',
            body: core.ConversationSnapshotMessageBody(
              text: 'Agent 已准备好。',
              payloadJson:
                  '{"schema":"awiki.agent.status.v1","status_scope":"runtime"}',
            ),
            sentAt: '2026-06-27T00:00:00Z',
          ),
        ),
      ),
    );

    final patch = await patchFuture.timeout(const Duration(seconds: 1));
    expect(patch.kind, CoreConversationPatchKind.upsert);
    expect(patch.item?.lastMessagePreview, 'Agent 已准备好。');
    expect(patch.item?.lastMessagePayloadJson, contains('awiki.agent.status'));
  });

  test('payload-only control patch removes hidden row', () async {
    final client = _FakeClient();
    final adapter = AwikiImCoreConversationAdapter(
      runtime: _FakeRuntime(client),
    );
    final patchFuture = adapter.watchConversationPatches().first;
    await Future<void>.delayed(Duration.zero);

    client.messages.emitPatch(
      const core.ConversationStorePatch(
        kind: core.ConversationStorePatchKind.upsert,
        ownerIdentityId: 'alice-id',
        ownerDid: 'did:alice',
        version: 4,
        unreadTotal: 0,
        item: core.ConversationSnapshotItem(
          threadKind: 'direct',
          threadId: 'did:agent:daemon',
          participants: <String>['did:agent:daemon'],
          unreadCount: 0,
          messageCount: 1,
          lastMessageAt: '2026-06-27T00:00:00Z',
          lastMessage: core.ConversationSnapshotMessage(
            id: 'msg-control-hidden',
            threadKind: 'direct',
            threadId: 'did:agent:daemon',
            direction: 'incoming',
            sender: 'did:agent:daemon',
            body: core.ConversationSnapshotMessageBody(
              payloadJson:
                  '{"schema":"awiki.agent.status.v1","status_scope":"daemon"}',
            ),
            sentAt: '2026-06-27T00:00:00Z',
          ),
        ),
      ),
    );

    final patch = await patchFuture.timeout(const Duration(seconds: 1));
    expect(patch.kind, CoreConversationPatchKind.remove);
    expect(patch.threadId, 'did:agent:daemon');
  });

  test(
    'watchConversationPatches maps SDK reorder patch without removing row',
    () async {
      final client = _FakeClient();
      final adapter = AwikiImCoreConversationAdapter(
        runtime: _FakeRuntime(client),
      );
      final patchFuture = adapter.watchConversationPatches().first;
      await Future<void>.delayed(Duration.zero);

      client.messages.emitPatch(
        const core.ConversationStorePatch(
          kind: core.ConversationStorePatchKind.reorder,
          ownerIdentityId: 'alice-id',
          ownerDid: 'did:alice',
          version: 2,
          unreadTotal: 0,
          threadKind: 'direct',
          threadId: 'did:bob',
          index: 0,
        ),
      );

      final patch = await patchFuture.timeout(const Duration(seconds: 1));
      expect(patch.kind, CoreConversationPatchKind.reorder);
      expect(patch.threadId, 'did:bob');
      expect(patch.index, 0);
    },
  );
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
        ),
      );

  final _FakeClient client;

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
  _FakeClient() : identity = _FakeIdentityApi(), messages = _FakeMessageApi();

  @override
  final _FakeIdentityApi identity;

  @override
  final _FakeMessageApi messages;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIdentityApi implements core.IdentityApi {
  @override
  Future<core.IdentitySummary> current() async {
    return const core.IdentitySummary(
      id: 'alice-id',
      did: 'did:alice',
      isDefault: true,
      readyForAuth: true,
      readyForMessaging: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMessageApi implements core.MessageApi {
  final StreamController<core.ConversationStorePatch> _patches =
      StreamController<core.ConversationStorePatch>.broadcast(sync: true);
  int markThreadReadCalls = 0;
  int historyCalls = 0;
  int markReadCalls = 0;
  core.ThreadRef? lastMarkThreadReadThread;
  core.ReadWatermark? lastMarkThreadReadWatermark;

  void emitPatch(core.ConversationStorePatch patch) {
    _patches.add(patch);
  }

  @override
  Stream<core.ConversationStorePatch> watchConversationPatches() {
    return _patches.stream;
  }

  @override
  Future<core.ConversationStorePatch> repairConversationStore() async {
    return const core.ConversationStorePatch(
      kind: core.ConversationStorePatchKind.repairRequired,
      ownerIdentityId: 'alice-id',
      ownerDid: 'did:alice',
      version: 1,
      unreadTotal: 0,
      reason: 'test',
    );
  }

  @override
  Future<core.MarkThreadReadResult> markThreadRead(
    core.ThreadRef thread, {
    core.ReadWatermark? watermark,
    int? fallbackMaxMessageIds,
  }) async {
    markThreadReadCalls += 1;
    lastMarkThreadReadThread = thread;
    lastMarkThreadReadWatermark = watermark;
    return const core.MarkThreadReadResult(
      updatedCount: 1,
      remoteAcknowledged: true,
      partial: false,
      fallbackUsed: false,
      pendingRemoteAck: false,
      effectiveWatermark: core.ReadWatermark(lastReadThreadSeq: '42'),
      legacyMessageIds: <String>['msg-1'],
    );
  }

  @override
  Future<core.MessagePage> history(
    core.ThreadRef thread, {
    required int limit,
    String? cursor,
    core.InboxHistoryOptions? inboxHistoryOptions,
  }) async {
    historyCalls += 1;
    return const core.MessagePage(items: <core.Message>[], hasMore: false);
  }

  @override
  Future<core.MarkReadResult> markRead(List<String> messageIds) async {
    markReadCalls += 1;
    return core.MarkReadResult(updatedCount: messageIds.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
