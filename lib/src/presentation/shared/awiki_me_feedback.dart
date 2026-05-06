import 'package:flutter/cupertino.dart';

import 'awiki_me_design.dart';

class AwikiMeToast {
  static void show(
    BuildContext context,
    String message, {
    bool danger = false,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return;
    }
    final entry = OverlayEntry(
      builder: (context) {
        final theme = context.awikiTheme;
        return Positioned(
          left: 20,
          right: 20,
          bottom: 110,
          child: IgnorePointer(
            child: SafeArea(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: danger
                        ? theme.danger.withValues(alpha: 0.9)
                        : theme.title.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.surface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(entry);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (entry.mounted) {
        entry.remove();
      }
    });
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
                      fontWeight: FontWeight.w600,
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
