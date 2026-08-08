// [INPUT]: Tenant storage scope, verification purpose, and the shared key-value store.
// [OUTPUT]: Purpose-isolated UTC retry boundaries without phone, Handle, or OTP data.
// [POS]: Data adapter for SmsOtpCooldownService.

import 'dart:convert';

import '../../application/sms_otp_cooldown_service.dart';
import 'app_key_value_store.dart';

class KeyValueSmsOtpCooldownService implements SmsOtpCooldownService {
  KeyValueSmsOtpCooldownService({
    required AppKeyValueStore storage,
    required String scopeId,
  }) : _storage = storage,
       _scopeId = scopeId;

  final AppKeyValueStore _storage;
  final String _scopeId;

  @override
  Future<DateTime?> loadRetryAt({
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  }) async {
    final key = _storageKey(_scopeId, purpose);
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null || !parsed.isUtc || !raw.endsWith('Z')) {
      await _storage.delete(key: key);
      return null;
    }
    return parsed;
  }

  @override
  Future<void> saveRetryAt(
    DateTime retryAt, {
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  }) {
    return _storage.write(
      key: _storageKey(_scopeId, purpose),
      value: retryAt.toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> clearRetryAt({
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  }) => _storage.delete(key: _storageKey(_scopeId, purpose));
}

String _storageKey(String scopeId, SmsOtpCooldownPurpose purpose) {
  final normalized = scopeId.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(scopeId, 'scopeId', 'must not be empty');
  }
  final encoded = base64Url.encode(utf8.encode(normalized)).replaceAll('=', '');
  final purposeSegment = switch (purpose) {
    SmsOtpCooldownPurpose.registrationAndJoin => '',
    SmsOtpCooldownPurpose.handleRecovery => '.handle_recovery',
  };
  return 'sms_otp_cooldown_retry_at_v1$purposeSegment.$encoded';
}
