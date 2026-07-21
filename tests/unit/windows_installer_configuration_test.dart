import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Inno keeps one escaped AppId and matching raw uninstall identity', () {
    final installer = File('installer/windows/awiki-me.iss').readAsStringSync();
    final verifier = File(
      'scripts/windows/verify_installer.ps1',
    ).readAsStringSync();

    const guid = '6D68B66D-87E1-4F18-93C5-AE56D58C5211';
    expect(installer, contains('#define MyAppGuid "$guid"'));
    expect(installer, contains('#define MyAppId "{{" + MyAppGuid + "}"'));
    expect(installer, contains('AppId={#MyAppId}'));
    expect(installer, contains('#define MyUninstallKey'));
    expect(installer, contains("'{#MyUninstallKey}'"));
    expect(installer, isNot(contains('AppId={#MyAppGuid}')));
    expect(verifier, contains('{$guid}_is1'));
  });

  test('installer is per-user, preserves data, and exits before overwrite', () {
    final installer = File('installer/windows/awiki-me.iss').readAsStringSync();
    final verifier = File(
      'scripts/windows/verify_installer.ps1',
    ).readAsStringSync();
    final worker = File('scripts/package_windows.ps1').readAsStringSync();

    expect(installer, contains('PrivilegesRequired=lowest'));
    expect(installer, isNot(contains('vc_redist.x64.exe')));
    expect(installer, isNot(contains('[Run]')));
    expect(worker, isNot(contains('vc_redist.x64.exe')));
    expect(worker, isNot(contains('MyVcRedistPath')));
    expect(
      installer,
      contains(r'DefaultDirName={localappdata}\Programs\{#MyAppName}'),
    );
    expect(installer, contains("'--shutdown-for-update'"));
    expect(installer, contains('CurUninstallStepChanged'));
    expect(installer, contains('RequestRunningAppShutdown'));
    expect(installer, contains('RaiseException'));
    expect(installer, contains('(ResultCode = 0)'));
    expect(installer, isNot(contains('deleteafterinstall recursesubdirs')));
    expect(verifier, contains('AWiki\\AWikiMe\\support'));
    expect(verifier, contains('Credential Manager item was deleted'));
    expect(
      r'Invoke-Installer $UpgradeInstaller'.allMatches(verifier),
      hasLength(2),
    );
    for (final runtime in <String>[
      'vcruntime140.dll',
      'vcruntime140_1.dll',
      'msvcp140.dll',
    ]) {
      expect(verifier, contains(runtime));
      expect(worker, contains(runtime));
    }
    for (final export in <String>[
      'frb_get_rust_content_hash',
      'frb_pde_ffi_dispatcher_primary',
      'frb_pde_ffi_dispatcher_sync',
      'frb_dart_fn_deliver_output',
    ]) {
      expect(worker, contains(export));
    }
    expect(worker, contains(r'Get-FileHash -LiteralPath $Installer'));
    expect(worker, contains("-Filter '*.dll'"));
    expect(worker, contains('awiki-runtime-manifest.json'));
    expect(worker, contains('[IO.Path]::GetRelativePath'));
    expect(verifier, contains('Assert-RuntimeManifest'));
    expect(verifier, contains('Installed runtime file hash mismatch'));
    expect(verifier, contains("'running-app uninstall'"));
    expect(worker, contains('-ExpectedRuntimeManifest'));
  });
}
