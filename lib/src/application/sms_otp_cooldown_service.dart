// [INPUT]: One tenant- and purpose-scoped SMS resend boundary.
// [OUTPUT]: Persistent, non-secret UTC cooldown state per verification purpose.
// [POS]: Application persistence port; UI timers and OTP targets stay outside.

enum SmsOtpCooldownPurpose { registrationAndJoin, handleRecovery }

abstract interface class SmsOtpCooldownService {
  Future<DateTime?> loadRetryAt({
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  });

  Future<void> saveRetryAt(
    DateTime retryAt, {
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  });

  Future<void> clearRetryAt({
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  });
}

class NoopSmsOtpCooldownService implements SmsOtpCooldownService {
  const NoopSmsOtpCooldownService();

  @override
  Future<DateTime?> loadRetryAt({
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  }) async => null;

  @override
  Future<void> saveRetryAt(
    DateTime retryAt, {
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  }) async {}

  @override
  Future<void> clearRetryAt({
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  }) async {}
}
