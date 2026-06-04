import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../presentation/shared/responsive_layout.dart';

typedef PreferredOrientationsSetter =
    Future<void> Function(List<DeviceOrientation> orientations);

class AppOrientationController {
  AppOrientationController({
    PreferredOrientationsSetter? setPreferredOrientations,
  }) : _setPreferredOrientations =
           setPreferredOrientations ?? SystemChrome.setPreferredOrientations;

  final PreferredOrientationsSetter _setPreferredOrientations;

  AwikiBreakpoint breakpointForWidth(double width) {
    return AwikiBreakpoints.fromWidth(width);
  }

  bool shouldLockPortrait({
    required double width,
    required TargetPlatform platform,
  }) {
    if (kIsWeb) {
      return false;
    }
    final isMobilePlatform =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    if (!isMobilePlatform) {
      return false;
    }
    return breakpointForWidth(width) == AwikiBreakpoint.phone;
  }

  Future<void> apply({
    required double width,
    required TargetPlatform platform,
  }) async {
    if (shouldLockPortrait(width: width, platform: platform)) {
      await _setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);
      return;
    }
    await _setPreferredOrientations(const <DeviceOrientation>[]);
  }
}

class AppOrientationScope extends StatefulWidget {
  const AppOrientationScope({super.key, required this.child, this.controller});

  final Widget child;
  final AppOrientationController? controller;

  @override
  State<AppOrientationScope> createState() => _AppOrientationScopeState();
}

class _AppOrientationScopeState extends State<AppOrientationScope> {
  late final AppOrientationController _controller;
  double? _lastWidth;
  TargetPlatform? _lastPlatform;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? AppOrientationController();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final platform = defaultTargetPlatform;
    if (_lastWidth != width || _lastPlatform != platform) {
      _lastWidth = width;
      _lastPlatform = platform;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.apply(width: width, platform: platform);
      });
    }
    return widget.child;
  }
}
