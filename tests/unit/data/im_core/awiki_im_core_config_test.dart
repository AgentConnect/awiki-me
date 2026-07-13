import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromEnvironment maps default service endpoints into SDK config', () {
    final config = AwikiImCoreEnvironmentConfig.fromEnvironment();
    final coreConfig = config.toCoreConfig();
    const baseUrl = primaryTenantBaseUrl;
    const domain = primaryTenantDomain;

    expect(config.serviceBaseUrl, baseUrl);
    expect(config.userServiceEndpoint, baseUrl);
    expect(config.messageServiceEndpoint, baseUrl);
    expect(config.mailServiceEndpoint, baseUrl);
    expect(config.didDomain, domain);
    expect(config.anpServiceDid, 'did:wba:$domain');
    expect(coreConfig, isA<core.AwikiImCoreConfig>());
    expect(coreConfig.serviceBaseUrl, config.serviceBaseUrl);
    expect(coreConfig.didDomain, config.didDomain);
    expect(coreConfig.anpServiceDid, 'did:wba:$domain');
    expect(coreConfig.transportPolicy, core.MessageTransportPolicy.auto);
  });

  test('explicit config preserves optional ANP service fields', () {
    const config = AwikiImCoreEnvironmentConfig(
      serviceBaseUrl: 'https://example.test',
      didDomain: 'example.test',
      anpServiceEndpoint: 'https://example.test/anp-im/rpc',
      anpServiceDid: 'did:wba:example.test',
      mailServiceEndpoint: 'https://mail.example.test',
      transportPolicy: core.MessageTransportPolicy.realtimePreferred,
    );

    final coreConfig = config.toCoreConfig();

    expect(coreConfig.mailServiceEndpoint, 'https://mail.example.test');
    expect(coreConfig.anpServiceEndpoint, 'https://example.test/anp-im/rpc');
    expect(coreConfig.anpServiceDid, 'did:wba:example.test');
    expect(
      coreConfig.transportPolicy,
      core.MessageTransportPolicy.realtimePreferred,
    );
  });
}
