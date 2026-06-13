import 'package:awiki_me/src/app/app_orientation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppOrientationController', () {
    test('小宽度移动端锁定竖屏', () {
      final controller = AppOrientationController();

      expect(
        controller.shouldLockPortrait(width: 390, platform: TargetPlatform.iOS),
        isTrue,
      );
      expect(
        controller.shouldLockPortrait(
          width: 500,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
    });

    test('Pad 与桌面端不锁方向', () {
      final controller = AppOrientationController();

      expect(
        controller.shouldLockPortrait(width: 820, platform: TargetPlatform.iOS),
        isFalse,
      );
      expect(
        controller.shouldLockPortrait(
          width: 1280,
          platform: TargetPlatform.macOS,
        ),
        isFalse,
      );
    });

    test('apply 在小宽度移动端下发竖屏限制', () async {
      List<DeviceOrientation>? applied;
      final controller = AppOrientationController(
        setPreferredOrientations: (orientations) async {
          applied = orientations;
        },
      );

      await controller.apply(width: 400, platform: TargetPlatform.android);

      expect(applied, const <DeviceOrientation>[DeviceOrientation.portraitUp]);
    });

    test('apply 在宽屏或桌面下清除方向限制', () async {
      List<DeviceOrientation>? applied;
      final controller = AppOrientationController(
        setPreferredOrientations: (orientations) async {
          applied = orientations;
        },
      );

      await controller.apply(width: 900, platform: TargetPlatform.iOS);
      expect(applied, isEmpty);

      await controller.apply(width: 1280, platform: TargetPlatform.macOS);
      expect(applied, isEmpty);
    });
  });
}
