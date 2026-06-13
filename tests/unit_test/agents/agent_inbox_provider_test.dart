// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:awiki_me/src/app/app_services.dart';
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
      container.read(agentInboxProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime_inbox',
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
    container.read(agentInboxProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'runtime_inbox_thread',
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
    expect(thread.messages.last.attachments.first.filename, '未命名附件');
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
    container.read(agentInboxProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'runtime_inbox',
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
    container.read(agentInboxProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'runtime_inbox_thread',
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
}

ProviderContainer _container(FakeAgentControlService control) {
  return ProviderContainer(
    overrides: <Override>[
      agentControlServiceProvider.overrideWithValue(control),
    ],
  );
}
