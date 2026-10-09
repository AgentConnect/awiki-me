import 'dart:async';

import 'package:awiki_me/src/app/app_appearance.dart';
import 'package:awiki_me/src/data/services/appearance_preference_service.dart';
import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'appearance survives a service restart and system clears the override',
    () async {
      final store = _Store();
      final service = AppearancePreferenceService(storage: store);
      expect(await service.load(), AppAppearance.system);
      for (final appearance in [AppAppearance.dark, AppAppearance.light]) {
        await service.save(appearance);
        expect(
          await AppearancePreferenceService(storage: store).load(),
          appearance,
        );
      }
      await service.save(AppAppearance.system);
      expect(store.values, isEmpty);
      store.values[AppearancePreferenceService.key] = 'unknown';
      expect(await service.load(), AppAppearance.system);
      store.fail = true;
      expect(await service.load(), AppAppearance.system);
    },
  );

  test(
    'failed save leaves selected appearance intact and permits retry',
    () async {
      final store = _Store()..fail = true;
      final controller = AppAppearanceController(
        AppAppearance.system,
        AppearancePreferenceService(storage: store),
      );
      addTearDown(controller.dispose);
      final observed = <AppAppearance>[];
      controller.addListener(observed.add);
      await expectLater(
        controller.setAppearance(AppAppearance.dark),
        throwsStateError,
      );
      expect(observed.last, AppAppearance.system);
      store.fail = false;
      await controller.setAppearance(AppAppearance.light);
      expect(observed.last, AppAppearance.light);
      expect(store.values[AppearancePreferenceService.key], 'light');
    },
  );

  test(
    'rapid choices serialize writes and preserve the final selection',
    () async {
      final gate = Completer<void>();
      final store = _Store()..firstWrite = gate.future;
      final controller = AppAppearanceController(
        AppAppearance.system,
        AppearancePreferenceService(storage: store),
      );
      addTearDown(controller.dispose);
      final observed = <AppAppearance>[];
      controller.addListener(observed.add);
      final first = controller.setAppearance(AppAppearance.dark);
      final last = controller.setAppearance(AppAppearance.light);
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, 1);
      gate.complete();
      await Future.wait([first, last]);
      expect(observed.last, AppAppearance.light);
      expect(store.values[AppearancePreferenceService.key], 'light');
    },
  );

  test('explicit appearance ignores system brightness', () {
    for (final brightness in Brightness.values) {
      expect(
        resolveAppBrightness(AppAppearance.system, brightness),
        brightness,
      );
      expect(
        resolveAppBrightness(AppAppearance.light, brightness),
        Brightness.light,
      );
      expect(
        resolveAppBrightness(AppAppearance.dark, brightness),
        Brightness.dark,
      );
    }
  });
}

class _Store implements AppKeyValueStore {
  final values = <String, String>{};
  bool fail = false;
  int writes = 0;
  Future<void>? firstWrite;

  @override
  Future<String?> read({required String key}) async {
    if (fail) throw StateError('unavailable');
    return values[key];
  }

  @override
  Future<void> delete({required String key}) async {
    if (fail) throw StateError('unavailable');
    values.remove(key);
  }

  @override
  Future<void> write({required String key, required String value}) async {
    writes++;
    if (writes == 1) await firstWrite;
    if (fail) throw StateError('unavailable');
    values[key] = value;
  }
}
