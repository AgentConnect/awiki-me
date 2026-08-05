import 'package:awiki_me/src/application/display_scale_preference_service.dart';
import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:awiki_me/src/data/services/key_value_display_scale_preference_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('display scale defaults to 100% and normalizes stored values', () async {
    final storage = _MemoryStore();
    final service = KeyValueDisplayScalePreferenceService(storage: storage);

    expect(await service.loadScale(), AwikiDisplayScale.normal);

    storage.values['awiki_me_display_scale_v1'] = '1.16';
    expect(await service.loadScale(), 1.2);

    storage.values['awiki_me_display_scale_v1'] = 'invalid';
    expect(await service.loadScale(), AwikiDisplayScale.normal);
  });

  test(
    'display scale persists presets and removes the default value',
    () async {
      final storage = _MemoryStore();
      final service = KeyValueDisplayScalePreferenceService(storage: storage);

      await service.saveScale(1.26);
      expect(storage.values['awiki_me_display_scale_v1'], '1.3');

      await service.saveScale(1);
      expect(storage.values, isEmpty);
    },
  );

  test('display scale read failures never block app startup', () async {
    final service = KeyValueDisplayScalePreferenceService(
      storage: _ThrowingStore(),
    );

    expect(await service.loadScale(), AwikiDisplayScale.normal);
  });
}

final class _MemoryStore implements AppKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

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
