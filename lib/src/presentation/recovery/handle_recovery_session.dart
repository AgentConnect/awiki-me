import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/session_provider.dart';

final handleRecoverySessionProvider = Provider<HandleRecoverySession>(
  (ref) => RuntimeHandleRecoverySession(ref),
);

/// App session effects only; Core remains the recovery state authority.
abstract interface class HandleRecoverySession {
  String? get currentIdentityId;
  Future<void> pauseCurrent({required bool Function() isCurrent});
  Future<bool> restorePrevious(
    String identityId, {
    required bool Function() isCurrent,
  });
}

class RuntimeHandleRecoverySession implements HandleRecoverySession {
  RuntimeHandleRecoverySession(this._ref);
  final Ref _ref;

  @override
  String? get currentIdentityId =>
      _ref.read(sessionProvider).session?.localIdentityId;

  @override
  Future<void> pauseCurrent({required bool Function() isCurrent}) async {
    if (!isCurrent() || _ref.read(sessionProvider).session == null) return;
    await _ref
        .read(appRuntimeProvider.notifier)
        .prepareIdentityActivation(isCurrent: isCurrent);
  }

  @override
  Future<bool> restorePrevious(
    String identityId, {
    required bool Function() isCurrent,
  }) => _ref
      .read(appRuntimeProvider.notifier)
      .loginWithLocalCredentialAndConfirm(identityId, isCurrent: isCurrent);
}
