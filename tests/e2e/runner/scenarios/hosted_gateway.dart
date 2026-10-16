part of '../../runner.dart';

extension HostedGatewayJoinScenario on DesktopE2eRunner {
  Future<void> _runHostedGatewayJoin() async {
    final fixture =
        Platform.environment['AWIKI_HOSTED_FIXTURE_PATH']?.trim() ?? '';
    final phoneFixture =
        Platform.environment['AWIKI_HOSTED_PHONE_FIXTURE_PATH']?.trim() ?? '';
    if (platform != DesktopE2ePlatform.macos) {
      throw E2eFailure(
        'Hosted Gateway App acceptance currently requires macOS.',
      );
    }
    if (!options.dryRun && !options.prepareOnly) {
      if (fixture.isEmpty ||
          !File(fixture).isAbsolute ||
          !File(fixture).existsSync() ||
          phoneFixture.isEmpty ||
          !File(phoneFixture).isAbsolute ||
          !File(phoneFixture).existsSync()) {
        throw E2eFailure(
          'Hosted Gateway acceptance needs an explicit protected fixture file.',
        );
      }
      if (appStateRootDir.existsSync() ||
          Directory('${appStateRootDir.path}-approval').existsSync()) {
        throw E2eFailure(
          'Hosted Gateway acceptance requires a fresh App device root.',
        );
      }
      suiteDefinition.validateRemoteTargetValues(
        didDomain: 'mcp-adapt.anpclaw.com',
        serviceUrls: const ['https://mcp-adapt.anpclaw.com'],
      );
    }
    _addRuntimeSecret(fixture);
    _addRuntimeSecret(phoneFixture);
    await commands.requireExecutable('ssh');
    await commands.run('bash', const [
      'scripts/verify_im_core_native_artifact.sh',
    ], timeout: const Duration(minutes: 1));
    if (options.dryRun) {
      _line(
        'Plan: build isolated hosted join App; execute only against mcp-adapt.anpclaw.com.',
      );
      return;
    }
    final artifact = await _prepareIntegrationExecutable(
      name: 'hosted-gateway-join',
      stateRoot: appStateRootDir,
    );
    if (options.prepareOnly || options.dryRun) return;
    _resourceSideEffectsPossible = true;
    await _executePreparedIntegration(
      artifact: artifact,
      caseIds: options.e2eCase.caseIds,
      stateRoot: appStateRootDir,
      environment: {
        'AWIKI_HOSTED_FIXTURE_PATH': fixture,
        'AWIKI_HOSTED_PHONE_FIXTURE_PATH': phoneFixture,
        // The executable builder creates its state root. Product fixtures need
        // their own untouched device roots underneath that runner-owned root.
        'AWIKI_HOSTED_APP_STATE_ROOT': '${appStateRootDir.path}/joining-device',
      },
    );
  }
}
