import 'package:awiki_me/src/application/font_size_preference_service.dart';
import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:awiki_me/src/data/services/key_value_font_size_preference_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'font size defaults to 14 and clamps stored values to 12 through 22',
    () async {
      final storage = _MemoryStore();
      final service = KeyValueFontSizePreferenceService(storage: storage);

      expect(await service.loadFontSize(), AwikiFontSize.standard);

      storage.values['awiki_me_font_size_v1'] = '17.6';
      expect(await service.loadFontSize(), 18);

      storage.values['awiki_me_font_size_v1'] = '99';
      expect(await service.loadFontSize(), AwikiFontSize.max);

      storage.values['awiki_me_font_size_v1'] = 'invalid';
      expect(await service.loadFontSize(), AwikiFontSize.standard);
    },
  );

  test(
    'font size persists integer values and removes the standard value',
    () async {
      final storage = _MemoryStore();
      final service = KeyValueFontSizePreferenceService(storage: storage);

      await service.saveFontSize(16.4);
      expect(storage.values['awiki_me_font_size_v1'], '16');

      await service.saveFontSize(14);
      expect(storage.values, isEmpty);
    },
  );

  test('font size read failures never block app startup', () async {
    final service = KeyValueFontSizePreferenceService(
      storage: _ThrowingStore(),
    );

    expect(await service.loadFontSize(), AwikiFontSize.standard);
  });
}

final class _MemoryStore implements AppKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete({required String key}) async => values.remove(key);

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

final class _ThrowingStore implements AppKeyValueStore {
  @override
  Future<void> delete({required String key}) async {}

  @override
  Future<String?> read({required String key}) {
    throw StateError('preferences_unavailable');
  }

  @override
  Future<void> write({required String key, required String value}) async {}
}
