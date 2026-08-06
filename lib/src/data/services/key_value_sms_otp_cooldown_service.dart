// [INPUT]: Tenant storage scope and the shared preference key-value store.
// [OUTPUT]: Strict UTC retry-boundary persistence without phone, Handle, or OTP data.
// [POS]: Data adapter for SmsOtpCooldownService.

import 'dart:convert';

import '../../application/sms_otp_cooldown_service.dart';
import 'app_key_value_store.dart';

class KeyValueSmsOtpCooldownService implements SmsOtpCooldownService {
  KeyValueSmsOtpCooldownService({
    required AppKeyValueStore storage,
    required String scopeId,
  }) : _storage = storage,
       _key = _storageKey(scopeId);

  final AppKeyValueStore _storage;
  final String _key;

  @override
  Future<DateTime?> loadRetryAt() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null || !parsed.isUtc || !raw.endsWith('Z')) {
      await _storage.delete(key: _key);
      return null;
    }
    return parsed;
  }

  @override
  Future<void> saveRetryAt(DateTime retryAt) {
    return _storage.write(key: _key, value: retryAt.toUtc().toIso8601String());
  }

  @override
  Future<void> clearRetryAt() => _storage.delete(key: _key);
}

String _storageKey(String scopeId) {
  final normalized = scopeId.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(scopeId, 'scopeId', 'must not be empty');
  }
  final encoded = base64Url.encode(utf8.encode(normalized)).replaceAll('=', '');
  return 'sms_otp_cooldown_retry_at_v1.$encoded';
}
