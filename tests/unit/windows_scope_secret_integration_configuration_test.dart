import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows CI runs the production scope-secret lifecycle probe', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();
    final probe = File(
      'tests/e2e/flutter/native/production_scope_restart_probe.dart',
    ).readAsStringSync();
    final runner = File(
      'scripts/windows/run_scope_secret_integration.ps1',
    ).readAsStringSync();

    expect(
      workflow,
      contains(
        r'WINDOWS_CORE_REF: ${{ github.event.inputs.cli_ref || '
        'vars.AWIKI_CLI_RS2_WINDOWS_REF || vars.AWIKI_CLI_RS2_REF }}',
      ),
    );
    expect(
      workflow,
      contains(
        '--target tests/e2e/flutter/native/'
        'production_scope_restart_probe.dart',
      ),
    );
    expect(
      workflow,
      contains('./scripts/windows/run_scope_secret_integration.ps1'),
    );

    expect(probe, contains('Platform.isWindows'));
    expect(probe, contains('!kReleaseMode'));
    expect(probe, contains('main(List<String> arguments)'));
    expect(probe, contains('fromEnvironment(widget.arguments)'));
    expect(probe, isNot(contains('Platform.executableArguments')));
    expect(probe, contains('PlatformScopeSecretRepository.forCurrentBuild()'));
    expect(probe, contains("'ai.awiki.awikime.scope-secrets'"));
    for (final phase in <String>[
      'provision',
      'reopen',
      'corrupt',
      'scope_mismatch',
      'cleanup',
    ]) {
      expect(probe, contains("case '$phase':"), reason: phase);
      expect(runner, contains("Invoke-ProbePhase '$phase'"), reason: phase);
    }

    expect(runner, contains('CredWriteW'));
    expect(runner, contains('CredDeleteW'));
    expect(
      runner,
      contains(
        r'[Security.Cryptography.RandomNumberGenerator]::Fill($keyBytes)',
      ),
    );
    expect(runner, contains('finally {'));
    expect(
      runner,
      contains(r'[AwikiScopeSecretCredentialProbe]::Delete($CredentialTarget)'),
    );
  });
}
