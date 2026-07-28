import 'package:flutter/cupertino.dart';

import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/formatters/localized_ui_formatters.dart';
import '../shared/responsive_layout.dart';
import 'agent_visual_status.dart';

class AgentStatusIndicatorOverlay extends StatelessWidget {
  const AgentStatusIndicatorOverlay({
    super.key,
    required this.status,
    required this.child,
    this.dotSize,
    this.inset = -1,
  });

  final AgentVisualStatus status;
  final Widget child;
  final double? dotSize;
  final double inset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        child,
        Positioned(
          right: inset,
          bottom: inset,
          child: AgentStatusDot(status: status, size: dotSize, showRing: true),
        ),
      ],
    );
  }
}

class AgentStatusDot extends StatelessWidget {
  const AgentStatusDot({
    super.key,
    required this.status,
    this.size,
    this.showRing = false,
  });

  final AgentVisualStatus status;
  final double? size;
  final bool showRing;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final size = this.size ?? responsive.displayScaled(9);
    final color = agentVisualStatusColor(status);
    return Semantics(
      label: localizeAgentVisualStatusSemantic(context.l10n, status),
      child: SizedBox(
        width: status.isProcessing ? size * 2.15 : size,
        height: status.isProcessing ? size * 2.15 : size,
        child: Center(
          child: status.isProcessing
              ? Container(
                  width: size * 2.05,
                  height: size * 2.05,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.32)),
                  ),
                  alignment: Alignment.center,
                  child: _SolidDot(color: color, size: size),
                )
              : _SolidDot(
                  color: color,
                  size: size,
                  borderColor: showRing ? CupertinoColors.white : null,
                ),
        ),
      ),
    );
  }
}

class AgentStatusPill extends StatelessWidget {
  const AgentStatusPill({super.key, required this.status});

  final AgentVisualStatus status;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final color = agentVisualStatusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.spacing(9),
        vertical: responsive.spacing(4),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _SolidDot(color: color, size: responsive.displayScaled(6)),
          SizedBox(width: responsive.spacing(5)),
          Text(
            localizeAgentVisualStatus(context.l10n, status),
            style: TextStyle(
              color: color,
              fontSize: responsive.metaSm,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SolidDot extends StatelessWidget {
  const _SolidDot({required this.color, required this.size, this.borderColor});

  final Color color;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: 1.5),
      ),
    );
  }
}

Color agentVisualStatusColor(AgentVisualStatus status) {
  return switch (status.kind) {
    AgentVisualStatusKind.processing => AwikiMeColors.primary,
    AgentVisualStatusKind.ready => AwikiMeColors.online,
    AgentVisualStatusKind.needsConfig ||
    AgentVisualStatusKind.needsUpgrade => AwikiMeColors.alert,
    AgentVisualStatusKind.failed => AwikiMeColors.danger,
    AgentVisualStatusKind.offline ||
    AgentVisualStatusKind.disabled ||
    AgentVisualStatusKind.unknown => AwikiMePalette.mutedNeutral,
  };
}
