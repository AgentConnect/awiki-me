import 'package:awiki_me/src/app/app_orientation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppOrientationController', () {
    test('compact 移动端按宽度或高度锁定竖屏', () {
      final controller = AppOrientationController();

      expect(
        controller.shouldLockPortrait(
          size: const Size(719, 600),
          platform: TargetPlatform.iOS,
        ),
        isTrue,
      );
      expect(
        controller.shouldLockPortrait(
          size: const Size(720, 599),
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
    });

    test('720x600 移动端解除方向限制', () {
      final controller = AppOrientationController();

      expect(
        controller.shouldLockPortrait(
          size: const Size(720, 600),
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
      expect(
        controller.shouldLockPortrait(
          size: const Size(1280, 800),
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
    });

    test('桌面平台即使是 compact 也不锁方向', () {
      final controller = AppOrientationController();

      for (final platform in <TargetPlatform>[
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          controller.shouldLockPortrait(
            size: const Size(719, 599),
            platform: platform,
          ),
          isFalse,
          reason: '$platform',
        );
      }
    });

    test('apply 在 compact 移动端下发竖屏限制', () async {
      List<DeviceOrientation>? applied;
      final controller = AppOrientationController(
        setPreferredOrientations: (orientations) async {
          applied = orientations;
        },
      );

      await controller.apply(
        size: const Size(900, 599),
        platform: TargetPlatform.android,
      );

      expect(applied, const <DeviceOrientation>[DeviceOrientation.portraitUp]);
    });

    test('apply 在 expanded 移动端或桌面端清除方向限制', () async {
      List<DeviceOrientation>? applied;
      final controller = AppOrientationController(
        setPreferredOrientations: (orientations) async {
          applied = orientations;
        },
      );

      await controller.apply(
        size: const Size(900, 600),
        platform: TargetPlatform.iOS,
      );
      expect(applied, isEmpty);

      await controller.apply(
        size: const Size(390, 599),
        platform: TargetPlatform.macOS,
      );
      expect(applied, isEmpty);
    });

    testWidgets('AppOrientationScope 会响应只有高度发生的档位变化', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final applied = <List<DeviceOrientation>>[];
        final controller = AppOrientationController(
          setPreferredOrientations: (orientations) async {
            applied.add(orientations);
          },
        );

        Future<void> pumpAt(Size size) {
          return tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(size: size),
              child: AppOrientationScope(
                key: const Key('orientation-scope'),
                controller: controller,
                child: const Directionality(
                  textDirection: TextDirection.ltr,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          );
        }

        await pumpAt(const Size(900, 600));
        await tester.pump();
        expect(applied.last, isEmpty);

        await pumpAt(const Size(900, 599));
        await tester.pump();

        expect(applied.last, const <DeviceOrientation>[
          DeviceOrientation.portraitUp,
        ]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
