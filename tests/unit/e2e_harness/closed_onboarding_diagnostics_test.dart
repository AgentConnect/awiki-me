import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../e2e/closed_onboarding_diagnostics.dart';

void main() {
  test('network diagnostics retain exact fixed native failure categories', () {
    expect(closedNetworkFailureReason(null), 'none');
    expect(
      closedNetworkFailureReason('network_connect_timeout'),
      'network_connect_timeout',
    );
    expect(
      closedNetworkFailureReason(
        'transport unavailable: transport unavailable: network_tls_handshake',
      ),
      'network_tls_handshake',
    );
    expect(
      closedNetworkFailureReason('transport unavailable: direct_connect'),
      'direct_connect',
    );
  });

  test('network diagnostics reject appended private error detail', () {
    const private = 'PRIVATE_PHONE_OTP_PIN_TOKEN';
    for (final message in [
      private,
      'network_connect_timeout $private',
      'transport unavailable: network_tls_handshake: $private',
      'transport unavailable: https://test.example/$private',
      'network_private_category',
    ]) {
      final reason = closedNetworkFailureReason(message);
      expect(reason, 'unrecognized');
      expect(reason, isNot(contains(private)));
    }
  });

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
