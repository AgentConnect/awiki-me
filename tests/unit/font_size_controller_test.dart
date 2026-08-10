import 'package:awiki_me/src/application/font_size_preference_service.dart';
import 'package:awiki_me/src/presentation/shared/font_size.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'controller normalizes the 12 through 22 range and persists in order',
    () async {
      final preferences = _RecordingPreferences();
      final controller = FontSizeController(
        initialFontSize: 13.6,
        preferenceService: preferences,
      );
      addTearDown(controller.dispose);

      expect(controller.fontSize, AwikiFontSize.standard);
      controller.setFontSize(17.7);
      controller.setFontSize(100);
      controller.setFontSize(11);
      await Future<void>.delayed(Duration.zero);

      expect(controller.fontSize, AwikiFontSize.min);
      expect(preferences.saved, <double>[18, 22, 12]);
    },
  );

  test('controller reset returns to the 14 px standard', () async {
    final preferences = _RecordingPreferences();
    final controller = FontSizeController(
      initialFontSize: 18,
      preferenceService: preferences,
    );
    addTearDown(controller.dispose);

    controller.reset();
    await Future<void>.delayed(Duration.zero);

    expect(controller.fontSize, AwikiFontSize.standard);
    expect(preferences.saved, <double>[AwikiFontSize.standard]);
  });
}

final class _RecordingPreferences implements FontSizePreferenceService {
  final List<double> saved = <double>[];

  @override
  Future<double> loadFontSize() async => AwikiFontSize.standard;

  @override
  Future<void> saveFontSize(double fontSize) async => saved.add(fontSize);
}
