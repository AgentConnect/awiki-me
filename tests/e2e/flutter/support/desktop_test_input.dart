import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Automated taps still use the test event source. Disable only the live
/// finders inspector: a native window drag can consume a physical mouse-up,
/// leaving its pointer tracked when the next physical hover arrives.
VoidCallback disableDesktopPointerInspector(TestWidgetsFlutterBinding binding) {
  if (binding is! LiveTestWidgetsFlutterBinding) return () {};
  final previous = binding.deviceEventDispatcher;
  binding.deviceEventDispatcher = null;
  return () => binding.deviceEventDispatcher = previous;
}
