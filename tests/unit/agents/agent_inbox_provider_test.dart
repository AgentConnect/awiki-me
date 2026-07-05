// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/agent/agent_control_status_store.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/presentation/agents/agent_inbox_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support.dart';

void main() {
  test(
    'queryInbox sends command and accepts matching status payload only',
    () async {
      final control = FakeAgentControlService()
        ..nextInboxRequestId = 'cmd_inbox_current';
      final container = _container(control);
      addTearDown(container.dispose);

      await container
          .read(agentInboxProvider.notifier)
          .queryInbox(
            daemonAgentDid: 'did:agent:daemon',
            runtimeAgentDid: 'did:agent:runtime',
            scope: AgentInboxScope.group,
          );

      expect(control.lastInboxDaemonDid, 'did:agent:daemon');
      expect(control.lastInboxRuntimeDid, 'did:agent:runtime');
      expect(control.lastInboxScope, 'group');
      expect(control.lastInboxLimit, agentInboxPageSize);
      container.read(agentInboxProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime_inbox',
          'daemon_agent_did': 'did:agent:daemon',
          'runtime_agent_did': 'did:agent:runtime',
          'request_id': 'old_request',
          'state': 'succeeded',
          'result': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'thread_id': 'dm:peer-scope:v1:old',
                'kind': 'direct',
              },
            ],
          },
        },
      );
      expect(container.read(agentInboxProvider).items, isEmpty);

      container.read(agentInboxProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime_inbox',
          'daemon_agent_did': 'did:agent:daemon',
          'runtime_agent_did': 'did:agent:runtime',
          'request_id': 'cmd_inbox_current',
          'state': 'succeeded',
          'result': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'thread_id': 'group:did:group:team',
                'kind': 'group',
                'title': '项目群',
                'group_did': 'did:group:team',
                'last_message_preview': 'report',
                'has_attachments': true,
              },
            ],
          },
        },
      );

      final state = container.read(agentInboxProvider);
      expect(state.items, hasLength(1));
      expect(state.items.first.kind, 'group');
      expect(state.items.first.hasAttachments, isTrue);
      expect(state.error, isNull);
    },
  );

  test(
    'inbox list sorts latest message first and thread messages by time',
    () async {
      final control = FakeAgentControlService()
        ..nextInboxRequestId = 'cmd_inbox_current'
        ..nextInboxThreadRequestId = 'cmd_thread_current';
      final container = _container(control);
      addTearDown(container.dispose);

      await container
          .read(agentInboxProvider.notifier)
          .queryInbox(
            daemonAgentDid: 'did:agent:daemon',
            runtimeAgentDid: 'did:agent:runtime',
          );
      container.read(agentInboxProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime_inbox',
          'daemon_agent_did': 'did:agent:daemon',
          'runtime_agent_did': 'did:agent:runtime',
          'request_id': 'cmd_inbox_current',
          'state': 'succeeded',
          'result': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'thread_id': 'dm:old',
                'kind': 'direct',
                'title': 'Old',
                'last_message_preview': 'old',
                'last_message_at_ms': 100,
              },
              <String, Object?>{
                'thread_id': 'dm:new',
                'kind': 'direct',
                'title': 'New',
                'last_message_preview': 'new',
                'last_message_at_ms': 300,
              },
            ],
          },
        },
      );

      expect(
        container.read(agentInboxProvider).items.map((item) => item.threadId),
        <String>['dm:new', 'dm:old'],
      );

      await container
          .read(agentInboxProvider.notifier)
          .queryThread(
            daemonAgentDid: 'did:agent:daemon',
            runtimeAgentDid: 'did:agent:runtime',
            item: container.read(agentInboxProvider).items.first,
          );
      expect(control.lastInboxThreadLimit, agentInboxPageSize);
      container.read(agentInboxProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime_inbox_thread',
          'daemon_agent_did': 'did:agent:daemon',
          'runtime_agent_did': 'did:agent:runtime',
          'request_id': 'cmd_thread_current',
          'state': 'succeeded',
          'result': <String, Object?>{
            'messages': <Object?>[
              <String, Object?>{
                'message_id': 'msg-late',
                'sender_did': 'did:human:bob',
                'text': 'late',
                'sent_at_ms': 300,
              },
              <String, Object?>{
                'message_id': 'msg-early',
                'sender_did': 'did:human:bob',
                'text': 'early',
                'sent_at_ms': 100,
              },
            ],
          },
        },
      );

      expect(
        container
            .read(agentInboxProvider)
            .thread
            .messages
            .map((message) => message.messageId),
        <String>['msg-early', 'msg-late'],
      );
    },
  );

  test('thread status payload parses attachment metadata', () async {
    final control = FakeAgentControlService()
      ..nextInboxThreadRequestId = 'cmd_thread_current';
    final container = _container(control);
    addTearDown(container.dispose);
    const item = AgentInboxItem(
      threadId: 'dm:peer-scope:v1:bob',
      kind: 'direct',
      title: 'bob.anpclaw.com',
      peerDid: 'did:human:bob',
      peerHandle: 'bob.anpclaw.com',
      peerUserId: 'user-bob',
      lastMessagePreview: '',
      unreadCount: 0,
      hasAttachments: false,
      lastContentType: 'text',
    );

    await container
        .read(agentInboxProvider.notifier)
        .queryThread(
          daemonAgentDid: 'did:agent:daemon',
          runtimeAgentDid: 'did:agent:runtime',
          item: item,
        );
    expect(control.lastInboxThreadPeerHandle, 'bob.anpclaw.com');
    expect(control.lastInboxThreadLimit, agentInboxPageSize);
    container.read(agentInboxProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'runtime_inbox_thread',
        'daemon_agent_did': 'did:agent:daemon',
        'runtime_agent_did': 'did:agent:runtime',
        'request_id': 'cmd_thread_current',
        'state': 'succeeded',
        'result': <String, Object?>{
          'thread_id': 'dm:peer-scope:v1:bob',
          'kind': 'direct',
          'title': 'bob.anpclaw.com',
          'messages': <Object?>[
            <String, Object?>{
              'message_id': 'msg-1',
              'sender_did': 'did:human:bob',
              'sender_handle': 'bob.anpclaw.com',
              'direction': 'incoming',
              'content_type': 'attachment',
              'text': 'caption',
              'attachments': <Object?>[
                <String, Object?>{
                  'attachment_id': 'att-1',
                  'filename': 'report.pdf',
                  'mime_type': 'application/pdf',
                  'size_bytes': 1024,
                },
              ],
            },
            <String, Object?>{
              'message_id': 'msg-2',
              'sender_did': 'did:human:bob',
              'sender_handle': 'bob.anpclaw.com',
              'direction': 'incoming',
              'content_type': 'attachment',
              'text': '',
              'attachments': <Object?>[
                <String, Object?>{
                  'attachment_id': 'att-2',
                  'mime_type': 'text/markdown',
                },
              ],
            },
          ],
        },
      },
    );

    final thread = container.read(agentInboxProvider).thread;
    expect(thread.messages, hasLength(2));
    expect(thread.messages.first.senderHandle, 'bob.anpclaw.com');
    expect(thread.messages.first.attachments.first.filename, 'report.pdf');
    expect(thread.messages.first.attachments.first.sizeBytes, 1024);
    expect(thread.messages.last.attachments.first.filename, isEmpty);
  });

  test('opening inbox thread clears local unread count immediately', () async {
    final control = FakeAgentControlService()
      ..nextInboxRequestId = 'cmd_inbox_current'
      ..nextInboxThreadRequestId = 'cmd_thread_current';
    final container = _container(control);
    addTearDown(container.dispose);

    await container
        .read(agentInboxProvider.notifier)
        .queryInbox(
          daemonAgentDid: 'did:agent:daemon',
          runtimeAgentDid: 'did:agent:runtime',
        );
    container.read(agentInboxProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'runtime_inbox',
        'daemon_agent_did': 'did:agent:daemon',
        'runtime_agent_did': 'did:agent:runtime',
        'request_id': 'cmd_inbox_current',
        'state': 'succeeded',
        'result': <String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'thread_id': 'dm:peer-scope:v1:bob',
              'kind': 'direct',
              'title': 'bob.anpclaw.com',
              'peer_handle': 'bob.anpclaw.com',
              'peer_user_id': 'user-bob',
              'last_message_preview': 'hello',
              'unread_count': 3,
            },
          ],
        },
      },
    );

    final item = container.read(agentInboxProvider).items.single;
    expect(item.unreadCount, 3);

    await container
        .read(agentInboxProvider.notifier)
        .queryThread(
          daemonAgentDid: 'did:agent:daemon',
          runtimeAgentDid: 'did:agent:runtime',
          item: item,
        );

    expect(container.read(agentInboxProvider).items.single.unreadCount, 0);
  });

  test(
    'attachment content type without attachment payload stays plain message',
    () {
      final message = AgentInboxMessage.fromJson(<String, Object?>{
        'message_id': 'msg-empty-attachment',
        'sender_did': 'did:human:bob',
        'sender_handle': 'bob.anpclaw.com',
        'direction': 'incoming',
        'content_type': 'attachment',
        'text': 'hello',
        'attachments': const <Object?>[],
      });

      expect(message.contentType, 'attachment');
      expect(message.text, 'hello');
      expect(message.attachments, isEmpty);
    },
  );

  test('list pagination appends unique items', () async {
    final control = FakeAgentControlService()
      ..nextInboxRequestId = 'cmd_inbox_first';
    final container = _container(control);
    addTearDown(container.dispose);

    await container
        .read(agentInboxProvider.notifier)
        .queryInbox(
          daemonAgentDid: 'did:agent:daemon',
          runtimeAgentDid: 'did:agent:runtime',
        );
    container.read(agentInboxProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'runtime_inbox',
        'daemon_agent_did': 'did:agent:daemon',
        'runtime_agent_did': 'did:agent:runtime',
        'request_id': 'cmd_inbox_first',
        'state': 'succeeded',
        'result': <String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'thread_id': 'dm:peer-scope:v1:bob',
              'kind': 'direct',
              'title': 'bob.anpclaw.com',
              'peer_handle': 'bob.anpclaw.com',
              'peer_user_id': 'user-bob',
            },
          ],
          'next_cursor': '1',
        },
      },
    );

    control.nextInboxRequestId = 'cmd_inbox_page_2';
    await container.read(agentInboxProvider.notifier).loadMoreInbox();
    expect(control.lastInboxScope, 'all');
    expect(control.lastInboxLimit, agentInboxPageSize);
    expect(control.lastInboxCursor, '1');
    container.read(agentInboxProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'runtime_inbox',
        'daemon_agent_did': 'did:agent:daemon',
        'runtime_agent_did': 'did:agent:runtime',
        'request_id': 'cmd_inbox_page_2',
        'state': 'succeeded',
        'result': <String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'thread_id': 'dm:peer-scope:v1:bob',
              'kind': 'direct',
              'title': 'bob.anpclaw.com duplicate',
              'peer_handle': 'bob.anpclaw.com',
              'peer_user_id': 'user-bob',
            },
            <String, Object?>{
              'thread_id': 'group:did:group:team',
              'kind': 'group',
              'title': 'Team',
            },
          ],
          'next_cursor': null,
        },
      },
    );

    final items = container.read(agentInboxProvider).items;
    expect(items.map((item) => item.threadId), <String>[
      'dm:peer-scope:v1:bob',
      'group:did:group:team',
    ]);
    expect(container.read(agentInboxProvider).nextCursor, isNull);
  });

  test(
    'list payload keeps stable direct item when duplicate aliases appear',
    () async {
      final control = FakeAgentControlService()
        ..nextInboxRequestId = 'cmd_inbox_current';
      final container = _container(control);
      addTearDown(container.dispose);

      await container
          .read(agentInboxProvider.notifier)
          .queryInbox(
            daemonAgentDid: 'did:agent:daemon',
            runtimeAgentDid: 'did:agent:runtime',
          );
      container.read(agentInboxProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime_inbox',
          'daemon_agent_did': 'did:agent:daemon',
          'runtime_agent_did': 'did:agent:runtime',
          'request_id': 'cmd_inbox_current',
          'state': 'succeeded',
          'result': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'thread_id': 'dm:did:human:bob',
                'kind': 'direct',
                'title': 'did:human:bob',
                'peer_did': 'did:human:bob',
                'last_message_preview': 'legacy',
                'last_message_at_ms': 100,
              },
              <String, Object?>{
                'thread_id': 'dm:peer-scope:v1:bob',
                'kind': 'direct',
                'title': 'bob.anpclaw.com',
                'peer_did': 'did:human:bob',
                'peer_handle': 'bob.anpclaw.com',
                'peer_user_id': 'user-bob',
                'last_message_preview': 'stable',
                'last_message_at_ms': 90,
              },
            ],
          },
        },
      );

      final items = container.read(agentInboxProvider).items;
      expect(items, hasLength(1));
      expect(items.single.threadId, 'dm:peer-scope:v1:bob');
      expect(items.single.title, 'bob.anpclaw.com');
      expect(items.single.peerHandle, 'bob.anpclaw.com');
      expect(items.single.lastMessagePreview, 'stable');
    },
  );

  test('thread pagination prepends older unique messages', () async {
    final control = FakeAgentControlService()
      ..nextInboxThreadRequestId = 'cmd_thread_first';
    final container = _container(control);
    addTearDown(container.dispose);
    const item = AgentInboxItem(
      threadId: 'dm:peer-scope:v1:bob',
      kind: 'direct',
      title: 'bob.anpclaw.com',
      peerDid: 'did:human:bob',
      peerHandle: 'bob.anpclaw.com',
      peerUserId: 'user-bob',
      lastMessagePreview: '',
      unreadCount: 0,
      hasAttachments: false,
      lastContentType: 'text',
    );

    await container
        .read(agentInboxProvider.notifier)
        .queryThread(
          daemonAgentDid: 'did:agent:daemon',
          runtimeAgentDid: 'did:agent:runtime',
          item: item,
        );
    container.read(agentInboxProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'runtime_inbox_thread',
        'daemon_agent_did': 'did:agent:daemon',
        'runtime_agent_did': 'did:agent:runtime',
        'request_id': 'cmd_thread_first',
        'state': 'succeeded',
        'result': <String, Object?>{
          'messages': <Object?>[
            <String, Object?>{
              'message_id': 'msg-new',
              'sender_did': 'did:human:bob',
              'text': 'new',
            },
          ],
          'next_cursor': '1',
        },
      },
    );

    control.nextInboxThreadRequestId = 'cmd_thread_page_2';
    await container.read(agentInboxProvider.notifier).loadMoreThread();
    expect(control.lastInboxThreadLimit, agentInboxPageSize);
    expect(control.lastInboxThreadCursor, '1');
    container.read(agentInboxProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'runtime_inbox_thread',
        'daemon_agent_did': 'did:agent:daemon',
        'runtime_agent_did': 'did:agent:runtime',
        'request_id': 'cmd_thread_page_2',
        'state': 'succeeded',
        'result': <String, Object?>{
          'messages': <Object?>[
            <String, Object?>{
              'message_id': 'msg-old',
              'sender_did': 'did:human:bob',
              'text': 'old',
            },
            <String, Object?>{
              'message_id': 'msg-new',
              'sender_did': 'did:human:bob',
              'text': 'duplicate',
            },
          ],
        },
      },
    );

    expect(
      container
          .read(agentInboxProvider)
          .thread
          .messages
          .map((message) => message.messageId),
      <String>['msg-old', 'msg-new'],
    );
  });

  test(
    'timeout keeps existing inbox data visible while refresh remains pending',
    () async {
      AgentInboxController.responseTimeout = const Duration(milliseconds: 10);
      addTearDown(() {
        AgentInboxController.responseTimeout = const Duration(seconds: 20);
      });
      final control = FakeAgentControlService()
        ..nextInboxRequestId = 'cmd_inbox_initial';
      final container = _container(control);
      addTearDown(container.dispose);

      await container
          .read(agentInboxProvider.notifier)
          .queryInbox(
            daemonAgentDid: 'did:agent:daemon',
            runtimeAgentDid: 'did:agent:runtime',
          );
      container.read(agentInboxProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime_inbox',
          'daemon_agent_did': 'did:agent:daemon',
          'runtime_agent_did': 'did:agent:runtime',
          'request_id': 'cmd_inbox_initial',
          'state': 'succeeded',
          'result': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'thread_id': 'dm:peer-scope:v1:bob',
                'kind': 'direct',
                'title': 'bob.anpclaw.com',
                'last_message_preview': 'hello',
              },
            ],
          },
        },
      );

      control.nextInboxRequestId = 'cmd_inbox_refresh';
      await container
          .read(agentInboxProvider.notifier)
          .queryInbox(
            daemonAgentDid: 'did:agent:daemon',
            runtimeAgentDid: 'did:agent:runtime',
            refresh: true,
          );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final state = container.read(agentInboxProvider);
      expect(state.items.single.lastMessagePreview, 'hello');
      expect(state.isLoading, isFalse);
      expect(state.isRefreshing, isTrue);
      expect(state.hasListTimeout, isTrue);
    },
  );

  test(
    'queryInbox applies status payload from local store when realtime is missed',
    () async {
      AgentInboxController.statusPollInterval = const Duration(milliseconds: 1);
      addTearDown(() {
        AgentInboxController.statusPollInterval = const Duration(
          milliseconds: 700,
        );
      });
      final control = FakeAgentControlService()
        ..nextInboxRequestId = 'cmd_inbox_local';
      final store = _FakeAgentControlStatusStore();
      final container = _container(control, statusStore: store);
      addTearDown(container.dispose);

      store.payloads['cmd_inbox_local'] = <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'runtime_inbox',
        'request_id': 'cmd_inbox_local',
        'state': 'succeeded',
        'daemon_agent_did': 'did:agent:daemon',
        'runtime_agent_did': 'did:agent:runtime',
        'result': <String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'thread_id': 'dm:peer-scope:v1:alice',
              'kind': 'direct',
              'title': 'alice.anpclaw.com',
              'peer_handle': 'alice.anpclaw.com',
              'peer_user_id': 'user-alice',
              'last_message_preview': 'hello from local status',
            },
          ],
        },
      };

      await container
          .read(agentInboxProvider.notifier)
          .queryInbox(
            daemonAgentDid: 'did:agent:daemon',
            runtimeAgentDid: 'did:agent:runtime',
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(agentInboxProvider);
      expect(state.items, hasLength(1));
      expect(state.items.single.title, 'alice.anpclaw.com');
      expect(state.items.single.lastMessagePreview, 'hello from local status');
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    },
  );

  test(
    'queryThread applies status payload from local store when realtime is missed',
    () async {
      AgentInboxController.statusPollInterval = const Duration(milliseconds: 1);
      addTearDown(() {
        AgentInboxController.statusPollInterval = const Duration(
          milliseconds: 700,
        );
      });
      final control = FakeAgentControlService()
        ..nextInboxThreadRequestId = 'cmd_thread_local';
      final store = _FakeAgentControlStatusStore();
      final container = _container(control, statusStore: store);
      addTearDown(container.dispose);
      const item = AgentInboxItem(
        threadId: 'dm:peer-scope:v1:alice',
        kind: 'direct',
        title: 'alice.anpclaw.com',
        lastMessagePreview: '',
        unreadCount: 0,
        hasAttachments: false,
        lastContentType: 'text',
      );
      store.payloads['cmd_thread_local'] = <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'runtime_inbox_thread',
        'request_id': 'cmd_thread_local',
        'state': 'succeeded',
        'daemon_agent_did': 'did:agent:daemon',
        'runtime_agent_did': 'did:agent:runtime',
        'result': <String, Object?>{
          'title': 'alice.anpclaw.com',
          'messages': <Object?>[
            <String, Object?>{
              'message_id': 'msg-local',
              'sender_did': 'did:alice',
              'sender_handle': 'alice.anpclaw.com',
              'direction': 'incoming',
              'text': 'thread from local status',
            },
          ],
        },
      };

      await container
          .read(agentInboxProvider.notifier)
          .queryThread(
            daemonAgentDid: 'did:agent:daemon',
            runtimeAgentDid: 'did:agent:runtime',
            item: item,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final thread = container.read(agentInboxProvider).thread;
      expect(thread.messages, hasLength(1));
      expect(thread.messages.single.text, 'thread from local status');
      expect(thread.isLoading, isFalse);
      expect(thread.error, isNull);
    },
  );
}

ProviderContainer _container(
  FakeAgentControlService control, {
  AgentControlStatusStore? statusStore,
}) {
  return ProviderContainer(
    overrides: <Override>[
      agentControlServiceProvider.overrideWithValue(control),
      if (statusStore != null)
        agentControlStatusStoreProvider.overrideWithValue(statusStore),
    ],
  );
}

class _FakeAgentControlStatusStore implements AgentControlStatusStore {
  final payloads = <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>?> findLatestDaemonStatusPayload({
    required String daemonAgentDid,
  }) async {
    return null;
  }

  @override
  Future<Map<String, Object?>?> findDaemonStatusPayload({
    required String daemonAgentDid,
    required String requestId,
  }) async {
    return null;
  }

  @override
  Future<Map<String, Object?>?> findStatusPayload({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String requestId,
    required String statusScope,
  }) async {
    final payload = payloads[requestId];
    if (payload == null) {
      return null;
    }
    if (payload['daemon_agent_did'] != daemonAgentDid ||
        payload['runtime_agent_did'] != runtimeAgentDid ||
        payload['status_scope'] != statusScope) {
      return null;
    }
    return payload;
  }
}
