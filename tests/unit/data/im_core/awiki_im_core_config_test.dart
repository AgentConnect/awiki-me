import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/data/im_core/awiki_im_core_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromEnvironment maps default service endpoints into SDK config', () {
    final config = AwikiImCoreEnvironmentConfig.fromEnvironment();
    final coreConfig = config.toCoreConfig();

    expect(config.serviceBaseUrl, 'https://awiki.info');
    expect(config.userServiceEndpoint, 'https://awiki.info');
    expect(config.messageServiceEndpoint, 'https://awiki.info');
    expect(config.mailServiceEndpoint, 'https://awiki.info');
    expect(config.didDomain, 'awiki.info');
    expect(config.anpServiceDid, 'did:wba:awiki.info');
    expect(coreConfig, isA<core.AwikiImCoreConfig>());
    expect(coreConfig.serviceBaseUrl, config.serviceBaseUrl);
    expect(coreConfig.didDomain, config.didDomain);
    expect(coreConfig.anpServiceDid, 'did:wba:awiki.info');
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
