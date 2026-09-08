import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/session_provider.dart';

/// Session orchestration only. Core owns recovery authorization and durable state.
abstract interface class HandleRecoverySession {
  Future<void> pauseCurrent();
  Future<void> restorePrevious();
  Future<bool> activate(String ownerIdentityId);
}

class RuntimeHandleRecoverySession implements HandleRecoverySession {
  RuntimeHandleRecoverySession(this._ref);
  final Ref _ref;
  String? _previousIdentity;

  @override
  Future<void> pauseCurrent() async {
    final session = _ref.read(sessionProvider).session;
    if (session == null) return;
    _previousIdentity = session.localIdentityId;
    await _ref.read(appRuntimeProvider.notifier).prepareIdentityActivation();
  }

  @override
  Future<void> restorePrevious() async {
    final previous = _previousIdentity;
    _previousIdentity = null;
    if (previous == null || previous.isEmpty) return;
    final activated = await _ref
        .read(appRuntimeProvider.notifier)
        .loginWithLocalCredentialAndConfirm(previous);
    if (!activated) throw StateError('previous_session_activation_failed');
  }

  @override
  Future<bool> activate(String ownerIdentityId) {
    _previousIdentity = null;
    return _ref
        .read(appRuntimeProvider.notifier)
        .loginWithLocalCredentialAndConfirm(ownerIdentityId);
  }
}
