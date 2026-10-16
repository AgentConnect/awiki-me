import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/remote_multi_device_join_contract.dart';

void main() {
  group('protected fixed OTP contract', () {
    test('requires exactly six ASCII digits', () {
      expect(isSixDigitAsciiOtp('482917'), isTrue);
      expect(isSixDigitAsciiOtp('48291'), isFalse);
      expect(isSixDigitAsciiOtp('4829170'), isFalse);
      expect(isSixDigitAsciiOtp('１２３４５６'), isFalse);
      expect(isSixDigitAsciiOtp('48291a'), isFalse);
    });

    test('honors bounded Retry-After before repeating an OTP request', () {
      expect(remoteMultiDeviceOtpRetryDelay('42'), const Duration(seconds: 43));
      expect(remoteMultiDeviceOtpRetryDelay(null), const Duration(seconds: 61));
      expect(
        remoteMultiDeviceOtpRetryDelay('301'),
        const Duration(seconds: 61),
      );
    });
  });

  group('Handle Recovery phone-global OTP cooldown', () {
    test(
      'waits through the persisted retry boundary with one-second slack',
      () {
        final now = DateTime.utc(2026, 8, 8, 1);
        expect(
          remoteHandleRecoveryPhoneCooldownDelay(
            retryAt: now.add(const Duration(seconds: 60)),
            now: now,
          ),
          const Duration(seconds: 61),
        );
        expect(
          remoteHandleRecoveryPhoneCooldownDelay(
            retryAt: now.subtract(const Duration(seconds: 1)),
            now: now,
          ),
          Duration.zero,
        );
      },
    );

    test('rejects an unbounded server cooldown', () {
      final now = DateTime.utc(2026, 8, 8, 1);
      expect(
        () => remoteHandleRecoveryPhoneCooldownDelay(
          retryAt: now.add(const Duration(seconds: 91)),
          now: now,
        ),
        throwsFormatException,
      );
    });
  });

  group('Recovery prepare factor-exchange retry boundary', () {
    test('allows one 429 retry on the exact existing operation', () {
      expect(
        remoteRecoveryPrepareRetryDelay(
          code: 'service_error',
          statusCode: 429,
          retries: 0,
          expectedOperationId: 'operation-a',
          currentOperationId: 'operation-a',
        ),
        const Duration(seconds: 301),
      );
    });
    test('rejects other failures, retries, and operation replacement', () {
      for (final row in [
        ('transport_error', 429, 0, 'operation-a', 'operation-a'),
        ('service_error', 401, 0, 'operation-a', 'operation-a'),
        ('service_error', 503, 0, 'operation-a', 'operation-a'),
        ('service_error', null, 0, 'operation-a', 'operation-a'),
        (null, 429, 0, 'operation-a', 'operation-a'),
        ('service_error', 429, 1, 'operation-a', 'operation-a'),
        ('service_error', 429, -1, 'operation-a', 'operation-a'),
        ('service_error', 429, 0, '', ''),
        ('service_error', 429, 0, 'operation-a', null),
        ('service_error', 429, 0, 'operation-a', 'operation-b'),
      ]) {
        expect(
          remoteRecoveryPrepareRetryDelay(
            code: row.$1,
            statusCode: row.$2,
            retries: row.$3,
            expectedOperationId: row.$4,
            currentOperationId: row.$5,
          ),
          isNull,
        );
      }
    });
  });

  group('remote foreground CLI Join SAS prompts', () {
    test(
      'recognizes the joining-device poll prompt only at its TTY boundary',
      () {
        expect(
          remoteMultiDeviceCliPollSas(
            utf8.encode("This device's one-time SAS: 482917\r\n"),
          ),
          '482917',
        );
        expect(
          remoteMultiDeviceCliPollSas(
            utf8.encode("This device's one-time SAS: 48291"),
          ),
          isNull,
        );
        expect(
          remoteMultiDeviceCliPollSas(
            utf8.encode("This device's one-time SAS: 4829179\r\n"),
          ),
          isNull,
        );
        expect(
          remoteMultiDeviceCliPollSas(
            utf8.encode('{"remote_state":"response_verified","sas":"482917"}'),
          ),
          isNull,
        );
      },
    );

    test('recognizes only the exact production prompts', () {
      final transcript = utf8.encode(
        'Compare this one-time SAS with the new device: 482917\r\n'
        'Type the same 6-digit SAS to continue: '
        'Type APPROVE to join and configure identity management on this device: ',
      );

      expect(remoteMultiDeviceCliApprovalSas(transcript), '482917');
      expect(remoteMultiDeviceCliRequestsSasInput(transcript), isTrue);
      expect(remoteMultiDeviceCliRequestsApproval(transcript), isTrue);
      expect(
        remoteMultiDeviceCliRequestsApproval(
          transcript,
          managementAllowed: false,
        ),
        isFalse,
      );
      final messageOnly = utf8.encode(
        'Type APPROVE to join for messaging only (no root key or management permission): ',
      );
      expect(remoteMultiDeviceCliRequestsApproval(messageOnly), isFalse);
      expect(
        remoteMultiDeviceCliRequestsApproval(
          messageOnly,
          managementAllowed: false,
        ),
        isTrue,
      );
    });

    test('waits for a complete ASCII SAS and rejects prompt drift', () {
      expect(
        remoteMultiDeviceCliApprovalSas(
          utf8.encode('Compare this one-time SAS with the new device: 48291'),
        ),
        isNull,
      );
      expect(
        remoteMultiDeviceCliApprovalSas(
          utf8.encode('Compare this one-time SAS with the new device: 48291a'),
        ),
        isNull,
      );
      expect(
        remoteMultiDeviceCliApprovalSas(
          utf8.encode(
            'Compare this one-time SAS with the new device: 4829179\r\n',
          ),
        ),
        isNull,
      );
      expect(
        remoteMultiDeviceCliApprovalSas(
          utf8.encode('Compare SAS with the new device: 482917'),
        ),
        isNull,
      );
      expect(
        remoteMultiDeviceCliRequestsSasInput(
          utf8.encode('Type the same 6-digit SAS to continue:'),
        ),
        isFalse,
      );
      expect(
        remoteMultiDeviceCliRequestsApproval(
          utf8.encode(
            'Type APPROVE to confirm local user presence and authorize this device:',
          ),
        ),
        isFalse,
      );
    });
  });
}
