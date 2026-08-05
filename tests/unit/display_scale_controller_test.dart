import 'package:awiki_me/src/application/display_scale_preference_service.dart';
import 'package:awiki_me/src/presentation/shared/display_scale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'controller uses stable presets and persists changes in order',
    () async {
      final preferences = _RecordingPreferences();
      final controller = DisplayScaleController(
        initialScale: 0.91,
        preferenceService: preferences,
      );
      addTearDown(controller.dispose);

      expect(controller.scale, 0.9);
      controller.increase();
      controller.increase();
      controller.decrease();
      controller.setScale(1.27);
      await Future<void>.delayed(Duration.zero);

      expect(controller.scale, 1.3);
      expect(preferences.saved, <double>[1, 1.1, 1, 1.3]);
    },
  );

  test('controller reset returns to the product 100% baseline', () async {
    final preferences = _RecordingPreferences();
    final controller = DisplayScaleController(
      initialScale: 1.2,
      preferenceService: preferences,
    );
    addTearDown(controller.dispose);

    controller.reset();
    await Future<void>.delayed(Duration.zero);

    expect(controller.scale, AwikiDisplayScale.normal);
    expect(preferences.saved, <double>[AwikiDisplayScale.normal]);
  });
}

final class _RecordingPreferences implements DisplayScalePreferenceService {
  final List<double> saved = <double>[];

  @override
  Future<double> loadScale() async => AwikiDisplayScale.normal;

  @override
  Future<void> saveScale(double scale) async {
    saved.add(scale);
  }
}
