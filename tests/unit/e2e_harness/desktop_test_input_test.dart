import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/flutter/support/desktop_test_input.dart';

class _Inspector implements HitTestDispatcher {
  int events = 0;

  @override
  void dispatchEvent(PointerEvent event, HitTestResult result) {
    events += 1;
  }
}

void main() {
  final binding = LiveTestWidgetsFlutterBinding();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;

  testWidgets('physical window drag cannot poison automated UI taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps += 1,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final original = binding.deviceEventDispatcher;
    final inspector = _Inspector();
    binding.deviceEventDispatcher = inspector;
    final restore = disableDesktopPointerInspector(binding);
    try {
      // The operating system may consume mouse-up while dragging the native
      // title bar. This sequence reproduced the live inspector assertion.
      binding.handlePointerEvent(
        const PointerDownEvent(
          pointer: 0,
          kind: PointerDeviceKind.mouse,
          position: Offset(10, 10),
        ),
      );
      binding.handlePointerEvent(
        const PointerHoverEvent(
          pointer: 0,
          kind: PointerDeviceKind.mouse,
          position: Offset(20, 20),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(inspector.events, 0);
      expect(taps, 0);
      await tester.tapAt(const Offset(40, 40));
      await tester.pump();
      expect(taps, 1);
    } finally {
      restore();
    }
    expect(binding.deviceEventDispatcher, same(inspector));
    binding.handlePointerEvent(
      const PointerHoverEvent(
        pointer: 0,
        kind: PointerDeviceKind.mouse,
        position: Offset(25, 25),
      ),
    );
    expect(inspector.events, 1);
    binding.deviceEventDispatcher = original;
  });
}
