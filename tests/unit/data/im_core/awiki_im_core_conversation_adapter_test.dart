import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
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
  int markThreadReadCalls = 0;
  int historyCalls = 0;
  int markReadCalls = 0;
  core.ThreadRef? lastMarkThreadReadThread;

  @override
  Future<core.MarkThreadReadResult> markThreadRead(
    core.ThreadRef thread, {
    int? maxMessageIds,
  }) async {
    markThreadReadCalls += 1;
    lastMarkThreadReadThread = thread;
    return const core.MarkThreadReadResult(
      updatedCount: 1,
      messageIds: <String>['msg-1'],
      localCandidateCount: 1,
      localUpdatedCount: 1,
      remoteUpdatedCount: 1,
      remoteAcknowledged: true,
      partial: false,
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
