import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to awiki.ai service root and Message Agent enabled', () {
    final config = AwikiEnvironmentConfig();

    expect(config.baseUrl, 'https://awiki.ai');
    expect(config.userServiceUrl, 'https://awiki.ai');
    expect(config.messageServiceUrl, 'https://awiki.ai');
    expect(config.mailServiceUrl, 'https://awiki.ai');
    expect(config.didDomain, 'awiki.ai');
    expect(config.anpServiceUrl, 'https://awiki.ai/anp-im/rpc');
    expect(config.anpServiceDid, 'did:wba:awiki.ai');
    expect(config.daemonDownloadBaseUrl, 'https://awiki.ai/daemon');
    expect(
      config.updateManifestUrl,
      'https://awiki.ai/downloads/awiki-me/latest.json',
    );
    expect(config.releasesUrl, 'https://awiki.ai/#download');
    expect(config.agentImEnabled, isTrue);
  });

  test('base URL derives backend endpoints and daemon download root', () {
    final config = AwikiEnvironmentConfig(baseUrl: 'https://anpclaw.com/');

    expect(config.baseUrl, 'https://anpclaw.com');
    expect(config.userServiceUrl, 'https://anpclaw.com');
    expect(config.messageServiceUrl, 'https://anpclaw.com');
    expect(config.mailServiceUrl, 'https://anpclaw.com');
    expect(config.didDomain, 'anpclaw.com');
    expect(config.anpServiceUrl, 'https://anpclaw.com/anp-im/rpc');
    expect(config.anpServiceDid, 'did:wba:anpclaw.com');
    expect(config.daemonDownloadBaseUrl, 'https://anpclaw.com/daemon');
    expect(
      config.updateManifestUrl,
      'https://anpclaw.com/downloads/awiki-me/latest.json',
    );
    expect(config.releasesUrl, 'https://anpclaw.com/#download');
  });

  test('explicit Message Agent flag override can disable IM agent', () {
    final config = AwikiEnvironmentConfig(agentImEnabled: false);

    expect(config.agentImEnabled, isFalse);
  });

  test('advanced overrides win over base URL defaults', () {
    final config = AwikiEnvironmentConfig(
      baseUrl: 'https://anpclaw.com',
      userServiceUrl: 'https://users.example.test/',
      messageServiceUrl: 'https://messages.example.test/',
      mailServiceUrl: 'https://mail.example.test/',
      didDomain: 'did.example.test',
      anpServiceUrl: 'https://anp.example.test/rpc/',
      anpServiceDid: 'did:wba:anp.example.test',
      daemonDownloadBaseUrl: 'https://static.example.test/daemon/',
      updateManifestUrl: 'https://updates.example.test/app/latest.json',
      releasesUrl: 'https://download.example.test/releases/',
      agentImEnabled: true,
    );

    expect(config.baseUrl, 'https://anpclaw.com');
    expect(config.userServiceUrl, 'https://users.example.test');
    expect(config.messageServiceUrl, 'https://messages.example.test');
    expect(config.mailServiceUrl, 'https://mail.example.test');
    expect(config.didDomain, 'did.example.test');
    expect(config.anpServiceUrl, 'https://anp.example.test/rpc');
    expect(config.anpServiceDid, 'did:wba:anp.example.test');
    expect(config.daemonDownloadBaseUrl, 'https://static.example.test/daemon');
    expect(
      config.updateManifestUrl,
      'https://updates.example.test/app/latest.json',
    );
    expect(config.releasesUrl, 'https://download.example.test/releases');
    expect(config.agentImEnabled, isTrue);
  });

  test('network route config has no local storage locator', () {
    final first = AwikiEnvironmentConfig(
      baseUrl: 'https://api.customer.example:8443/root/',
      didDomain: 'customer.example',
    );
    final second = AwikiEnvironmentConfig(
      baseUrl: 'https://anything.internal',
      didDomain: 'tenant.internal',
    );

    expect(first.baseUrl, isNot(second.baseUrl));
    expect(first.didDomain, isNot(second.didDomain));
  });
}
