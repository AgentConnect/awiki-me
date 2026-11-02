import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../e2e/protected_files.dart';
import '../../e2e/desktop_paths.dart';

void main() {
  test('Windows config paths preserve drive letters and UNC roots', () {
    final root = Directory.systemTemp;
    for (final path in [
      r'D:\AWiki test\config.yaml',
      r'\\server\share\config.yaml',
      'D:/AWiki/config.yaml',
    ]) {
      expect(resolveDesktopConfigPath(root, path), path);
    }
    expect(resolveDesktopConfigPath(root, '../peer'), '${root.path}/../peer');
  });
  test(
    'Windows sensitive fixtures reject broad ACLs and become owner/system-only',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'awiki-private-file-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/fixture.json',
      ).writeAsString('fixture-no-secrets');
      protectE2ePathSync(directory.path, directory: true);
      protectE2ePathSync(file.path);
      expect(isPrivateE2eFile(file), isTrue);
      final changed = await Process.run(
        'pwsh.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'$p=$env:AWIKI_ACL_FIXTURE; $a=Get-Acl -LiteralPath $p; '
              r'$s=[Security.Principal.SecurityIdentifier]::new("S-1-5-32-545"); '
              r'$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($s,"Read","Allow")); '
              r'Set-Acl -LiteralPath $p -AclObject $a',
        ],
        environment: {'AWIKI_ACL_FIXTURE': file.path},
      );
      expect(changed.exitCode, 0);
      expect(isPrivateE2eFile(file), isFalse);
      protectE2ePathSync(file.path);
      expect(isPrivateE2eFile(file), isTrue);
    },
    skip: !Platform.isWindows,
  );
}
