import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/appearance_preference_service.dart';

enum AppAppearance { system, light, dark }

Brightness resolveAppBrightness(AppAppearance appearance, Brightness system) =>
    switch (appearance) {
      AppAppearance.system => system,
      AppAppearance.light => Brightness.light,
      AppAppearance.dark => Brightness.dark,
    };

final initialAppAppearanceProvider = Provider((ref) => AppAppearance.system);
final appearancePreferenceServiceProvider = Provider(
  (ref) => const AppearancePreferenceService(),
);
final appAppearanceProvider =
    StateNotifierProvider<AppAppearanceController, AppAppearance>(
      (ref) => AppAppearanceController(
        ref.watch(initialAppAppearanceProvider),
        ref.watch(appearancePreferenceServiceProvider),
      ),
    );

class AppAppearanceController extends StateNotifier<AppAppearance> {
  AppAppearanceController(super.state, this._preferences);

  final AppearancePreferenceService _preferences;
  Future<void> _pending = Future<void>.value();

  Future<void> setAppearance(AppAppearance appearance) {
    final operation = _pending.then((_) async {
      await _preferences.save(appearance);
      if (mounted) state = appearance;
    });
    // Preserve write order while allowing a later choice to retry a failed save.
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
