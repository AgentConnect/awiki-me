import 'package:flutter/services.dart';

/// Allowlist of replaceable App state affected by the v10.3.1 namespace bug.
/// This policy must never be applied to Scope secrets, credentials or vaults.
bool canRecoverAndroidLegacyAppState(String key, Object error) {
  if (!_isReplaceableAppState(key) || error is! PlatformException) return false;
  if (error.code != 'Exception encountered') return false;
  final message = error.message ?? '';
  final details = error.details;
  return message.contains('BAD_DECRYPT') ||
      (details is String &&
          details.contains('javax.crypto.BadPaddingException'));
}

bool _isReplaceableAppState(String key) {
  if (key == 'awiki_me_locale_mode' || key == 'awiki_me_display_scale_v1') {
    return true;
  }
  return _activeIdentity.hasMatch(key) ||
      _updateCache.hasMatch(key) ||
      _updateSource.hasMatch(key) ||
      _otpCooldown.hasMatch(key);
}

final _activeIdentity = RegExp(
  r'^awiki_me_active_identity\.scope\.[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _updateCache = RegExp(
  r'^awiki_me_update_[0-9a-f]{64}_[0-9a-f]{64}_awiki-me_stable_(checked_at|manifest|policy_v1|cached_at|prompted_version|ignored_version)$',
);
final _updateSource = RegExp(
  r'^awiki_me_update_[0-9a-f]{64}_preferred_official_source$',
);
// This is a local retry hint; the server remains authoritative for OTP limits.
final _otpCooldown = RegExp(
  r'^sms_otp_cooldown_retry_at_v1(\.handle_recovery)?\.[A-Za-z0-9_-]+$',
);
