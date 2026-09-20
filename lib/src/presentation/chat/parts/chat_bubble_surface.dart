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
    final padding = responsive.displayScaled(13);
    final tail = macStyle ? 0.0 : responsive.displayScaled(6);
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: EdgeInsets.fromLTRB(
        padding + (isMine ? 0 : tail),
        responsive.displayScaled(9),
        padding + (isMine ? tail : 0),
        responsive.displayScaled(9),
      ),
      decoration: macStyle
          ? BoxDecoration(
              color: hasAttachment
                  ? theme.surface
                  : isMine
                  ? theme.outgoingMessage
                  : theme.incomingMessage,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(
                  responsive.displayScaled(isMine ? 13 : 4),
                ),
                topRight: Radius.circular(
                  responsive.displayScaled(isMine ? 4 : 13),
                ),
                bottomLeft: Radius.circular(responsive.displayScaled(13)),
                bottomRight: Radius.circular(responsive.displayScaled(13)),
              ),
              boxShadow: hasAttachment ? shadows : null,
            )
          : ShapeDecoration(
              color: hasAttachment
                  ? theme.surface
                  : isMine
                  ? theme.outgoingMessage
                  : theme.surface,
              shape: _ChatBubbleShapeBorder(
                isMine: isMine,
                radius: responsive.displayScaled(16),
                tailExtent: tail,
                side: BorderSide(
                  color: isMine
                      ? AwikiMePalette.brandAccent.withValues(alpha: 0.28)
                      : theme.border,
                ),
              ),
              shadows: hasAttachment ? shadows : null,
            ),
      child: child,
    );
  }
}
