import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets(
    'chat mention composer shows group candidates and inserts draft range',
    (tester) async {
      final gateway = FakeAwikiGateway()
        ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
          'group-mention': const <GroupMemberSummary>[
            GroupMemberSummary(
              userId: 'did:wba:awiki.info:u:hermes',
              did: 'did:wba:awiki.info:u:hermes',
              handle: 'hermes1',
              role: 'member',
              displayName: 'Hermes One',
              subjectType: GroupMemberSubjectType.agent,
            ),
            GroupMemberSummary(
              userId: 'did:wba:awiki.info:u:alice',
              did: 'did:wba:awiki.info:u:alice',
              handle: 'alice',
              role: 'member',
              displayName: 'Alice',
              subjectType: GroupMemberSubjectType.human,
            ),
          ],
        };
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:u:me',
        handle: 'me',
        displayName: 'Me',
        credentialName: 'me.json',
      );
      final conversation = ConversationSummary(
        threadId: 'group:group-mention',
        displayName: 'Mention Group',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 6, 14, 20, 40),
        unreadCount: 0,
        isGroup: true,
        groupId: 'group-mention',
      );

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: CupertinoPageScaffold(
            child: ChatView(
              conversation: conversation,
              embedded: true,
              macStyle: true,
            ),
          ),
          gateway: gateway,
          session: session,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(CupertinoTextField), '@Herm');
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('chat-mention-candidate-panel')),
        findsOneWidget,
      );
      expect(find.text('@Hermes One'), findsOneWidget);

      await tester.tap(find.text('@Hermes One'));
      await tester.pumpAndSettle();

      final textField = tester.widget<CupertinoTextField>(
        find.byType(CupertinoTextField),
      );
      expect(textField.controller!.text, '@Hermes One ');
      expect(
        find.byKey(const Key('chat-mention-candidate-panel')),
        findsNothing,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatView)),
        listen: false,
      );
      final draft = container
          .read(chatComposerDraftsProvider.notifier)
          .draftFor(conversation);
      expect(draft.mentions, hasLength(1));
      expect(draft.validMentions, hasLength(1));
      expect(draft.mentions.single.surface, '@Hermes One');
      expect(draft.mentions.single.target.did, 'did:wba:awiki.info:u:hermes');
      expect(draft.p9MentionJsonForSend().single['target'], <String, Object?>{
        'kind': 'agent',
        'did': 'did:wba:awiki.info:u:hermes',
      });
    },
  );

  testWidgets('chat mention highlight renders selected range as styled span', (
    tester,
  ) async {
    const text = '@所有 Agents 请总结';
    final gateway = FakeAwikiGateway();
    final message = ChatMessage(
      localId: 'msg-mention-highlight',
      remoteId: 'msg-mention-highlight',
      threadId: 'group:group-mention',
      senderDid: 'did:wba:awiki.info:u:peer',
      senderName: 'Peer',
      groupId: 'group-mention',
      content: text,
      originalType: 'application/json',
      payloadJson:
          '{"text":"@所有 Agents 请总结","mentions":[{"id":"men_agents","range":{"start":0,"end":10,"unit":"unicode_code_point"},"target":{"kind":"group_selector","selector":"agents"},"mention_role":"addressee"}]}',
      createdAt: DateTime(2026, 6, 14, 21),
      isMine: false,
      sendState: MessageSendState.sent,
      mentions: const <ChatMessageMention>[
        ChatMessageMention(
          id: 'men_agents',
          surface: '@所有 Agents',
          start: 0,
          end: '@所有 Agents'.length,
          target: ChatMentionTargetDraft.groupSelector(
            ChatMentionSelector.agents,
          ),
        ),
      ],
    );
    const session = SessionIdentity(
      did: 'did:wba:awiki.info:u:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'me.json',
    );
    final conversation = ConversationSummary(
      threadId: 'group:group-mention',
      displayName: 'Mention Group',
      lastMessagePreview: text,
      lastMessageAt: DateTime(2026, 6, 14, 21),
      unreadCount: 0,
      isGroup: true,
      groupId: 'group-mention',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(
            conversation: conversation,
            embedded: true,
            macStyle: true,
          ),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
      listen: false,
    );
    container
        .read(chatThreadsProvider.notifier)
        .applyRealtimeUpdate(message, conversation: conversation);
    await tester.pumpAndSettle();

    expect(
      container
          .read(chatThreadProvider(conversation.threadId))
          .messages
          .single
          .content,
      text,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            _textSpanHasStyledMention(widget.text, '@所有 Agents'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('chat mention composer does not open candidates in direct chat', (
    tester,
  ) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:wba:awiki.info:u:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'me.json',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:did:wba:awiki.info:u:peer',
      displayName: 'Peer',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 14, 20, 41),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:wba:awiki.info:u:peer',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(
            conversation: conversation,
            embedded: true,
            macStyle: true,
          ),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField), '@Herm');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-mention-candidate-panel')), findsNothing);
  });
}

bool _textSpanHasStyledMention(InlineSpan span, String mentionText) {
  if (span is! TextSpan) {
    return false;
  }
  final style = span.style;
  if (span.text == mentionText &&
      style?.fontWeight == FontWeight.w700 &&
      style?.color != null &&
      style?.backgroundColor != null) {
    return true;
  }
  return span.children?.any(
        (child) => _textSpanHasStyledMention(child, mentionText),
      ) ??
      false;
}
