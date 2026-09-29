part of '../chat_page.dart';

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
    const shadows = [
      BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
    ];
    final color = hasAttachment
        ? theme.surface
        : isMine
        ? theme.outgoingMessage
        : theme.incomingMessage;
    // Desktop follows the reference's flat 6-unit bubble; phone uses the
    // rounder bubble whose sender-side top corner tightens toward the avatar.
    final large = responsive.displayScaled(macStyle ? 6 : 20);
    final small = responsive.displayScaled(macStyle ? 6 : 8);
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: EdgeInsets.symmetric(
        horizontal: responsive.displayScaled(macStyle ? 12 : 14),
        vertical: responsive.displayScaled(macStyle ? 8 : 9),
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isMine ? large : small),
          topRight: Radius.circular(isMine ? small : large),
          bottomLeft: Radius.circular(large),
          bottomRight: Radius.circular(large),
        ),
        border: hasAttachment ? Border.all(color: theme.border) : null,
        boxShadow: hasAttachment ? shadows : null,
      ),
      child: child,
    );
  }
}
