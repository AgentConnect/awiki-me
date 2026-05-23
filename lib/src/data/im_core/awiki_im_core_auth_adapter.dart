import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/app_auth_state.dart';
import '../../application/ports/auth_core_port.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreAuthAdapter implements AuthCorePort {
  AwikiImCoreAuthAdapter({required AwikiImCoreRuntime runtime})
    : _runtime = runtime;

  final AwikiImCoreRuntime _runtime;

  @override
  Future<AppAuthState> status() async {
    final status = await (await _runtime.currentClient()).auth.status();
    return AppAuthState(
      authenticated: status.authenticated,
      subject: status.subject,
      expiresAt: _tryParseDateTime(status.expiresAt),
      needsRefresh: status.needsRefresh,
      warnings: status.warnings,
    );
  }

  @override
  Future<AppAuthState> login() async {
    final bundle = await (await _runtime.currentClient()).auth.login();
    return AppAuthState(
      authenticated: true,
      subject: bundle.subject,
      expiresAt: _tryParseDateTime(bundle.expiresAt),
      warnings: bundle.refreshed ? const <String>[] : const <String>[],
    );
  }

  @override
  Future<AppAuthState> ensureSession() async {
    final bundle = await (await _runtime.currentClient()).auth.ensureSession(
      core.AuthScope.messaging,
    );
    return AppAuthState(
      authenticated: true,
      subject: bundle.subject,
      expiresAt: _tryParseDateTime(bundle.expiresAt),
    );
  }

  @override
  Future<AppAuthState> refreshSession() async {
    final update = await (await _runtime.currentClient()).auth.refreshSession();
    return AppAuthState(
      authenticated: true,
      subject: update.subject,
      expiresAt: _tryParseDateTime(update.newExpiresAt),
      needsRefresh: !update.refreshed,
    );
  }
}

DateTime? _tryParseDateTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}
