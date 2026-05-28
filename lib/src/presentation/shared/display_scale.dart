import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AwikiDisplayScale {
  const AwikiDisplayScale._();

  static const double min = 0.76;
  static const double max = 1.32;
  static const double step = 0.06;
  static const double normal = 1.0;

  static double normalize(double value) {
    return value.clamp(min, max).toDouble();
  }
}

class DisplayScaleController extends StateNotifier<double> {
  DisplayScaleController() : super(AwikiDisplayScale.normal);

  void increase() {
    state = AwikiDisplayScale.normalize(state + AwikiDisplayScale.step);
  }

  void decrease() {
    state = AwikiDisplayScale.normalize(state - AwikiDisplayScale.step);
  }

  void reset() {
    state = AwikiDisplayScale.normal;
  }
}

final displayScaleProvider =
    StateNotifierProvider<DisplayScaleController, double>(
      (ref) => DisplayScaleController(),
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
