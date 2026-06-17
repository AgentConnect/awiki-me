part of '../conversation_workspace_page.dart';

class _MacProfileCard extends StatelessWidget {
  const _MacProfileCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF17213A),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _MacPanelShell extends StatelessWidget {
  const _MacPanelShell({
    required this.title,
    required this.onClose,
    required this.child,
    this.closeIcon,
    this.closeButtonKey,
    this.closeSemanticLabel = '关闭身份卡',
    this.closeButtonLeading = false,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;
  final IconData? closeIcon;
  final Key? closeButtonKey;
  final String closeSemanticLabel;
  final bool closeButtonLeading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFF8FAFD)),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Container(
              height: 60,
              padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE5EAF2))),
              ),
              child: Row(
                children: <Widget>[
                  if (closeButtonLeading) ...<Widget>[
                    _MacPanelIconButton(
                      key:
                          closeButtonKey ??
                          const Key('mac-side-panel-close-button'),
                      semanticLabel: closeSemanticLabel,
                      icon: closeIcon ?? CupertinoIcons.xmark,
                      onTap: onClose,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF101B32),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (!closeButtonLeading)
                    _MacPanelIconButton(
                      key:
                          closeButtonKey ??
                          const Key('mac-side-panel-close-button'),
                      semanticLabel: closeSemanticLabel,
                      icon: closeIcon ?? CupertinoIcons.xmark,
                      onTap: onClose,
                    ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _MacPanelIconButton extends StatelessWidget {
  const _MacPanelIconButton({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    this.isLoading = false,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final enabled = onTap != null && !isLoading;
    return AppIconButton(
      onPressed: isLoading ? null : onTap,
      semanticLabel: semanticLabel,
      tooltip: semanticLabel,
      isLoading: isLoading,
      size: responsive.displayScaled(32),
      backgroundColor: CupertinoColors.white,
      borderColor: const Color(0xFFDDE5F0),
      borderRadius: BorderRadius.circular(responsive.displayScaled(8)),
      child: Icon(
        icon,
        color: enabled ? const Color(0xFF34415C) : theme.tertiaryText,
        size: responsive.displayScaled(16),
      ),
    );
  }
}

class _MacProfilePill extends StatelessWidget {
  const _MacProfilePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF0B65F8),
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
