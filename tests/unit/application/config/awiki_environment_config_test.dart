import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to awiki.info service root and Message Agent enabled', () {
    final config = AwikiEnvironmentConfig();

    expect(config.baseUrl, 'https://awiki.info');
    expect(config.userServiceUrl, 'https://awiki.info');
    expect(config.messageServiceUrl, 'https://awiki.info');
    expect(config.mailServiceUrl, 'https://awiki.info');
    expect(config.didDomain, 'awiki.info');
    expect(config.stateNamespace, 'awiki.info');
    expect(config.anpServiceUrl, 'https://awiki.info/anp-im/rpc');
    expect(config.anpServiceDid, 'did:wba:awiki.info');
    expect(config.daemonDownloadBaseUrl, 'https://awiki.info/daemon');
    expect(config.packageChannel, 'test');
    expect(
      config.updateManifestUrl,
      'https://awiki.info/downloads/awiki-me/test/latest.json',
    );
    expect(config.releasesUrl, 'https://awiki.info/#download');
    expect(config.agentImEnabled, isTrue);
  });

  test('base URL derives backend endpoints and daemon download root', () {
    final config = AwikiEnvironmentConfig(baseUrl: 'https://anpclaw.com/');

    expect(config.baseUrl, 'https://anpclaw.com');
    expect(config.userServiceUrl, 'https://anpclaw.com');
    expect(config.messageServiceUrl, 'https://anpclaw.com');
    expect(config.mailServiceUrl, 'https://anpclaw.com');
    expect(config.didDomain, 'anpclaw.com');
    expect(config.stateNamespace, 'anpclaw.com');
    expect(config.anpServiceUrl, 'https://anpclaw.com/anp-im/rpc');
    expect(config.anpServiceDid, 'did:wba:anpclaw.com');
    expect(config.daemonDownloadBaseUrl, 'https://anpclaw.com/daemon');
    expect(
      config.updateManifestUrl,
      'https://anpclaw.com/downloads/awiki-me/test/latest.json',
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
      stateNamespace: 'Customer Env / CN #1',
      anpServiceUrl: 'https://anp.example.test/rpc/',
      anpServiceDid: 'did:wba:anp.example.test',
      daemonDownloadBaseUrl: 'https://static.example.test/daemon/',
      packageChannel: 'internal beta',
      updateManifestUrl: 'https://updates.example.test/app/latest.json',
      releasesUrl: 'https://download.example.test/releases/',
      agentImEnabled: true,
    );

    expect(config.baseUrl, 'https://anpclaw.com');
    expect(config.userServiceUrl, 'https://users.example.test');
    expect(config.messageServiceUrl, 'https://messages.example.test');
    expect(config.mailServiceUrl, 'https://mail.example.test');
    expect(config.didDomain, 'did.example.test');
    expect(config.stateNamespace, 'customer-env-cn-1');
    expect(config.anpServiceUrl, 'https://anp.example.test/rpc');
    expect(config.anpServiceDid, 'did:wba:anp.example.test');
    expect(config.daemonDownloadBaseUrl, 'https://static.example.test/daemon');
    expect(config.packageChannel, 'internal-beta');
    expect(
      config.updateManifestUrl,
      'https://updates.example.test/app/latest.json',
    );
    expect(config.releasesUrl, 'https://download.example.test/releases');
    expect(config.agentImEnabled, isTrue);
  });

  test('state namespace works for arbitrary future backend roots', () {
    final sameDomain = AwikiEnvironmentConfig(
      baseUrl: 'https://api.customer.example:8443/root/',
      didDomain: 'customer.example',
    );

    expect(
      sameDomain.stateNamespace,
      'customer.example-api.customer.example-8443',
    );

    final explicit = AwikiEnvironmentConfig(
      baseUrl: 'https://anything.internal',
      didDomain: 'tenant.internal',
      stateNamespace: 'tenant-alpha',
    );

    expect(explicit.stateNamespace, 'tenant-alpha');
  });
}
