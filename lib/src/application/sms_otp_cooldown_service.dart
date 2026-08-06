// [INPUT]: One tenant-scoped SMS resend boundary.
// [OUTPUT]: Persistent, non-secret UTC cooldown state.
// [POS]: Application persistence port; UI timers and OTP targets stay outside.

abstract interface class SmsOtpCooldownService {
  Future<DateTime?> loadRetryAt();

  Future<void> saveRetryAt(DateTime retryAt);

  Future<void> clearRetryAt();
}

class NoopSmsOtpCooldownService implements SmsOtpCooldownService {
  const NoopSmsOtpCooldownService();

  @override
  Future<DateTime?> loadRetryAt() async => null;

  @override
  Future<void> saveRetryAt(DateTime retryAt) async {}

  @override
  Future<void> clearRetryAt() async {}
}
