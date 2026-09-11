import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/runner/manifest.dart';
import '../../e2e/remote_target.dart';

void main() {
  test('configured target preserves HTTPS, exact domain and origin guards', () {
    for (final url in <String>[
      'http://qa.example.org',
      'https://other.example.org',
      'https://qa.example.org.evil.example',
      'https://user:password@qa.example.org',
      'https://qa.example.org?redirect=elsewhere',
      'https://qa.example.org#fragment',
      'https://qa.example.org:8443',
      'not-a-url',
    ]) {
      expect(
        () => validateConfiguredRemoteTarget(
          didDomain: 'qa.example.org',
          serviceUrls: ['https://qa.example.org', url],
        ),
        throwsFormatException,
        reason: url,
      );
    }
    for (final domain in [
      '',
      'localhost',
      '127.0.0.1',
      'qa.example.org/path',
    ]) {
      expect(
        () => validateConfiguredRemoteTarget(
          didDomain: domain,
          serviceUrls: ['https://qa.example.org'],
        ),
        throwsFormatException,
      );
    }
    expect(
      () => validateConfiguredRemoteTarget(
        didDomain: 'qa.example.org',
        serviceUrls: [],
      ),
      throwsFormatException,
    );
  });
  for (final suite in <String>[
    'multi-device-app-pair-recovery-retirement-ordinary-rejoin',
    'identity-deletion-recovery-guard',
  ]) {
    test('$suite checks the configured secure WebSocket origin', () {
      final definition = DesktopE2eSuiteManifest.load(
        Directory.current,
      ).definitions[suite]!;
      expect(
        () => definition.validateRemoteTarget(
          _Target('wss://qa.example.org/im/ws'),
        ),
        returnsNormally,
      );
      for (final ws in [
        'ws://qa.example.org/im/ws',
        'wss://other.example.org/im/ws',
        'wss://qa.example.org:8443/im/ws',
        'wss://qa.example.org/wrong',
        'wss://user:password@qa.example.org/im/ws',
      ]) {
        expect(
          () => definition.validateRemoteTarget(_Target(ws)),
          throwsException,
        );
      }
    });
    test('$suite rejects a mismatched configured service', () {
      final definition = DesktopE2eSuiteManifest.load(
        Directory.current,
      ).definitions[suite]!;
      expect(definition.remoteTargetPolicy, 'configured_same_origin');
      expect(definition.allowedHosts, isEmpty);
      expect(definition.allowedDidDomains, isEmpty);
      expect(
        () => definition.validateRemoteTargetValues(
          didDomain: 'qa.example.org',
          serviceUrls: ['https://other.example.org'],
        ),
        throwsException,
      );
    });
    for (final domain in <String>['awiki.info', 'rwiki.cn', 'qa.example.org']) {
      test('$suite uses the externally configured $domain target', () {
        final definition = DesktopE2eSuiteManifest.load(
          Directory.current,
        ).definitions[suite]!;
        expect(
          () => definition.validateRemoteTargetValues(
            didDomain: domain,
            serviceUrls: <String>[
              'https://$domain',
              'https://$domain/user-service',
              'https://$domain/anp-im/rpc',
            ],
          ),
          returnsNormally,
        );
      });
    }
  }
}

class _Target implements DesktopRemoteTargetContract {
  _Target(this.messageServiceWsUrl);
  @override
  final String messageServiceWsUrl;
  @override
  String get didDomain => 'qa.example.org';
  @override
  String get serviceBaseUrl => 'https://qa.example.org';
  @override
  String get userServiceUrl => serviceBaseUrl;
  @override
  String get messageServiceUrl => serviceBaseUrl;
}
