import 'dart:convert';

import 'package:awiki_me/src/domain/entities/agent/acp_task.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/acp_execution_record.dart';
import 'package:awiki_me/src/presentation/agents/acp_session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class _Timeline extends ChatThreadsController {
  _Timeline(super.ref, List<ChatMessage> messages) {
    replace(messages);
  }
  void replace(List<ChatMessage> messages) {
    state = {'chat': ChatThreadState(threadId: 'chat', messages: messages)};
  }
}

ChatMessage message(
  String id, {
  String sender = 'did:agent',
  String text = '',
  Map<String, Object?>? payload,
  bool group = false,
}) => ChatMessage(
  localId: id,
  remoteId: id,
  conversationId: 'chat',
  threadId: 'chat',
  senderDid: sender,
  content: text,
  createdAt: DateTime.utc(2026, 9, 17),
  isMine: sender == 'did:me',
  groupId: group ? 'did:group' : null,
  sendState: MessageSendState.sent,
  payloadJson: payload == null ? null : jsonEncode(payload),
);
Map<String, Object?> task({
  String state = 'running',
  int revision = 1,
  bool group = false,
}) => {
  'schema': 'awiki.acp.task.v1',
  'session_key': 'session',
  'agent_did': 'did:agent',
  'conversation_id': 'remote-scope',
  'group': group,
  'revision': revision,
  'run_id': 'run',
  'source_message_id': 'prompt',
  'requester_did': 'did:me',
  'state': state,
  'text': '**Answer** with `code`',
  'tools': [
    {
      'kind': 'read',
      'title': '/Users/example/private/project/test.md',
      'status': 'completed',
    },
  ],
  'questions': [],
};

void main() {
  test(
    'tool summaries use categories and basenames without raw commands or credentials',
    () {
      final file = acpToolSummary({
        'kind': 'read',
        'title': '/Users/private/test.md',
        'status': 'completed',
      }, chinese: true);
      expect(file, (action: '读取文件', target: 'test.md', status: '已完成'));
      final command = acpToolSummary({
        'kind': 'execute',
        'title': 'curl -H secret=private-value https://server',
      }, chinese: false);
      expect(command.action, 'Run command');
      expect(command.target, isNull);
      expect(
        acpToolSummary(
          {'title': '/tmp/example.txt', 'status': 'in_progress'},
          chinese: true,
          taskEnded: true,
        ),
        (action: '调用工具', target: 'example.txt', status: '未完成'),
      );
      expect(
        acpToolSummary({
          'title': 'unknown tool parameters',
          'target': '/tmp/sk-fakeTokenValue',
        }, chinese: true).target,
        isNull,
      );
    },
  );

  test('handoff requires sender, local conversation, exact source and run', () {
    final record = AcpTask.parse(task(), localConversationId: 'chat')!;
    final annotations = {
      'awiki_reply_to_message_id': 'prompt',
      'awiki_run_id': 'run',
    };
    final finalReply = message(
      'reply',
      text: 'Answer',
      payload: {'annotations': annotations},
    );
    expect(acpFinalReplyForTask(record, [finalReply]), same(finalReply));
    expect(
      acpFinalReplyForTask(record, [
        message(
          'foreign',
          sender: 'did:other-agent',
          payload: {'annotations': annotations},
        ),
        message(
          'other-run',
          payload: {
            'annotations': {...annotations, 'awiki_run_id': 'different'},
          },
        ),
        message(
          'other-source',
          payload: {
            'annotations': {
              ...annotations,
              'awiki_reply_to_message_id': 'another',
            },
          },
        ),
        message('unrelated', text: 'Answer'),
        message(
          'wrong-group',
          group: true,
          payload: {'annotations': annotations},
        ),
        message(
          'malformed-run',
          payload: {
            'annotations': {...annotations, 'awiki_run_id': 42},
          },
        ),
      ]),
      isNull,
    );
  });

  for (final desktop in [false, true]) {
    for (final group in [false, true]) {
      testWidgets(
        'left response and retained activity handoff desktop=$desktop group=$group',
        (tester) async {
          await tester.binding.setSurfaceSize(
            desktop ? const Size(1100, 800) : const Size(390, 844),
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final conversation = ConversationSummary(
            conversationId: 'chat',
            threadId: 'chat',
            displayName: 'Agent',
            lastMessagePreview: '',
            lastMessageAt: DateTime.utc(2026),
            unreadCount: 0,
            isGroup: group,
            groupId: group ? 'did:group' : null,
            targetDid: group ? null : 'did:agent',
          );
          final prompt = message(
            'prompt',
            sender: 'did:me',
            text: 'Read the file',
            group: group,
          );
          await tester.pumpWidget(
            buildLocalizedTestApp(
              session: const SessionIdentity(
                did: 'did:me',
                credentialName: 'me',
                displayName: 'Me',
              ),
              home: CupertinoPageScaffold(
                child: ChatView(
                  conversation: conversation,
                  embedded: false,
                  macStyle: desktop,
                ),
              ),
              providerOverrides: [
                chatThreadsProvider.overrideWith(
                  (ref) => _Timeline(ref, [prompt]),
                ),
              ],
            ),
          );
          await tester.pumpAndSettle();
          final container = ProviderScope.containerOf(
            tester.element(find.byType(ChatView)),
          );
          final c = container.read(acpSessionsProvider.notifier);
          void project(Map<String, Object?> record) => c.applyConversation(
            message(
              'event',
              group: group,
              payload: {'schema': 'awiki.acp.status.v1', 'acp_task': record},
            ),
            'chat',
          );
          project(task(group: group));
          await tester.pumpAndSettle();
          final preview = find.byKey(const ValueKey('acp-reply-bubble:run'));
          final avatar = find.byKey(
            const Key('chat-message-avatar:acp:run:peer'),
          );
          final record = find.byKey(const ValueKey('acp-record-toggle:run'));
          final promptBubble = find.byKey(
            const Key('chat-message-bubble:prompt'),
          );
          expect(
            tester.getRect(preview).left,
            lessThan(tester.getRect(promptBubble).left),
          );
          expect(
            tester.getRect(avatar).right,
            lessThan(tester.getRect(preview).left),
          );
          expect(
            tester.getRect(record).left,
            closeTo(tester.getRect(preview).left, 0.1),
          );
          expect(
            tester.getRect(record).bottom,
            lessThanOrEqualTo(tester.getRect(preview).top),
          );
          await tester.tap(record);
          await tester.pumpAndSettle();
          expect(find.text('读取文件 · test.md · 已完成'), findsOneWidget);
          expect(find.textContaining('/Users/example'), findsNothing);
          project(task(state: 'finished', revision: 2, group: group));
          await tester.pumpAndSettle();
          expect(
            preview,
            findsOneWidget,
            reason:
                'Terminal status must not remove the preview before Core delivers the reply',
          );
          (container.read(chatThreadsProvider.notifier) as _Timeline).replace(
            [],
          );
          await tester.pumpAndSettle();
          expect(
            preview,
            findsOneWidget,
            reason:
                'The latest task remains visible when its source is outside the Core window',
          );
          expect(find.text('原指令不在当前消息记录中'), findsOneWidget);
          final reply = message(
            'reply',
            text: '**Answer** with `code`',
            group: group,
            payload: {
              'annotations': {
                'awiki_reply_to_message_id': 'prompt',
                'awiki_run_id': 'run',
              },
            },
          );
          (container.read(chatThreadsProvider.notifier) as _Timeline).replace([
            reply,
          ]);
          await tester.pumpAndSettle();
          expect(preview, findsNothing);
          expect(
            find.byKey(const Key('chat-message-bubble:reply')),
            findsOneWidget,
          );
          expect(record, findsOneWidget);
          expect(
            find.text('读取文件 · test.md · 已完成'),
            findsOneWidget,
            reason: 'Expanded state survives preview/final handoff',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('stopped task retains partial answer with incomplete label', (
    tester,
  ) async {
    final conversation = ConversationSummary(
      conversationId: 'chat',
      threadId: 'chat',
      displayName: 'Agent',
      lastMessagePreview: '',
      lastMessageAt: DateTime.utc(2026),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent',
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        providerOverrides: [
          chatThreadsProvider.overrideWith(
            (ref) => _Timeline(ref, [
              message('prompt', sender: 'did:me', text: 'Help'),
            ]),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    ProviderScope.containerOf(tester.element(find.byType(ChatView)))
        .read(acpSessionsProvider.notifier)
        .applyConversation(
          message(
            'event',
            payload: {
              'schema': 'awiki.acp.status.v1',
              'acp_task': task(state: 'cancelled'),
            },
          ),
          'chat',
        );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('acp-reply-bubble:run')), findsOneWidget);
    expect(find.byKey(const ValueKey('acp-incomplete:run')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
