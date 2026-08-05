import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../application/desktop_startup_presentation_service.dart';

class DesktopStartupReadyBoundary extends StatefulWidget {
  const DesktopStartupReadyBoundary({
    super.key,
    required this.presentationService,
    required this.child,
  });

  final DesktopStartupPresentationService presentationService;
  final Widget child;

  @override
  State<DesktopStartupReadyBoundary> createState() =>
      _DesktopStartupReadyBoundaryState();
}

class _DesktopStartupReadyBoundaryState
    extends State<DesktopStartupReadyBoundary> {
  bool _presentationScheduled = false;

  @override
  Widget build(BuildContext context) {
    if (!_presentationScheduled) {
      _presentationScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          widget.presentationService.presentReadyContent().catchError(
            (Object _, StackTrace __) {},
          ),
        );
      });
    }
    return widget.child;
  }
}
