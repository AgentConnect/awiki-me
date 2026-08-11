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
        'Type APPROVE to confirm local user presence and authorize this device: ',
      );

      expect(remoteMultiDeviceCliApprovalSas(transcript), '482917');
      expect(remoteMultiDeviceCliRequestsSasInput(transcript), isTrue);
      expect(remoteMultiDeviceCliRequestsApproval(transcript), isTrue);
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
