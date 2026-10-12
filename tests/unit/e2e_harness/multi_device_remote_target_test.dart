import 'package:flutter_test/flutter_test.dart';

import '../../e2e/remote_target.dart';

void main() {
  for (final appPair in [false, true]) {
    test('native multi-device target remains audited, appPair=$appPair', () {
      for (final domain in ['awiki.info', 'test-fix.anpclaw.com']) {
        validateMultiDeviceRemoteTarget(
          didDomain: domain,
          serviceUrls: ['https://$domain', 'https://$domain/anp-im/rpc'],
          appPair: appPair,
        );
      }
      for (final domain in [
        'qa.example.org',
        'test-fix-b.anpclaw.com',
        'test-fix.anpclaw.com.evil.example',
        '',
      ]) {
        expect(
          () => validateMultiDeviceRemoteTarget(
            didDomain: domain,
            serviceUrls: ['https://$domain'],
            appPair: appPair,
          ),
          throwsFormatException,
        );
      }
    });
    test('native target rejects unsafe URLs, appPair=$appPair', () {
      for (final urls in <List<String>>[
        [],
        ['http://test-fix.anpclaw.com'],
        ['https://awiki.info'],
        ['https://anpclaw.com'],
        ['https://user:password@test-fix.anpclaw.com'],
        ['https://test-fix.anpclaw.com?redirect=elsewhere'],
        ['https://test-fix.anpclaw.com#fragment'],
        ['https://test-fix.anpclaw.com:8443'],
        ['https://test-fix.anpclaw.com', 'https://test-fix-b.anpclaw.com'],
      ]) {
        expect(
          () => validateMultiDeviceRemoteTarget(
            didDomain: 'test-fix.anpclaw.com',
            serviceUrls: urls,
            appPair: appPair,
          ),
          throwsFormatException,
        );
      }
    });
  }
  test('existing main Singapore support is restricted to App-pair', () {
    validateMultiDeviceRemoteTarget(
      didDomain: 'anpclaw.com',
      serviceUrls: ['https://anpclaw.com'],
      appPair: true,
    );
    expect(
      () => validateMultiDeviceRemoteTarget(
        didDomain: 'anpclaw.com',
        serviceUrls: ['https://anpclaw.com'],
        appPair: false,
      ),
      throwsFormatException,
    );
  });
}
