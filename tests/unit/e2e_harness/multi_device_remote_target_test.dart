import 'package:flutter_test/flutter_test.dart';

import '../../e2e/remote_target.dart';

void main() {
  test('DSH stdin config preserves the audited target and service DID', () {
    for (final domain in ['awiki.info', 'test-fix.anpclaw.com']) {
      final target = dshDeviceJoinTargetConfig(
        didDomain: domain,
        serviceDid: 'did:wba:$domain',
        userServiceUrl: 'https://$domain',
        messageServiceUrl: 'https://$domain',
        baseUrl: 'https://$domain',
      );
      expect(target, {
        'didDomain': domain,
        'userServiceUrl': 'https://$domain',
        'messageServiceUrl': 'https://$domain',
        'messageServicePublicUrl': 'https://$domain',
        'messageServiceDid': 'did:wba:$domain',
      });
    }
  });
  test('DSH rejects mismatched DID, paths, origins and unaudited domains', () {
    const domain = 'test-fix.anpclaw.com';
    for (final row in [
      (domain, 'did:wba:awiki.info', 'https://$domain'),
      (domain, 'did:wba:$domain', 'https://$domain/anp-im/rpc'),
      (domain, 'did:wba:$domain', 'https://awiki.info'),
      (domain, 'did:wba:$domain', 'https://$domain:8443'),
      ('anpclaw.com', 'did:wba:anpclaw.com', 'https://anpclaw.com'),
    ]) {
      expect(
        () => dshDeviceJoinTargetConfig(
          didDomain: row.$1,
          serviceDid: row.$2,
          userServiceUrl: row.$3,
          messageServiceUrl: 'https://${row.$1}',
          baseUrl: 'https://${row.$1}',
        ),
        throwsFormatException,
      );
    }
  });

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
