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
    expect(installer, isNot(contains('[InstallDelete]')));
    expect(installer, contains('DisableDirPage=yes'));
    expect(installer, contains('UsePreviousAppDir=no'));
    expect(installer, isNot(contains('PurgeInstalledPayload')));
    expect(installer, contains('CapturePreviousRuntimeFiles'));
    expect(installer, contains('RemoveObsoleteRuntimeFiles'));
    expect(installer, contains('IsSafeRuntimeRelativePath'));
    expect(installer, contains('LoadStringsFromFile'));
    expect(installer, contains('StringChangeEx'));
    expect(installer, contains('ExpandFileName'));
    expect(installer, contains("Pos('./', Framed)"));
    expect(installer, contains("Pos(' /', Framed)"));
    expect(installer, contains('CurStep = ssPostInstall'));
    expect(installer, contains('DelTree('));
    expect(installer, isNot(contains(r'AWiki\AWikiMe\support')));
    expect(installer, isNot(contains(r'AWiki\AWikiMe\cache')));
    final shutdown = installer.lastIndexOf(
      'if not RequestRunningAppShutdown() then',
    );
    final capture = installer.lastIndexOf('CapturePreviousRuntimeFiles();');
    expect(shutdown, greaterThanOrEqualTo(0));
    expect(capture, greaterThan(shutdown));
    expect(verifier, contains('AWiki\\AWikiMe\\support'));
    expect(verifier, contains('AWiki\\AWikiMe\\cache'));
    expect(verifier, contains('Credential Manager item was deleted'));
    expect(verifier, contains(r'^unins[0-9]{3}\.(dat|exe|msg)$'));
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
    expect(worker, contains('awiki-runtime-files.txt'));
    expect(worker, contains('[IO.Path]::GetRelativePath'));
    expect(worker, contains(r'$BaseAppStage'));
    expect(worker, contains('obsolete-runtime-fixture.dll'));
    expect(worker, contains('obsolete-runtime-fixture.txt'));
    expect(worker, contains('-ExpectedBaseRuntimeManifest'));
    expect(
      worker,
      contains("Compile-Installer \$compiler \$BaseAppStage '0.0.0'"),
    );
    expect(verifier, contains('Assert-RuntimeManifest'));
    expect(verifier, contains('Installed runtime file hash mismatch'));
    expect(verifier, contains('Installed runtime allowlist mismatch'));
    expect(verifier, contains('Assert-ObsoleteRuntimeFiles'));
    expect(verifier, contains('removed during upgrade'));
    expect(verifier, contains('ExpectedSupportSentinelHash'));
    expect(verifier, contains('ExpectedCacheSentinelHash'));
    expect(verifier, contains('state was modified'));
    expect(
      'Assert-PreservedExternalState'.allMatches(verifier).length,
      greaterThanOrEqualTo(6),
    );
    expect(verifier, contains("'running-app uninstall'"));
    expect(verifier, contains('Application directory remains after uninstall'));
    expect(
      verifier,
      contains('Uninstall registration remains after uninstall'),
    );
    expect(worker, contains('-ExpectedRuntimeManifest'));
  });
}
