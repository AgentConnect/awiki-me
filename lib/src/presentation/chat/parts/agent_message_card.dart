import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../domain/entities/agent/agent_message_v1.dart';

/// Callout Strip (the selected direction) for a validated Agent projection.
/// This widget never receives sender, route, title, URL, or attachment values
/// from the wire contract.
class AgentMessageCard extends StatelessWidget {
  const AgentMessageCard({
    super.key,
    required this.message,
    required this.copy,
    required this.onOpenConversation,
    this.timeLabel,
  });

  final AgentMessageV1 message;
  final AgentMessageCardCopy copy;
  final VoidCallback? onOpenConversation;
  final String? timeLabel;

  @override
  Widget build(BuildContext context) {
    final urgent = message.level == AgentMessageLevel.urgent;
    final urgentCall = urgent && message.kind == AgentMessageKind.alert;
    final accent = switch (message.kind) {
      AgentMessageKind.message => const Color(0xFF2778B8),
      AgentMessageKind.taskResult => const Color(0xFF00A85A),
      AgentMessageKind.alert => const Color(0xFFE79A00),
    };
    final surface = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: Color(0xFFFFFFFF),
        darkColor: Color(0xFF202124),
      ),
      context,
    );
    final titleColor = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: Color(0xFF242424),
        darkColor: Color(0xFFF4F4F4),
      ),
      context,
    );
    final secondaryColor = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: Color(0xFF888888),
        darkColor: Color(0xFFB7B7B7),
      ),
      context,
    );
    final label = urgentCall
        ? copy.urgentCall
        : switch (message.kind) {
            AgentMessageKind.message => copy.message,
            AgentMessageKind.taskResult => copy.taskResult,
            AgentMessageKind.alert => copy.alert,
          };
    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(
          color: urgentCall ? const Color(0xFFED3333) : const Color(0xFFDADADA),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (urgentCall)
            Container(
              color: const Color(0xFF151612),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const ExcludeSemantics(
                    child: Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      color: Color(0xFFFFB400),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFB400),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (!urgentCall)
                  Row(
                    children: <Widget>[
                      ExcludeSemantics(
                        child: Icon(
                          message.kind == AgentMessageKind.taskResult
                              ? CupertinoIcons.check_mark_circled
                              : message.kind == AgentMessageKind.alert
                              ? CupertinoIcons.exclamationmark_triangle
                              : CupertinoIcons.bell,
                          color: accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (urgent)
                        Text(
                          copy.urgent,
                          key: const Key('agent-message-urgent-badge'),
                          style: const TextStyle(
                            color: Color(0xFFED3333),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                if (!urgentCall) const SizedBox(height: 9),
                Text(
                  message.taskName,
                  key: const Key('agent-message-task-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: urgentCall ? const Color(0xFFFFB400) : accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (urgentCall) ...<Widget>[
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0xFFED3333),
                          shape: BoxShape.circle,
                        ),
                        child: const ExcludeSemantics(
                          child: Icon(
                            CupertinoIcons.exclamationmark,
                            color: Color(0xFFFFFFFF),
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        message.summary,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                if (message.detail case final detail?) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    detail,
                    style: TextStyle(color: secondaryColor, height: 1.35),
                  ),
                ],
                if (timeLabel case final value?) ...<Widget>[
                  const SizedBox(height: 11),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      value,
                      style: TextStyle(color: secondaryColor, fontSize: 14),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: onOpenConversation != null,
      label: '$label: ${message.taskName}: ${message.summary}',
      child: onOpenConversation == null
          ? KeyedSubtree(
              key: Key('agent-message-card:${message.eventId}'),
              child: card,
            )
          : GestureDetector(
              key: Key('agent-message-card:${message.eventId}'),
              onTap: onOpenConversation,
              child: card,
            ),
    );
  }
}

/// A WeChat-call-like App-internal foreground state, not an Android full-screen
/// intent or VoIP surface. It deliberately cannot wake the screen, bypass DND,
/// or invoke native notification APIs.
class AgentUrgentCalloutOverlay extends StatelessWidget {
  const AgentUrgentCalloutOverlay({
    super.key,
    required this.message,
    required this.senderLabel,
    required this.copy,
    required this.metaLabel,
    required this.onIgnore,
    required this.onAct,
  });

  final AgentMessageV1 message;
  final String senderLabel;
  final AgentUrgentCalloutCopy copy;
  final String metaLabel;
  final VoidCallback onIgnore;
  final VoidCallback onAct;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ColoredBox(
      key: const Key('agent-urgent-callout-overlay'),
      color: const Color(0xFF161713),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = (constraints.maxHeight / 844).clamp(0.82, 1.05);
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 14 * scale, 24, 28 * scale),
                  child: Column(
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: CupertinoButton(
                          key: const Key('agent-urgent-back'),
                          padding: EdgeInsets.zero,
                          onPressed: onIgnore,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(
                                CupertinoIcons.chevron_left,
                                color: Color(0xFFF1E8D7),
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                copy.back,
                                style: const TextStyle(
                                  color: Color(0xFFF1E8D7),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 28 * scale),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const ExcludeSemantics(
                            child: Icon(
                              CupertinoIcons.exclamationmark_triangle,
                              color: Color(0xFFFFB400),
                              size: 27,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              copy.urgentCall,
                              style: const TextStyle(
                                color: Color(0xFFFFB400),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6 * scale),
                      _AgentIdentityRings(
                        senderLabel: senderLabel,
                        trustedLabel: copy.trustedAgent,
                        scale: scale,
                      ),
                      SizedBox(height: 10 * scale),
                      Text(
                        message.taskName,
                        key: const Key('agent-urgent-task-name'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFFB400),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                      SizedBox(height: 8 * scale),
                      Text(
                        message.summary,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFF8F7F2),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      SizedBox(height: 15 * scale),
                      if (message.detail case final detail?) ...<Widget>[
                        Text(
                          detail,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFE5DED2),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        SizedBox(height: 6 * scale),
                      ],
                      Text(
                        copy.notAVoipNotice,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFB8AD9A),
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                      SizedBox(height: 13 * scale),
                      Text(
                        metaLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFB8AD9A),
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 25 * scale),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 270),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFFFB400)),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const ExcludeSemantics(
                              child: Icon(
                                CupertinoIcons.bell,
                                color: Color(0xFFFFB400),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                copy.cueStops,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFD8CBB7),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 48 * scale),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _UrgentRoundAction(
                            buttonKey: const Key('agent-urgent-ignore'),
                            color: const Color(0xFFE93434),
                            icon: CupertinoIcons.xmark,
                            label: copy.ignore,
                            onPressed: onIgnore,
                          ),
                          _UrgentRoundAction(
                            buttonKey: const Key('agent-urgent-act'),
                            color: const Color(0xFF098DDA),
                            icon: CupertinoIcons.check_mark,
                            label: copy.act,
                            onPressed: onAct,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _AgentIdentityRings extends StatelessWidget {
  const _AgentIdentityRings({
    required this.senderLabel,
    required this.trustedLabel,
    required this.scale,
  });

  final String senderLabel;
  final String trustedLabel;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final normalized = senderLabel.trim();
    final initial = normalized.isEmpty
        ? 'A'
        : String.fromCharCode(normalized.runes.first);
    return SizedBox(
      height: 284 * scale,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final diameter = math.min(constraints.maxWidth, 300 * scale);
          return Stack(
            alignment: Alignment.topCenter,
            children: <Widget>[
              SizedBox(
                width: diameter,
                height: diameter,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Container(
                      width: diameter,
                      height: diameter,
                      decoration: const BoxDecoration(
                        color: Color(0x0DFFB400),
                        shape: BoxShape.circle,
                      ),
                    ),
                    for (final factor in const <double>[0.90, 0.76, 0.62, 0.48])
                      Container(
                        width: diameter * factor,
                        height: diameter * factor,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0x52B88100),
                            width: 1,
                          ),
                        ),
                      ),
                    Container(
                      width: diameter * 0.32,
                      height: diameter * 0.32,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF3E2C5),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Color(0xFF6B4300),
                          fontSize: 43,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 24 * scale,
                left: 0,
                right: 0,
                child: Text(
                  normalized.isEmpty ? 'Agent' : normalized,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Positioned(
                bottom: 2 * scale,
                left: 0,
                right: 0,
                child: Text(
                  trustedLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFD8C6A7),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _UrgentRoundAction extends StatelessWidget {
  const _UrgentRoundAction({
    required this.buttonKey,
    required this.color,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Key buttonKey;
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CupertinoButton(
          key: buttonKey,
          padding: EdgeInsets.zero,
          color: color,
          borderRadius: BorderRadius.circular(36),
          onPressed: onPressed,
          child: SizedBox(
            width: 72,
            height: 72,
            child: Icon(icon, color: const Color(0xFFFFFFFF), size: 34),
          ),
        ),
        const SizedBox(height: 11),
        Text(
          label,
          style: const TextStyle(color: Color(0xFFF1E8D7), fontSize: 14),
        ),
      ],
    );
  }
}

final class AgentMessageCardCopy {
  const AgentMessageCardCopy({
    required this.message,
    required this.taskResult,
    required this.alert,
    required this.urgent,
    required this.urgentCall,
  });

  final String message;
  final String taskResult;
  final String alert;
  final String urgent;
  final String urgentCall;
}

final class AgentUrgentCalloutCopy {
  const AgentUrgentCalloutCopy({
    required this.urgentCall,
    required this.back,
    required this.trustedAgent,
    required this.notAVoipNotice,
    required this.cueStops,
    required this.ignore,
    required this.act,
  });

  final String urgentCall;
  final String back;
  final String trustedAgent;
  final String notAVoipNotice;
  final String cueStops;
  final String ignore;
  final String act;
}
