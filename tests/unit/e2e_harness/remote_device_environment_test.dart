import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/remote_device_environment.dart';

AwikiEnvironmentConfig environment({
  bool step4 = false,
  bool functional = false,
  bool sync = false,
  bool root = false,
}) => remoteDeviceEnvironment(
  baseUrl: 'https://awiki.info',
  userServiceUrl: 'https://awiki.info',
  messageServiceUrl: 'https://awiki.info',
  mailServiceUrl: 'https://awiki.info',
  didDomain: 'awiki.info',
  anpServiceUrl: 'https://awiki.info',
  anpServiceDid: 'did:wba:awiki.info',
  enableStep4: step4,
  enableAppPairFunctional: functional,
  enableMessageSyncCore: sync,
  enableRootTransfer: root,
);

void main() {
  test('Step4 group encryption has the reliable control-input pipeline', () {
    final config = environment(step4: true);
    expect(config.multiDeviceGroupE2eeEnabled, isTrue);
    expect(config.multiDeviceDeviceRevokeEnabled, isTrue);
    expect(config.messageSyncV2ReadEnabled, isTrue);
    expect(config.agentImEnabled, isFalse);
    expect(config.multiDeviceDirectE2eeEnabled, isFalse);
  });

  test('the base Join-only scenario keeps its existing limited scope', () {
    final config = environment();
    expect(config.messageSyncV2ReadEnabled, isFalse);
    expect(config.multiDeviceGroupE2eeEnabled, isFalse);
    expect(config.multiDeviceDeviceRevokeEnabled, isFalse);
  });

  test(
    'functional and explicit-sync scenarios keep their receive pipeline',
    () {
      expect(environment(functional: true).messageSyncV2ReadEnabled, isTrue);
      expect(environment(sync: true).messageSyncV2ReadEnabled, isTrue);
      expect(environment(functional: true).agentImEnabled, isTrue);
    },
  );

  test('root-transfer scope and canonical endpoints are preserved', () {
    final config = environment(root: true);
    expect(config.multiDeviceDirectE2eeEnabled, isTrue);
    expect(config.multiDeviceGroupE2eeEnabled, isFalse);
    expect(config.baseUrl, 'https://awiki.info');
    expect(config.userServiceUrl, 'https://awiki.info');
    expect(config.didDomain, 'awiki.info');
  });
}
