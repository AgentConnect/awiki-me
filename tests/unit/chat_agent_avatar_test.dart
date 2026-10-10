import 'dart:convert';

import 'package:awiki_me/src/domain/entities/agent/agent_avatar.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/agents/acp_session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/shared/agent_avatar_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

const _agentDid = 'did:agent:finance';

AgentSummary _agent(String did, String preset) => AgentSummary(
  agentDid: did,
  kind: AgentKind.runtime,
  runtime: 'codex',
  displayName: '金融助手',
  activeState: 'active',
  latest: const AgentLatestStatus(status: 'ready'),
  avatar: AgentAvatar(
    agentId: did,
    source: 'preset',
    presetId: preset,
    animatedUri: '/avatars/presets/$preset.gif',
    posterUri: '/avatars/presets/$preset.png',
    version: preset,
    status: 'ready',
  ),
);

class _Inventory extends AgentsController {
  _Inventory(super.ref) {
    replace('financing');
  }

  void replace(String preset) {
    state = AgentsState(
      agents: [_agent(_agentDid, preset), _agent('did:agent:other', 'legal')],
    );
  }
}

class _Timeline extends ChatThreadsController {
  _Timeline(super.ref, List<ChatMessage> messages) {
    state = {'chat': ChatThreadState(threadId: 'chat', messages: messages)};
  }
}

ChatMessage _message(String id, String sender, {required bool group}) =>
    ChatMessage(
      localId: id,
      remoteId: id,
      conversationId: 'chat',
      threadId: 'chat',
      senderDid: sender,
      content: id,
      createdAt: DateTime.utc(2026, 10, 9),
      isMine: sender == 'did:me',
      groupId: group ? 'did:group' : null,
      sendState: MessageSendState.sent,
    );

Finder _avatar(String id) => find.byKey(Key('chat-message-avatar:$id:peer'));

void _expectPreset(WidgetTester tester, String id, String preset) {
  final imageFinder = find.descendant(
    of: _avatar(id),
    matching: find.byType(AgentAvatarImage),
  );
  expect(imageFinder, findsOneWidget);
  final avatar = tester.widget<AgentAvatarImage>(imageFinder);
  expect(avatar.uri, '/avatars/presets/$preset.gif');
  expect(avatar.posterUri, '/avatars/presets/$preset.png');
  final image = tester.widget<Image>(
    find.descendant(of: imageFinder, matching: find.byType(Image)).first,
  );
  final asset = (image.image as ResizeImage).imageProvider as AssetImage;
  expect(asset.assetName, 'assets/avatars/agents/$preset.png');
}

void main() {
  for (final desktop in [false, true]) {
    for (final group in [false, true]) {
      testWidgets(
        'chat and ACP avatars follow sender Inventory desktop=$desktop group=$group',
        (tester) async {
          final size = desktop ? const Size(1100, 900) : const Size(390, 844);
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final conversation = ConversationSummary(
            conversationId: 'chat',
            threadId: 'chat',
            displayName: '金融助手',
            lastMessagePreview: '',
            lastMessageAt: DateTime.utc(2026, 10, 9),
            unreadCount: 0,
            isGroup: group,
            groupId: group ? 'did:group' : null,
            targetDid: group ? null : _agentDid,
          );
          final messages = [
            _message('prompt', 'did:me', group: group),
            _message('ready', _agentDid, group: group),
            if (group) _message('other', 'did:agent:other', group: true),
            if (group) _message('human', 'did:human', group: true),
          ];
          await tester.pumpWidget(
            buildLocalizedTestApp(
              session: const SessionIdentity(
                did: 'did:me',
                credentialName: 'me',
                displayName: 'Me',
              ),
              home: MediaQuery(
                data: MediaQueryData(size: size, disableAnimations: true),
                child: CupertinoPageScaffold(
                  child: ChatView(
                    conversation: conversation,
                    embedded: false,
                    macStyle: desktop,
                  ),
                ),
              ),
              providerOverrides: [
                agentsProvider.overrideWith((ref) => _Inventory(ref)),
                chatThreadsProvider.overrideWith(
                  (ref) => _Timeline(ref, messages),
                ),
              ],
            ),
          );
          await tester.pumpAndSettle();
          _expectPreset(tester, 'ready', 'financing');
          expect(
            find.descendant(
              of: find.byKey(const Key('chat-message-avatar:prompt:mine')),
              matching: find.byType(AgentAvatarImage),
            ),
            findsNothing,
          );
          if (group) {
            _expectPreset(tester, 'other', 'legal');
            expect(
              find.descendant(
                of: _avatar('human'),
                matching: find.byType(AgentAvatarImage),
              ),
              findsNothing,
            );
          }
          final container = ProviderScope.containerOf(
            tester.element(find.byType(ChatView)),
          );
          final control = _message('event', _agentDid, group: group).copyWith(
            payloadJson: jsonEncode({
              'schema': 'awiki.acp.status.v1',
              'acp_task': {
                'schema': 'awiki.acp.task.v1',
                'session_key': 'session',
                'agent_did': _agentDid,
                'conversation_id': 'remote-scope',
                'group': group,
                'revision': 1,
                'run_id': 'run',
                'source_message_id': 'prompt',
                'requester_did': 'did:me',
                'state': 'running',
                'text': '流式回复',
                'tools': [],
                'questions': [],
              },
            }),
          );
          container
              .read(acpSessionsProvider.notifier)
              .applyConversation(control, 'chat');
          await tester.pumpAndSettle();
          _expectPreset(tester, 'acp:run', 'financing');

          // Changing the authoritative avatar updates both existing messages
          // and the execution preview without rewriting the message history.
          (container.read(agentsProvider.notifier) as _Inventory).replace(
            'research',
          );
          await tester.pumpAndSettle();
          _expectPreset(tester, 'ready', 'research');
          _expectPreset(tester, 'acp:run', 'research');
          if (group) _expectPreset(tester, 'other', 'legal');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
