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

  AwikiBreakpoint breakpointFor(Size size) {
    return AwikiBreakpoints.fromSize(size);
  }

  bool shouldLockPortrait({
    required Size size,
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
    return breakpointFor(size) == AwikiBreakpoint.compact;
  }

  Future<void> apply({
    required Size size,
    required TargetPlatform platform,
  }) async {
    if (shouldLockPortrait(size: size, platform: platform)) {
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
  Size? _lastSize;
  TargetPlatform? _lastPlatform;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? AppOrientationController();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final platform = defaultTargetPlatform;
    if (_lastSize != size || _lastPlatform != platform) {
      _lastSize = size;
      _lastPlatform = platform;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.apply(size: size, platform: platform);
      });
    }
    return widget.child;
  }
}
