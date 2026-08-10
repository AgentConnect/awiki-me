import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/display_scale_preference_service.dart';

export '../../application/display_scale_preference_service.dart'
    show AwikiDisplayScale;

class DisplayScaleController extends StateNotifier<double> {
  DisplayScaleController({
    double initialScale = AwikiDisplayScale.normal,
    DisplayScalePreferenceService preferenceService =
        const NoopDisplayScalePreferenceService(),
  }) : _preferenceService = preferenceService,
       super(AwikiDisplayScale.nearestLevel(initialScale));

  final DisplayScalePreferenceService _preferenceService;
  Future<void> _pendingSave = Future<void>.value();

  double get scale => state;

  void increase() {
    _setScale(AwikiDisplayScale.increase(state));
  }

  void decrease() {
    _setScale(AwikiDisplayScale.decrease(state));
  }

  void reset() {
    _setScale(AwikiDisplayScale.normal);
  }

  void setScale(double scale) {
    _setScale(AwikiDisplayScale.nearestLevel(scale));
  }

  void _setScale(double scale) {
    if (state == scale) return;
    state = scale;
    _pendingSave = _pendingSave
        .then((_) => _preferenceService.saveScale(scale))
        .catchError((Object _, StackTrace __) {});
  }
}

final initialDisplayScaleProvider = Provider<double>(
  (ref) => AwikiDisplayScale.normal,
);

final displayScalePreferenceServiceProvider =
    Provider<DisplayScalePreferenceService>(
      (ref) => const NoopDisplayScalePreferenceService(),
    );

final displayScaleProvider =
    StateNotifierProvider<DisplayScaleController, double>(
      (ref) => DisplayScaleController(
        initialScale: ref.watch(initialDisplayScaleProvider),
        preferenceService: ref.watch(displayScalePreferenceServiceProvider),
      ),
    );

class AwikiDisplayScaleScope extends InheritedWidget {
  const AwikiDisplayScaleScope({
    super.key,
    required this.scale,
    required super.child,
  });

  final double scale;

  static double of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AwikiDisplayScaleScope>();
    return scope?.scale ?? AwikiDisplayScale.normal;
  }

  @override
  bool updateShouldNotify(AwikiDisplayScaleScope oldWidget) {
    return oldWidget.scale != scale;
  }
}

class AwikiDisplayScaleTextMediaQuery extends StatelessWidget {
  const AwikiDisplayScaleTextMediaQuery({
    super.key,
    required this.scale,
    required this.child,
  });

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final systemTextScale = mediaQuery.textScaler.scale(1);
    final effectiveTextScale =
        systemTextScale * AwikiDisplayScale.effective(scale);
    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: TextScaler.linear(effectiveTextScale),
      ),
      child: child,
    );
  }
}
