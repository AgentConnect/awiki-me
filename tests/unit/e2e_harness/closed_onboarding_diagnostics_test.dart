import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../e2e/closed_onboarding_diagnostics.dart';

void main() {
  test(
    'read warning diagnostics distinguish a queued predecessor from failure',
    () {
      expect(
        recoveryReadWarningCategories([
          'Read watermark is queued behind an in-flight predecessor',
          'Remote read-state mark-read failed: service error 503: PRIVATE_BODY',
          'Invalid read-state ACK: PRIVATE_BODY',
        ]),
        ['invalid_remote_ack', 'predecessor_in_flight', 'remote_read_failed'],
      );
      expect(
        recoveryReadHttpStatuses([
          'Remote read-state mark-read failed: service error 503: PRIVATE_BODY',
          'service error 409 (PRIVATE_CODE): PRIVATE_BODY',
          'service error 654321: PRIVATE_BODY',
        ]),
        [409, 503],
      );
      expect(
        recoveryReadServiceCodes([
          'Invalid read-state ACK: service error (READ_STATE_INVALID_ACK): PRIVATE_BODY',
          'service error (PRIVATE_CODE): PRIVATE_BODY',
        ]),
        ['READ_STATE_INVALID_ACK'],
      );
    },
  );

  test(
    'diagnostic summaries never pass arbitrary warning/code/feedback text',
    () {
      const private = 'PRIVATE_PHONE_OTP_PIN_TOKEN_IDENTIFIER';
      final summary = jsonEncode({
        'warnings': recoveryReadWarningCategories([
          private,
          'Failed to commit read-state ACK: $private',
        ]),
        'statuses': recoveryReadHttpStatuses([private]),
        'serviceCodes': recoveryReadServiceCodes([
          'service error ($private): $private',
        ]),
        'code': closedOnboardingFailureCode(private),
        'feedback': closedOnboardingFeedbackId(private),
      });
      expect(summary, isNot(contains(private)));
      expect(recoveryReadWarningCategories([private]), ['unrecognized']);
      expect(closedOnboardingFailureCode(null), 'none');
      expect(closedOnboardingFeedbackId(null), 'none');
    },
  );

  test('only fixed onboarding codes cross the diagnostic boundary', () {
    expect(closedOnboardingFailureCode('request_timeout'), 'request_timeout');
    expect(
      closedOnboardingFailureCode('identity.local_registry_conflict'),
      'identity.local_registry_conflict',
    );
    expect(
      closedOnboardingFeedbackId('registrationContinuityChanged'),
      'registrationContinuityChanged',
    );
    expect(
      closedOnboardingFeedbackId('arbitrary.safe.looking.token'),
      'unrecognized',
    );
  });
}
