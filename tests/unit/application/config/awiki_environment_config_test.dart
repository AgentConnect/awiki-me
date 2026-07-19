import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps awiki.ai as the default primary tenant domain', () {
    const hasBuildOverride = bool.hasEnvironment(
      primaryTenantDomainEnvironmentKey,
    );

    if (!hasBuildOverride) {
      expect(primaryTenantDomain, 'awiki.ai');
    }
  });

  test('derives default services from the primary tenant domain', () {
    final config = AwikiEnvironmentConfig();
    const baseUrl = primaryTenantBaseUrl;
    const domain = primaryTenantDomain;

    expect(config.baseUrl, baseUrl);
    expect(config.userServiceUrl, baseUrl);
    expect(config.messageServiceUrl, baseUrl);
    expect(config.mailServiceUrl, baseUrl);
    expect(config.didDomain, domain);
    expect(config.anpServiceUrl, '$baseUrl/anp-im/rpc');
    expect(config.anpServiceDid, 'did:wba:$domain');
    expect(config.daemonDownloadBaseUrl, '$baseUrl/daemon');
    expect(config.updateManifestUrl, '$baseUrl/downloads/awiki-me/latest.json');
    expect(config.releasesUrl, '$baseUrl/#download');
    expect(config.agentImEnabled, isTrue);
  });

  test('bundled realm allowlist enables Agent and Daemon capabilities', () {
    for (final domain in agentDaemonTenantDomainAllowlist) {
      final config = AwikiEnvironmentConfig(baseUrl: 'https://$domain');

      expect(config.didDomain, domain);
      expect(config.daemonDownloadBaseUrl, 'https://$domain/daemon');
      expect(config.agentImEnabled, isTrue, reason: domain);
    }
  });

  test('Agent and Daemon realm allowlist fails closed', () {
    for (final config in <AwikiEnvironmentConfig>[
      AwikiEnvironmentConfig(baseUrl: 'https://example.com'),
      AwikiEnvironmentConfig(
        baseUrl: 'https://awiki.info',
        didDomain: 'awiki.ai',
      ),
      AwikiEnvironmentConfig(baseUrl: 'http://awiki.info'),
      AwikiEnvironmentConfig(baseUrl: 'https://awiki.info:8443'),
      AwikiEnvironmentConfig(baseUrl: 'https://awiki.info/api'),
      AwikiEnvironmentConfig(baseUrl: 'https://subdomain.awiki.info'),
    ]) {
      expect(config.agentImEnabled, isFalse, reason: config.baseUrl);
    }
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

  test('explicit Personal Agent flag override can disable IM agent', () {
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
      multiDeviceJoinEnabled: true,
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
    expect(config.multiDeviceJoinEnabled, isTrue);
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
