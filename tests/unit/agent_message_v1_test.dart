import 'package:awiki_me/src/domain/entities/agent/agent_message_v1.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/agent_message_presentation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

const message = AgentMessageV1(
  eventId: 'evt_task_20260811_001',
  taskName: '生产发布检查',
  kind: AgentMessageKind.alert,
  level: AgentMessageLevel.urgent,
  summary: '需要处理',
  detail: '请查看任务详情。',
  action: AgentMessageAction.openConversation,
);

void main() {
  test('is a typed Core projection, not a raw JSON decoder', () {
    expect(AgentMessageV1.schema, 'awiki.agent.message.v1');
    expect(message.taskName, '生产发布检查');
    expect(message.kind, AgentMessageKind.alert);
    expect(message.level, AgentMessageLevel.urgent);
  });

  test('projection equality and nullable ChatMessage copy are value-safe', () {
    const projection = ValidAgentMessageProjection(message);
    expect(projection, const ValidAgentMessageProjection(message));
    expect(
      const InvalidAgentMessageProjection(),
      const InvalidAgentMessageProjection(),
    );
    final chatMessage = ChatMessage(
      localId: 'message-1',
      threadId: 'conversation-1',
      senderDid: 'did:agent',
      content: '',
      originalType: 'agent_message',
      payloadJson: '{"legacy":true}',
      createdAt: DateTime.utc(2026, 8, 11),
      isMine: false,
      sendState: MessageSendState.sent,
      agentMessage: projection,
    );

    expect(chatMessage.copyWith().agentMessage, projection);
    final cleared = chatMessage.copyWith(agentMessage: null, payloadJson: null);
    expect(cleared.agentMessage, isNull);
    expect(cleared.payloadJson, isNull);
  });

  test('urgent is downgraded unless every local gate passes', () {
    final policy = AgentMessagePresentationPolicy();
    final now = DateTime.utc(2026, 8, 11, 12);
    expect(
      policy
          .decide(
            message: message,
            acceptedAt: now,
            now: now,
            senderIsTrustedForCurrentSession: false,
            urgentOptIn: true,
            conversationMuted: false,
            platformPresentationAllowed: true,
            isForeground: true,
            senderUrgentCountInWindow: 0,
            accountUrgentCountInWindow: 0,
          )
          .disposition,
      AgentMessagePresentationDisposition.silentForeground,
    );
    expect(
      policy
          .decide(
            message: message,
            acceptedAt: now,
            now: now,
            senderIsTrustedForCurrentSession: true,
            urgentOptIn: true,
            conversationMuted: false,
            platformPresentationAllowed: true,
            isForeground: true,
            senderUrgentCountInWindow: 0,
            accountUrgentCountInWindow: 0,
          )
          .disposition,
      AgentMessagePresentationDisposition.urgentForegroundCallout,
    );
  });

  test('mute suppresses every App-owned presentation', () {
    final now = DateTime.utc(2026, 8, 11, 12);
    expect(
      AgentMessagePresentationPolicy()
          .decide(
            message: message,
            acceptedAt: now,
            now: now,
            senderIsTrustedForCurrentSession: true,
            urgentOptIn: true,
            conversationMuted: true,
            platformPresentationAllowed: true,
            isForeground: false,
            senderUrgentCountInWindow: 0,
            accountUrgentCountInWindow: 0,
          )
          .disposition,
      AgentMessagePresentationDisposition.suppressedMuted,
    );
  });

  test(
    'permission denial never falls back to a native normal notification',
    () {
      final now = DateTime.utc(2026, 8, 11, 12);
      expect(
        AgentMessagePresentationPolicy()
            .decide(
              message: message,
              acceptedAt: now,
              now: now,
              senderIsTrustedForCurrentSession: true,
              urgentOptIn: true,
              conversationMuted: false,
              platformPresentationAllowed: false,
              isForeground: false,
              senderUrgentCountInWindow: 0,
              accountUrgentCountInWindow: 0,
            )
            .disposition,
        AgentMessagePresentationDisposition.suppressedPermission,
      );
    },
  );

  test('future or missing accepted time always downgrades urgent', () {
    final now = DateTime.utc(2026, 8, 11, 12);
    final policy = AgentMessagePresentationPolicy();
    for (final acceptedAt in <DateTime?>[
      null,
      now.add(const Duration(seconds: 1)),
    ]) {
      final decision = policy.decide(
        message: message,
        acceptedAt: acceptedAt,
        now: now,
        senderIsTrustedForCurrentSession: true,
        urgentOptIn: true,
        conversationMuted: false,
        platformPresentationAllowed: true,
        isForeground: true,
        senderUrgentCountInWindow: 0,
        accountUrgentCountInWindow: 0,
      );
      expect(
        decision.disposition,
        AgentMessagePresentationDisposition.silentForeground,
      );
      expect(decision.shouldUseUrgentCue, isFalse);
    }
  });

  test('non-alert urgent can cue but never becomes a full-screen callout', () {
    final now = DateTime.utc(2026, 8, 11, 12);
    const urgentTask = AgentMessageV1(
      eventId: 'evt_task_20260811_002',
      taskName: 'Release readiness',
      kind: AgentMessageKind.taskResult,
      level: AgentMessageLevel.urgent,
      summary: 'Task needs attention',
      detail: null,
      action: AgentMessageAction.openConversation,
    );
    final decision = AgentMessagePresentationPolicy().decide(
      message: urgentTask,
      acceptedAt: now,
      now: now,
      senderIsTrustedForCurrentSession: true,
      urgentOptIn: true,
      conversationMuted: false,
      platformPresentationAllowed: true,
      isForeground: true,
      senderUrgentCountInWindow: 0,
      accountUrgentCountInWindow: 0,
    );
    expect(
      decision.disposition,
      AgentMessagePresentationDisposition.urgentForegroundCue,
    );
    expect(decision.isUrgentCall, isFalse);
    expect(decision.shouldUseUrgentCue, isTrue);
  });
}
