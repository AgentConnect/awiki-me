import 'dart:io';

/// Protects test-only files and state roots. NTFS ACLs replace POSIX mode checks
/// on Windows; neither platform silently skips the confidentiality boundary.
void protectE2ePathSync(String path, {bool directory = false}) {
  if (FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw StateError('E2E private paths cannot be symbolic links.');
  }
  final result = Platform.isWindows
      ? Process.runSync(
          'pwsh.exe',
          ['-NoProfile', '-NonInteractive', '-Command', _protectAcl],
          environment: {
            'AWIKI_E2E_PRIVATE_PATH': File(path).absolute.path,
            'AWIKI_E2E_PRIVATE_DIRECTORY': directory ? '1' : '0',
          },
        )
      : Process.runSync('chmod', [directory ? '700' : '600', path]);
  if (result.exitCode != 0)
    throw StateError('The E2E private path could not be protected.');
}

bool isPrivateE2eFile(File file) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file)
    return false;
  if (!Platform.isWindows) return (file.statSync().mode & 0x3f) == 0;
  final result = Process.runSync(
    'pwsh.exe',
    ['-NoProfile', '-NonInteractive', '-Command', _checkAcl],
    environment: {'AWIKI_E2E_PRIVATE_PATH': file.absolute.path},
  );
  return result.exitCode == 0 && result.stdout.toString().trim() == 'private';
}

const _protectAcl = r'''
$ErrorActionPreference='Stop'
$path=$env:AWIKI_E2E_PRIVATE_PATH
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$acl=Get-Acl -LiteralPath $path
$owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
$admin=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($owner -ne $sid.Value -and -not ($owner -eq 'S-1-5-32-544' -and $admin)){throw 'not_owned'}
$acl.SetAccessRuleProtection($true,$false)
foreach($rule in @($acl.Access)){$acl.RemoveAccessRuleSpecific($rule)}
$acl.SetOwner($sid)
foreach($principal in @($sid,$system)){
  if($env:AWIKI_E2E_PRIVATE_DIRECTORY -eq '1'){
    $rule=[Security.AccessControl.FileSystemAccessRule]::new($principal,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
  }else{$rule=[Security.AccessControl.FileSystemAccessRule]::new($principal,'FullControl','Allow')}
  $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $path -AclObject $acl
''';

const _checkAcl = r'''
$ErrorActionPreference='Stop'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$acl=Get-Acl -LiteralPath $env:AWIKI_E2E_PRIVATE_PATH
if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid){exit 1}
$rules=$acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
foreach($rule in $rules){
  if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @($sid,'S-1-5-18')){exit 1}
}
Write-Output 'private'
''';
