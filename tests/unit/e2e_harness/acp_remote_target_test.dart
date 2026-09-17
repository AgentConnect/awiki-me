import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/runner/manifest.dart';
import '../../e2e/flutter/support/app_pair_target.dart';

void main() {
  test(
    'ACP App pair accepts the selected audited host and retains target gates',
    () {
      final suite = DesktopE2eSuiteManifest.load(
        Directory.current,
      ).definitions['multi-device-app-pair-acp']!;
      for (final domain in ['awiki.info', 'anpclaw.com']) {
        expect(
          () => suite.validateRemoteTargetValues(
            didDomain: domain,
            serviceUrls: ['https://$domain', 'https://$domain/user-service'],
          ),
          returnsNormally,
        );
        expect(
          () => validateAppPairRemoteTarget(
            acp: true,
            didDomain: domain,
            serviceUrls: ['https://$domain', 'https://$domain/user-service'],
          ),
          returnsNormally,
        );
      }
      for (final url in [
        'http://anpclaw.com',
        'https://anpclaw.com.evil.example',
        'https://unreviewed.example',
      ]) {
        expect(
          () => suite.validateRemoteTargetValues(
            didDomain: 'anpclaw.com',
            serviceUrls: [url],
          ),
          throwsException,
        );
        expect(
          () => validateAppPairRemoteTarget(
            acp: true,
            didDomain: 'anpclaw.com',
            serviceUrls: [url],
          ),
          throwsStateError,
        );
      }
      expect(
        () => suite.validateRemoteTargetValues(
          didDomain: 'unreviewed.example',
          serviceUrls: ['https://anpclaw.com'],
        ),
        throwsException,
      );
    },
  );
  test('App guard preserves other suites and rejects mixed tenants', () {
    expect(
      () => validateAppPairRemoteTarget(
        acp: false,
        didDomain: 'awiki.info',
        serviceUrls: ['https://awiki.info'],
      ),
      returnsNormally,
    );
    for (final args in [
      (acp: false, domain: 'anpclaw.com', url: 'https://anpclaw.com'),
      (acp: true, domain: 'unreviewed.example', url: 'https://anpclaw.com'),
      (acp: true, domain: 'anpclaw.com', url: 'https://awiki.info'),
    ]) {
      expect(
        () => validateAppPairRemoteTarget(
          acp: args.acp,
          didDomain: args.domain,
          serviceUrls: [args.url],
        ),
        throwsStateError,
      );
    }
  });
}
