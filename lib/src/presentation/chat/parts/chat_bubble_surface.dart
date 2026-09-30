part of '../chat_page.dart';

/// Converts a reference-design pixel value into layout units, so the chat
/// matches the reference exactly at the default display scale.
double _chatDesignPx(AwikiResponsiveInfo responsive, double px) =>
    responsive.displayScaled(px / AwikiDisplayScale.layoutBaseline);

/// Reference `--bubble-r` / `--bubble-tail`: 18/6 on desktop, 20/8 on phone.
/// The sharper tail corner sits at the top on the sender's side.
BorderRadius _chatBubbleRadius(
  AwikiResponsiveInfo responsive, {
  required bool isMine,
  required bool macStyle,
}) {
  final round = Radius.circular(_chatDesignPx(responsive, macStyle ? 18 : 20));
  final tail = Radius.circular(_chatDesignPx(responsive, macStyle ? 6 : 8));
  return BorderRadius.only(
    topLeft: isMine ? round : tail,
    topRight: isMine ? tail : round,
    bottomLeft: round,
    bottomRight: round,
  );
}

/// Shared geometry for messages and ACP previews; contains no message identity.
class _MessageBubbleSurface extends StatelessWidget {
  const _MessageBubbleSurface({
    super.key,
    required this.maxWidth,
    required this.isMine,
    required this.hasAttachment,
    required this.macStyle,
    required this.child,
  });
  final double maxWidth;
  final bool isMine;
  final bool hasAttachment;
  final bool macStyle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    // Reference `.file`: attachments sit on the surface with a hairline
    // border instead of a tinted bubble.
    final color = hasAttachment
        ? theme.surface
        : isMine
        ? theme.outgoingMessage
        : theme.incomingMessage;
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: hasAttachment
          ? EdgeInsets.fromLTRB(
              _chatDesignPx(responsive, 10),
              _chatDesignPx(responsive, 10),
              _chatDesignPx(responsive, 14),
              _chatDesignPx(responsive, 10),
            )
          : EdgeInsets.symmetric(
              horizontal: _chatDesignPx(responsive, 14),
              vertical: _chatDesignPx(responsive, 9),
            ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: _chatBubbleRadius(
          responsive,
          isMine: isMine,
          macStyle: macStyle,
        ),
        border: hasAttachment ? Border.all(color: theme.border) : null,
      ),
      child: child,
    );
  }
}
