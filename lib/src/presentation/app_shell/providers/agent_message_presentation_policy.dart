import '../../../domain/entities/agent/agent_message_v1.dart';

/// The sole App policy for structured Agent-message presentation.
///
/// It is intentionally independent of provider payloads: callers must supply
/// trusted local inventory, mute, preference and receipt facts after Core has
/// committed the message. A killed process therefore cannot safely promote an
/// urgent payload using this policy.
final class AgentMessagePresentationPolicy {
  AgentMessagePresentationPolicy({this.window = const Duration(minutes: 15)});

  final Duration window;

  AgentMessagePresentationDecision decide({
    required AgentMessageV1 message,
    required DateTime? acceptedAt,
    required DateTime now,
    required bool senderIsTrustedForCurrentSession,
    required bool urgentOptIn,
    required bool conversationMuted,
    required bool platformPresentationAllowed,
    required bool isForeground,
    required int senderUrgentCountInWindow,
    required int accountUrgentCountInWindow,
  }) {
    if (conversationMuted) {
      return const AgentMessagePresentationDecision.suppressedMuted();
    }
    if (!platformPresentationAllowed) {
      return const AgentMessagePresentationDecision.suppressedPermission();
    }
    final age = acceptedAt == null ? null : now.difference(acceptedAt);
    if (message.level == AgentMessageLevel.normal) {
      return AgentMessagePresentationDecision.normal(foreground: isForeground);
    }
    if (!senderIsTrustedForCurrentSession) {
      return const AgentMessagePresentationDecision.suppressedUntrusted();
    }
    if (!urgentOptIn) {
      return const AgentMessagePresentationDecision.suppressedOptOut();
    }
    if (age == null || age.isNegative || age > window) {
      return const AgentMessagePresentationDecision.suppressedExpired();
    }
    if (senderUrgentCountInWindow >= 3 || accountUrgentCountInWindow >= 6) {
      return const AgentMessagePresentationDecision.suppressedRateLimited();
    }
    return AgentMessagePresentationDecision.urgent(
      foreground: isForeground,
      isUrgentCall: message.kind == AgentMessageKind.alert,
    );
  }
}

enum AgentMessagePresentationDisposition {
  silentForeground,
  normalNotification,
  urgentForegroundCue,
  urgentForegroundCallout,
  urgentNotification,
  suppressedMuted,
  suppressedUntrusted,
  suppressedOptOut,
  suppressedExpired,
  suppressedRateLimited,
  suppressedPermission,
}

final class AgentMessagePresentationDecision {
  const AgentMessagePresentationDecision._(
    this.disposition, {
    this.isUrgentCall = false,
  });

  const AgentMessagePresentationDecision.suppressedMuted()
    : this._(AgentMessagePresentationDisposition.suppressedMuted);

  const AgentMessagePresentationDecision.suppressedPermission()
    : this._(AgentMessagePresentationDisposition.suppressedPermission);

  const AgentMessagePresentationDecision.suppressedUntrusted()
    : this._(AgentMessagePresentationDisposition.suppressedUntrusted);

  const AgentMessagePresentationDecision.suppressedOptOut()
    : this._(AgentMessagePresentationDisposition.suppressedOptOut);

  const AgentMessagePresentationDecision.suppressedExpired()
    : this._(AgentMessagePresentationDisposition.suppressedExpired);

  const AgentMessagePresentationDecision.suppressedRateLimited()
    : this._(AgentMessagePresentationDisposition.suppressedRateLimited);

  AgentMessagePresentationDecision.normal({required bool foreground})
    : this._(
        foreground
            ? AgentMessagePresentationDisposition.silentForeground
            : AgentMessagePresentationDisposition.normalNotification,
      );

  AgentMessagePresentationDecision.urgent({
    required bool foreground,
    required bool isUrgentCall,
  }) : this._(
         foreground
             ? isUrgentCall
                   ? AgentMessagePresentationDisposition.urgentForegroundCallout
                   : AgentMessagePresentationDisposition.urgentForegroundCue
             : AgentMessagePresentationDisposition.urgentNotification,
         isUrgentCall: isUrgentCall,
       );

  final AgentMessagePresentationDisposition disposition;
  final bool isUrgentCall;

  bool get shouldUseUrgentCue =>
      disposition == AgentMessagePresentationDisposition.urgentForegroundCue ||
      disposition ==
          AgentMessagePresentationDisposition.urgentForegroundCallout ||
      disposition == AgentMessagePresentationDisposition.urgentNotification;
}
