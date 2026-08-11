import 'dart:async';

import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/peer_display_profile.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/profile/peer_display_profile_provider.dart';
import 'package:awiki_me/src/presentation/shared/avatar_badge.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets(
    'chat mention preloads one roster and filters consecutive queries locally',
    (tester) async {
      final rosterLoad = Completer<void>();
      final gateway = FakeAwikiGateway()
        ..listGroupMembersCompleter = rosterLoad
        ..groupMembersByGroupId = const <String, List<GroupMemberSummary>>{
          'group-mention': <GroupMemberSummary>[
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
      addTearDown(() {
        if (!rosterLoad.isCompleted) {
          rosterLoad.complete();
        }
      });
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:u:me',
        handle: 'me',
        displayName: 'Me',
        credentialName: 'me.json',
      );
      final conversation = ConversationSummary(
        threadId: 'group:group-mention',
        conversationId: 'group:group-mention',
        displayName: 'Mention Group',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 7, 17, 18),
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
      await tester.pump();

      expect(gateway.listGroupMembersCalls, 1);
      expect(gateway.loadCachedDisplayProfilesCalls, 0);
      await tester.enterText(find.byType(CupertinoTextField), '@A');
      await tester.pump();
      expect(gateway.listGroupMembersCalls, 1);

      rosterLoad.complete();
      await tester.pumpAndSettle();
      expect(find.text('@Alice'), findsOneWidget);
      expect(gateway.loadPublicProfileQueries, isEmpty);
      expect(gateway.loadCachedDisplayProfilesCalls, 1);

      await tester.enterText(find.byType(CupertinoTextField), '@Al');
      await tester.pump();
      expect(find.text('@Alice'), findsOneWidget);
      expect(gateway.listGroupMembersCalls, 1);
      expect(gateway.loadCachedDisplayProfilesCalls, 1);

      await tester.enterText(find.byType(CupertinoTextField), '@Ali');
      await tester.pump();
      final panel = find.byKey(const Key('chat-mention-candidate-panel'));
      expect(panel, findsOneWidget);
      expect(
        find.descendant(of: panel, matching: find.text('@Alice')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.byType(CupertinoActivityIndicator),
        ),
        findsNothing,
      );
      expect(gateway.listGroupMembersCalls, 1);
    },
  );

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
        conversationId: 'group:group-mention',
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

  testWidgets(
    'chat mention waits for one local profile prewarm before first candidates',
    (tester) async {
      const agentDid = 'did:wba:awiki.info:agent:runtime:cgw-cx-038:e1_agent';
      final profileGate = Completer<void>();
      final gateway = FakeAwikiGateway()
        ..cachedPeerDisplayProfilesCompleter = profileGate
        ..cachedPeerDisplayProfiles = const <PeerDisplayProfile>[
          PeerDisplayProfile(
            did: agentDid,
            peerPersonaId: 'persona:cgw-cx-038',
            displayName: '第一个 Codex',
            handle: 'cgw-cx-038.awiki.info',
          ),
        ]
        ..groupMembersByGroupId = const <String, List<GroupMemberSummary>>{
          'group-mention': <GroupMemberSummary>[
            GroupMemberSummary(
              userId: agentDid,
              did: agentDid,
              handle: 'cgw-cx-038.awiki.info',
              role: 'member',
              peerPersonaId: 'persona:cgw-cx-038',
              subjectType: GroupMemberSubjectType.agent,
            ),
          ],
        };
      addTearDown(() {
        if (!profileGate.isCompleted) {
          profileGate.complete();
        }
      });
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:user:me:e1_current',
        handle: 'me.awiki.info',
        displayName: 'Me',
        credentialName: 'me.json',
      );
      final conversation = ConversationSummary(
        threadId: 'group:group-mention',
        conversationId: 'group:group-mention',
        displayName: 'Mention Group',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 8, 11, 12),
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
      await tester.pump();
      await tester.enterText(find.byType(CupertinoTextField), '@');
      await tester.pump();

      final panel = find.byKey(const Key('chat-mention-candidate-panel'));
      expect(panel, findsOneWidget);
      expect(
        find.descendant(
          of: panel,
          matching: find.byType(CupertinoActivityIndicator),
        ),
        findsOneWidget,
      );
      expect(find.text('@cgw-cx-038'), findsNothing);
      expect(gateway.listGroupMembersCalls, 1);
      expect(gateway.loadCachedDisplayProfilesCalls, 1);

      profileGate.complete();
      await tester.pumpAndSettle();

      expect(find.text('@第一个 Codex'), findsOneWidget);
      expect(
        find.text('@cgw-cx-038.awiki.info · did:wba:aw…_agent'),
        findsOneWidget,
      );
      expect(gateway.loadPublicProfileQueries, isEmpty);

      await tester.enterText(find.byType(CupertinoTextField), '@cgw');
      await tester.pumpAndSettle();
      expect(find.text('@第一个 Codex'), findsOneWidget);
      expect(gateway.listGroupMembersCalls, 1);
      expect(gateway.loadCachedDisplayProfilesCalls, 1);
    },
  );

  testWidgets(
    'chat mention candidate uses the shared peer name and avatar projection',
    (tester) async {
      const peerDid = 'did:wba:awiki.info:user:zhuocheng:e1_peer';
      const peerPersonaId = 'persona:zhuocheng';
      const avatarUri = 'https://awiki.info/avatar/zhuocheng.png';
      final gateway = FakeAwikiGateway()
        ..groupMembersByGroupId = const <String, List<GroupMemberSummary>>{
          'group-mention': <GroupMemberSummary>[
            GroupMemberSummary(
              userId: peerDid,
              did: peerDid,
              handle: 'zhuocheng.awiki.info',
              role: 'member',
              peerPersonaId: peerPersonaId,
              displayName: 'zhuocheng',
              subjectType: GroupMemberSubjectType.human,
            ),
          ],
        };
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:user:me:e1_current',
        handle: 'me.awiki.info',
        displayName: 'Me',
        credentialName: 'me.json',
      );
      final conversation = ConversationSummary(
        threadId: 'group:group-mention',
        conversationId: 'group:group-mention',
        displayName: 'Mention Group',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 7, 17, 17, 14),
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
          .read(peerDisplayProfileProvider.notifier)
          .updateFromRemote(
            ownerDid: session.did,
            peerPersonaId: peerPersonaId,
            profile: const UserProfile(
              did: peerDid,
              displayName: '卓诚',
              bio: '',
              tags: <String>[],
              profileMarkdown: '',
              fullHandle: 'zhuocheng.awiki.info',
              avatarUri: avatarUri,
            ),
          );
      await tester.pump();

      await tester.enterText(find.byType(CupertinoTextField), '@');
      await tester.pump();
      await tester.pump();

      expect(find.text('@卓诚'), findsOneWidget);
      final candidate = find.byKey(
        const Key('chat-mention-candidate-member:$peerDid'),
      );
      expect(candidate, findsOneWidget);
      final avatar = tester.widget<AvatarBadge>(
        find.descendant(of: candidate, matching: find.byType(AvatarBadge)),
      );
      expect(avatar.seed, '卓诚');
      expect(avatar.avatarUri, avatarUri);
    },
  );

  testWidgets('chat mention composer hides self and group selector shortcuts', (
    tester,
  ) async {
    final gateway = FakeAwikiGateway()
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        'group-mention': const <GroupMemberSummary>[
          GroupMemberSummary(
            userId: 'did:wba:awiki.info:u:me',
            did: 'did:wba:awiki.info:u:me',
            handle: 'me',
            role: 'owner',
            displayName: 'Me',
            subjectType: GroupMemberSubjectType.human,
          ),
          GroupMemberSummary(
            userId: 'did:wba:awiki.info:u:alice',
            did: 'did:wba:awiki.info:u:alice',
            handle: 'alice',
            role: 'member',
            displayName: 'Alice',
            subjectType: GroupMemberSubjectType.human,
          ),
          GroupMemberSummary(
            userId: 'did:wba:awiki.info:agent:runtime:hermes:e1_agent',
            did: 'did:wba:awiki.info:agent:runtime:hermes:e1_agent',
            handle: 'hermes',
            role: 'member',
            displayName: 'Hermes',
            subjectType: GroupMemberSubjectType.agent,
          ),
        ],
      };
    const session = SessionIdentity(
      did: 'did:wba:awiki.info:u:me',
      handle: 'me.awiki.info',
      displayName: 'Me',
      credentialName: 'me.json',
    );
    final conversation = ConversationSummary(
      threadId: 'group:group-mention',
      conversationId: 'group:group-mention',
      displayName: 'Mention Group',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 14, 20, 42),
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

    await tester.enterText(find.byType(CupertinoTextField), '@');
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('chat-mention-candidate-panel')),
      findsOneWidget,
    );
    expect(find.text('@me'), findsNothing);
    expect(find.text('@所有人'), findsNothing);
    expect(find.text('@所有用户'), findsNothing);
    expect(find.text('@所有智能体'), findsNothing);
    expect(find.text('@Alice'), findsOneWidget);
    expect(find.text('@Hermes'), findsOneWidget);
  });

  testWidgets('chat mention keyboard selection stays visible in long lists', (
    tester,
  ) async {
    final members = <GroupMemberSummary>[
      for (var index = 0; index < 18; index += 1)
        GroupMemberSummary(
          userId: 'did:wba:awiki.info:u:user$index',
          did: 'did:wba:awiki.info:u:user$index',
          handle: 'user$index',
          role: 'member',
          displayName: 'User $index',
          subjectType: GroupMemberSubjectType.human,
        ),
    ];
    final gateway = FakeAwikiGateway()
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        'group-mention': members,
      };
    const session = SessionIdentity(
      did: 'did:wba:awiki.info:u:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'me.json',
    );
    final conversation = ConversationSummary(
      threadId: 'group:group-mention',
      conversationId: 'group:group-mention',
      displayName: 'Mention Group',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 14, 20, 40),
      unreadCount: 0,
      isGroup: true,
      groupId: 'group-mention',
    );

    addTearDown(() {
      tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(900, 720));

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

    await tester.enterText(find.byType(CupertinoTextField), '@');
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byType(CupertinoTextField));
    await tester.pump();

    expect(
      find.byKey(const Key('chat-mention-candidate-panel')),
      findsOneWidget,
    );

    for (var index = 0; index < 12; index += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pump();

    final selectedFinder = find.byKey(
      const Key('chat-mention-selected-candidate'),
    );
    expect(selectedFinder, findsOneWidget);
    expect(
      find.descendant(of: selectedFinder, matching: find.text('@User 12')),
      findsOneWidget,
    );

    final panelRect = tester.getRect(
      find.byKey(const Key('chat-mention-candidate-panel')),
    );
    final selectedRect = tester.getRect(selectedFinder);
    expect(selectedRect.top, greaterThanOrEqualTo(panelRect.top));
    expect(selectedRect.bottom, lessThanOrEqualTo(panelRect.bottom));
  });

  testWidgets(
    'chat mention keyboard selection stays visible in compact layout',
    (tester) async {
      final members = <GroupMemberSummary>[
        for (var index = 0; index < 18; index += 1)
          GroupMemberSummary(
            userId: 'did:wba:awiki.info:u:compact-user$index',
            did: 'did:wba:awiki.info:u:compact-user$index',
            handle: 'compact-user$index',
            role: 'member',
            displayName: 'Compact User $index',
            subjectType: GroupMemberSubjectType.human,
          ),
      ];
      final gateway = FakeAwikiGateway()
        ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
          'group-mention': members,
        };
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:u:me',
        handle: 'me',
        displayName: 'Me',
        credentialName: 'me.json',
      );
      final conversation = ConversationSummary(
        threadId: 'group:group-mention',
        conversationId: 'group:group-mention',
        displayName: 'Mention Group',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 6, 14, 20, 45),
        unreadCount: 0,
        isGroup: true,
        groupId: 'group-mention',
      );

      addTearDown(() {
        tester.binding.setSurfaceSize(null);
      });
      await tester.binding.setSurfaceSize(const Size(390, 844));

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: CupertinoPageScaffold(
            child: ChatView(conversation: conversation, embedded: true),
          ),
          gateway: gateway,
          session: session,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(CupertinoTextField), '@');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byType(CupertinoTextField));
      await tester.pump();

      expect(
        find.byKey(const Key('chat-mention-candidate-panel')),
        findsOneWidget,
      );

      for (var index = 0; index < 12; index += 1) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 120));
      }
      await tester.pump();

      final selectedFinder = find.byKey(
        const Key('chat-mention-selected-candidate'),
      );
      expect(selectedFinder, findsOneWidget);
      expect(
        find.descendant(
          of: selectedFinder,
          matching: find.text('@Compact User 12'),
        ),
        findsOneWidget,
      );

      final panelRect = tester.getRect(
        find.byKey(const Key('chat-mention-candidate-panel')),
      );
      final selectedRect = tester.getRect(selectedFinder);
      expect(selectedRect.top, greaterThanOrEqualTo(panelRect.top));
      expect(selectedRect.bottom, lessThanOrEqualTo(panelRect.bottom));
    },
  );

  testWidgets('chat mention highlight renders selected range as styled span', (
    tester,
  ) async {
    const text = '@hermes 请总结';
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
          '{"text":"@hermes 请总结","mentions":[{"id":"men_hermes","range":{"start":0,"end":7,"unit":"unicode_code_point"},"target":{"kind":"agent","did":"did:wba:awiki.info:agent:runtime:hermes:e1_agent"},"mention_role":"addressee"}]}',
      createdAt: DateTime(2026, 6, 14, 21),
      isMine: false,
      sendState: MessageSendState.sent,
      mentions: const <ChatMessageMention>[
        ChatMessageMention(
          id: 'men_hermes',
          surface: '@hermes',
          start: 0,
          end: '@hermes'.length,
          target: ChatMentionTargetDraft.member(
            kind: ChatMentionTargetKind.agent,
            did: 'did:wba:awiki.info:agent:runtime:hermes:e1_agent',
            handle: 'hermes',
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
      conversationId: 'group:group-mention',
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
        .debugSeedMessageForTesting(message);
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
            _textSpanHasStyledMention(widget.text, '@hermes'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'agent reply mention projects the current profile without mutating payload',
    (tester) async {
      const rawText = '@cgw051 你好';
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:user:cgw051:e1_current',
        handle: 'cgw051.awiki.info',
        displayName: '旧会话名称',
        credentialName: 'me.json',
      );
      const currentProfile = UserProfile(
        did: 'did:wba:awiki.info:user:cgw051:e1_current',
        displayName: '测试用户',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
        fullHandle: 'cgw051.awiki.info',
      );
      final conversation = ConversationSummary(
        threadId: 'group:group-self-mention',
        conversationId: 'group:group-self-mention',
        displayName: 'Mention Group',
        lastMessagePreview: rawText,
        lastMessageAt: DateTime(2026, 8, 11, 12, 10),
        unreadCount: 0,
        isGroup: true,
        groupId: 'group-self-mention',
      );
      final message = ChatMessage(
        localId: 'msg-self-mention',
        remoteId: 'msg-self-mention',
        threadId: conversation.conversationId,
        senderDid: 'did:wba:awiki.info:agent:runtime:codex:e1_agent',
        senderName: 'Codex',
        groupId: conversation.groupId,
        content: rawText,
        originalType: 'application/json',
        payloadJson:
            '{"text":"@cgw051 你好","mentions":[{"id":"reply_me","range":{"start":0,"end":7,"unit":"unicode_code_point"},"target":{"kind":"human","did":"did:wba:awiki.info:user:cgw051:e1_current","display_name":"cgw051"},"mention_role":"addressee"}]}',
        createdAt: DateTime(2026, 8, 11, 12, 10),
        isMine: false,
        sendState: MessageSendState.sent,
        mentions: const <ChatMessageMention>[
          ChatMessageMention(
            id: 'reply_me',
            surface: '@cgw051',
            start: 0,
            end: 7,
            target: ChatMentionTargetDraft.member(
              kind: ChatMentionTargetKind.human,
              did: 'did:wba:awiki.info:user:cgw051:e1_current',
              handle: 'cgw051.awiki.info',
              displayName: 'cgw051',
            ),
          ),
        ],
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
          gateway: FakeAwikiGateway(),
          session: session,
          profile: currentProfile,
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatView)),
        listen: false,
      );
      container
          .read(chatThreadsProvider.notifier)
          .debugSeedMessageForTesting(message);
      await tester.pumpAndSettle();

      expect(
        container
            .read(chatThreadProvider(conversation.threadId))
            .messages
            .single
            .content,
        rawText,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              _textSpanHasStyledMention(widget.text, '@测试用户'),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              _textSpanHasStyledMention(widget.text, '@cgw051'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'peer profile update reprojects one structured mention by stable DID',
    (tester) async {
      const agentDid = 'did:wba:awiki.info:agent:runtime:cgw-cx-038:e1_agent';
      const rawText = '@cgw-cx-038 你好';
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:user:me:e1_current',
        handle: 'me.awiki.info',
        displayName: 'Me',
        credentialName: 'me.json',
      );
      final conversation = ConversationSummary(
        threadId: 'group:group-peer-mention',
        conversationId: 'group:group-peer-mention',
        displayName: 'Mention Group',
        lastMessagePreview: rawText,
        lastMessageAt: DateTime(2026, 8, 11, 12, 20),
        unreadCount: 0,
        isGroup: true,
        groupId: 'group-peer-mention',
      );
      final message = ChatMessage(
        localId: 'msg-peer-mention',
        remoteId: 'msg-peer-mention',
        threadId: conversation.conversationId,
        senderDid: session.did,
        groupId: conversation.groupId,
        content: rawText,
        createdAt: DateTime(2026, 8, 11, 12, 20),
        isMine: true,
        sendState: MessageSendState.sent,
        mentions: const <ChatMessageMention>[
          ChatMessageMention(
            id: 'mention-agent',
            surface: '@cgw-cx-038',
            start: 0,
            end: 11,
            target: ChatMentionTargetDraft.member(
              kind: ChatMentionTargetKind.agent,
              did: agentDid,
              handle: 'cgw-cx-038.awiki.info',
              displayName: 'cgw-cx-038',
            ),
          ),
        ],
      );
      final gateway = FakeAwikiGateway()
        ..groupMembersByGroupId = const <String, List<GroupMemberSummary>>{
          'group-peer-mention': <GroupMemberSummary>[
            GroupMemberSummary(
              userId: agentDid,
              did: agentDid,
              handle: 'cgw-cx-038.awiki.info',
              role: 'member',
              peerPersonaId: 'persona:cgw-cx-038',
              subjectType: GroupMemberSubjectType.agent,
            ),
          ],
        };

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
          .debugSeedMessageForTesting(message);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              _textSpanHasStyledMention(widget.text, '@cgw-cx-038'),
        ),
        findsOneWidget,
      );

      container
          .read(peerDisplayProfileProvider.notifier)
          .updateFromRemote(
            ownerDid: session.did,
            peerPersonaId: 'persona:cgw-cx-038',
            profile: const UserProfile(
              did: agentDid,
              displayName: '第一个 Codex',
              bio: '',
              tags: <String>[],
              profileMarkdown: '',
              fullHandle: 'cgw-cx-038.awiki.info',
            ),
          );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              _textSpanHasStyledMention(widget.text, '@第一个 Codex'),
        ),
        findsOneWidget,
      );
      expect(
        container
            .read(chatThreadProvider(conversation.threadId))
            .messages
            .single
            .content,
        rawText,
      );
      expect(
        find.byKey(const Key('chat-message-bubble:msg-peer-mention')),
        findsOneWidget,
      );
    },
  );

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
      conversationId: 'dm:did:wba:awiki.info:u:peer',
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
      style?.fontWeight == FontWeight.w400 &&
      style?.color != null &&
      style?.backgroundColor != null) {
    return true;
  }
  return span.children?.any(
        (child) => _textSpanHasStyledMention(child, mentionText),
      ) ??
      false;
}
