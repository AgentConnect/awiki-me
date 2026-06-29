import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea, SelectionContainer;
import 'package:flutter/services.dart';

import '../../app/app_router.dart';
import 'awiki_me_design.dart';
import 'responsive_layout.dart';

const _awikiMeInfoToastDuration = Duration(seconds: 2);
const _awikiMeDangerToastDuration = Duration(seconds: 8);

class AwikiMeToast {
  static void show(
    BuildContext context,
    String message, {
    bool danger = false,
    String? detail,
    Duration? duration,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return;
    }
    final displayDuration =
        duration ??
        (danger ? _awikiMeDangerToastDuration : _awikiMeInfoToastDuration);
    final entry = OverlayEntry(
      builder: (context) {
        final theme = context.awikiTheme;
        final content = SafeArea(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: danger
                    ? theme.danger.withValues(alpha: 0.9)
                    : theme.title.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(14),
              ),
              child: _ToastContent(
                message: message,
                detail: detail,
                danger: danger,
              ),
            ),
          ),
        );
        return Positioned(
          left: 20,
          right: 20,
          bottom: 110,
          child: danger
              ? SelectionArea(child: content)
              : IgnorePointer(child: content),
        );
      },
    );
    overlay.insert(entry);
    Future<void>.delayed(displayDuration, () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }
}

class _ToastContent extends StatelessWidget {
  const _ToastContent({
    required this.message,
    required this.detail,
    required this.danger,
  });

  final String message;
  final String? detail;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final detailText = detail?.trim();
    if (!danger || detailText == null || detailText.isEmpty) {
      return Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: theme.surface,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.surface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SelectionContainer.disabled(
          child: CupertinoButton(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            color: theme.surface.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
            onPressed: () => showAwikiMeErrorDetailDialog(
              context,
              message: message,
              detail: detailText,
            ),
            child: Text(
              '详情',
              style: TextStyle(
                color: theme.surface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showAwikiMeErrorDetailDialog(
  BuildContext context, {
  required String message,
  required String detail,
}) {
  return AppNavigator.showDialog<void>(
    context,
    (dialogContext) =>
        _AwikiMeErrorDetailDialog(message: message, detail: detail),
  );
}

class _AwikiMeErrorDetailDialog extends StatefulWidget {
  const _AwikiMeErrorDetailDialog({
    required this.message,
    required this.detail,
  });

  final String message;
  final String detail;

  @override
  State<_AwikiMeErrorDetailDialog> createState() =>
      _AwikiMeErrorDetailDialogState();
}

class _AwikiMeErrorDetailDialogState extends State<_AwikiMeErrorDetailDialog> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return CupertinoPopupSurface(
      isSurfacePainted: false,
      child: Container(
        width: responsive.isPhone ? double.infinity : 520,
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: responsive.isPhone ? 520 : 620,
        ),
        margin: EdgeInsets.symmetric(
          horizontal: responsive.isPhone ? 16 : 0,
          vertical: 24,
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: theme.overlayShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    '错误详情',
                    style: TextStyle(
                      color: theme.title,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                CupertinoButton(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.all(4),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Icon(
                    CupertinoIcons.xmark,
                    color: theme.secondaryText,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.message,
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.subtleSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.border),
                ),
                child: SingleChildScrollView(
                  child: SelectionArea(
                    child: Text(
                      widget.detail,
                      style: TextStyle(
                        color: theme.title,
                        fontSize: 12,
                        height: 1.45,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                CupertinoButton(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    '关闭',
                    style: TextStyle(
                      color: theme.secondaryText,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  minimumSize: Size.zero,
                  color: theme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  borderRadius: BorderRadius.circular(9),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: widget.detail));
                    if (mounted) {
                      setState(() {
                        _copied = true;
                      });
                    }
                  },
                  child: Text(
                    _copied ? '已复制' : '复制详情',
                    style: TextStyle(
                      color: theme.surface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AwikiMeErrorNotice extends StatelessWidget {
  const AwikiMeErrorNotice({
    super.key,
    required this.message,
    this.center = false,
    this.compact = false,
    this.trailing,
  });

  final String message;
  final bool center;
  final bool compact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? responsive.spacing(10) : 12),
      decoration: BoxDecoration(
        color: theme.dangerContainer,
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: theme.danger.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: center
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: AwikiMeErrorText(
              message: message,
              textAlign: center ? TextAlign.center : TextAlign.start,
              compact: compact,
            ),
          ),
          if (trailing != null) ...<Widget>[
            SizedBox(width: responsive.spacing(10)),
            SelectionContainer.disabled(child: trailing!),
          ],
        ],
      ),
    );
  }
}

class AwikiMeErrorText extends StatelessWidget {
  const AwikiMeErrorText({
    super.key,
    required this.message,
    this.textAlign,
    this.compact = false,
    this.maxLines,
  });

  final String message;
  final TextAlign? textAlign;
  final bool compact;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final text = Text(
      message,
      maxLines: maxLines,
      textAlign: textAlign,
      style: TextStyle(
        color: theme.danger,
        fontSize: compact ? responsive.metaSm : responsive.bodySm,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
    );
    if (SelectionContainer.maybeOf(context) != null) {
      return text;
    }
    return SelectionArea(child: text);
  }
}

class AwikiMePersistentToast extends StatelessWidget {
  const AwikiMePersistentToast({
    super.key,
    required this.message,
    this.danger = false,
    this.showSpinner = false,
    this.bottom = 110,
  });

  final String message;
  final bool danger;
  final bool showSpinner;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final content = SafeArea(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: danger
                ? theme.danger.withValues(alpha: 0.9)
                : theme.title.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (showSpinner) ...<Widget>[
                CupertinoActivityIndicator(color: theme.surface, radius: 8),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.surface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Positioned(
      left: 20,
      right: 20,
      bottom: bottom,
      child: danger
          ? SelectionArea(child: content)
          : IgnorePointer(child: content),
    );
  }
}

class AwikiMeLoadingMask extends StatelessWidget {
  const AwikiMeLoadingMask({super.key, this.label = '', this.opacity = 0.18});

  final String label;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: CupertinoColors.black.withValues(alpha: opacity),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: theme.surface.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(AwikiMeRadii.lg),
                boxShadow: theme.overlayShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CupertinoActivityIndicator(radius: 12),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    style: TextStyle(
                      color: theme.title,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
