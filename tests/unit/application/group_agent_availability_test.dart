import 'package:awiki_me/src/application/agent/group_agent_availability.dart';
import 'package:awiki_me/src/domain/entities/agent/acp_task.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_availability.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final message = ChatMessage(
    localId: 'local',
    remoteId: 'remote',
    threadId: 'legacy-route',
    conversationId: 'canonical-group',
    groupId: 'did:group',
    senderDid: 'did:owner',
    content: '@Agent help',
    createdAt: DateTime.utc(2026),
    isMine: true,
    sendState: MessageSendState.sent,
    mentions: const [
      ChatMessageMention(
        id: 'm1',
        surface: '@Agent',
        start: 0,
        end: 6,
        target: ChatMentionTargetDraft.member(
          kind: ChatMentionTargetKind.agent,
          did: 'did:agent',
        ),
        role: ChatMentionRole.addressee,
      ),
    ],
  );
  const availability = {
    'did:agent': AgentAvailability(
      agentDid: 'did:agent',
      state: AgentAvailabilityState.unavailable,
      version: '2',
      reason: 'agent_deleted',
    ),
  };

  test(
    'only sender gets a lifecycle notice and no text or result is rewritten',
    () {
      expect(
        unavailableGroupAgentNotices(
          message: message,
          conversationId: 'canonical-group',
          availability: availability,
          tasks: [],
        ),
        {'did:agent': '@Agent'},
      );
      expect(
        unavailableGroupAgentNotices(
          message: ChatMessage(
            localId: message.localId,
            threadId: message.threadId,
            conversationId: message.conversationId,
            groupId: message.groupId,
            senderDid: message.senderDid,
            content: message.content,
            createdAt: message.createdAt,
            isMine: false,
            sendState: message.sendState,
            mentions: message.mentions,
          ),
          conversationId: 'canonical-group',
          availability: availability,
          tasks: [],
        ),
        isEmpty,
      );
      expect(
        explicitGroupAgentTargets(
          message.copyWith(sendState: MessageSendState.sending),
        ),
        isEmpty,
      );
      expect(
        explicitGroupAgentTargets(message.copyWith(content: 'edited')),
        isEmpty,
      );
      expect(message.content, '@Agent help');
    },
  );

  test(
    'terminal or rejected task suppresses notice only for exact source and route',
    () {
      AcpTask task(String source, String route) => AcpTask.parse({
        'schema': 'awiki.acp.task.v1',
        'revision': 1,
        'session_key': 'session',
        'run_id': 'run',
        'source_message_id': source,
        'agent_did': 'did:agent',
        'group': true,
        'state': 'finished',
      }, localConversationId: route)!;
      expect(
        unavailableGroupAgentNotices(
          message: message,
          conversationId: 'canonical-group',
          availability: availability,
          tasks: [task('remote', 'canonical-group')],
        ),
        isEmpty,
      );
      expect(
        unavailableGroupAgentNotices(
          message: message,
          conversationId: 'canonical-group',
          availability: availability,
          tasks: [
            task('other', 'canonical-group'),
            task('remote', 'another-group'),
          ],
        ),
        isNotEmpty,
      );
      expect(
        unavailableGroupAgentNotices(
          message: message,
          conversationId: 'canonical-group',
          availability: availability,
          tasks: [],
          rejectedAgentDids: {'did:agent'},
        ),
        isEmpty,
      );
      expect(
        unavailableGroupAgentNotices(
          message: message,
          conversationId: 'another-group',
          availability: availability,
          tasks: [],
        ),
        isEmpty,
      );
    },
  );

  test(
    'broadcast and cc do not trigger lifecycle checks or repeated notices',
    () {
      for (final selector in [
        ChatMentionSelector.all,
        ChatMentionSelector.agents,
      ]) {
        final broadcast = message.copyWith(
          content: '@all help',
          mentions: [
            ChatMessageMention(
              id: 'all',
              surface: '@all',
              start: 0,
              end: 4,
              target: ChatMentionTargetDraft.groupSelector(selector),
              role: ChatMentionRole.addressee,
            ),
          ],
        );
        expect(explicitGroupAgentTargets(broadcast), isEmpty);
      }
      expect(
        explicitGroupAgentTargets(
          message.copyWith(
            mentions: const [
              ChatMessageMention(
                id: 'cc',
                surface: '@Agent',
                start: 0,
                end: 6,
                target: ChatMentionTargetDraft.member(
                  kind: ChatMentionTargetKind.agent,
                  did: 'did:agent',
                ),
                role: ChatMentionRole.cc,
              ),
            ],
          ),
        ),
        isEmpty,
      );
    },
  );
}
