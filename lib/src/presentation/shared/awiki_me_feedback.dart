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
      builder: (context) => Positioned(
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
                      ? const Color(0xE6B42318)
                      : CupertinoColors.black.withOpacity(0.82),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AwikiMeColors.surface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
  const AwikiMeLoadingMask({
    super.key,
    this.label = '加载中...',
    this.opacity = 0.18,
  });

  final String label;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: CupertinoColors.black.withOpacity(opacity),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 18,
              ),
              decoration: BoxDecoration(
                color: const Color(0xF7FFFFFF),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CupertinoActivityIndicator(radius: 12),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AwikiMeColors.title,
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
