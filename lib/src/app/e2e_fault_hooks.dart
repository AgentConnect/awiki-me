// Product-side seam only. The controller and file protocol live in tests/e2e.
import 'package:flutter/foundation.dart';

const bool e2eFaultHooksEnabled = !kReleaseMode && bool.fromEnvironment('AWIKI_E2E');

bool allowE2eFaultHooks({required bool releaseMode, required bool e2eEnabled}) =>
    !releaseMode && e2eEnabled;

enum E2eFaultCheckpoint { recoveryBeforeProductReset, identityAfterProductDelete }
enum E2eFaultAction { continueExecution, stopBeforeReset, throwError }
typedef E2eFaultHandler = Future<E2eFaultAction> Function(E2eFaultCheckpoint checkpoint);

// No production configuration/file access and no controller registration in Release.
class E2eFaultHookRegistry {
  E2eFaultHookRegistry({required this.enabled});
  final bool enabled;
  E2eFaultHandler? _handler;
  void install(E2eFaultHandler handler) {
    if (!enabled) throw StateError('E2E fault hooks are disabled.');
    if (_handler != null) throw StateError('E2E fault controller already installed.');
    _handler = handler;
  }
  void clear() => _handler = null;
  Future<E2eFaultAction> hit(E2eFaultCheckpoint checkpoint) async {
    if (!enabled) return E2eFaultAction.continueExecution;
    return await _handler?.call(checkpoint) ?? E2eFaultAction.continueExecution;
  }
}

final e2eFaultHooks = E2eFaultHookRegistry(enabled: e2eFaultHooksEnabled);
