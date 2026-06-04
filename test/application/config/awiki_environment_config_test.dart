import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    );

    expect(config.baseUrl, 'https://anpclaw.com');
    expect(config.userServiceUrl, 'https://users.example.test');
    expect(config.messageServiceUrl, 'https://messages.example.test');
    expect(config.mailServiceUrl, 'https://mail.example.test');
    expect(config.didDomain, 'did.example.test');
    expect(config.anpServiceUrl, 'https://anp.example.test/rpc');
    expect(config.anpServiceDid, 'did:wba:anp.example.test');
    expect(config.daemonDownloadBaseUrl, 'https://static.example.test/daemon');
  });
}
