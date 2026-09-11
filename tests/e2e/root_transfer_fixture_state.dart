// Test-only retention of the wrapping key needed to inspect an unresolved run.
import 'dart:io';

Future<void> retainRootTransferFixtureKey(String home, String key) async {
  final directory = await Directory(home).create(recursive: true);
  final file = File('${directory.path}/.root-transfer-vault-key.local');
  if (await file.exists()) {
    throw StateError('root_transfer_fixture_key_already_exists');
  }
  if ((await Process.run('chmod', <String>['700', directory.path])).exitCode !=
      0) {
    throw StateError('root_transfer_fixture_permissions_failed');
  }
  await file.create();
  if ((await Process.run('chmod', <String>['600', file.path])).exitCode != 0) {
    throw StateError('root_transfer_fixture_permissions_failed');
  }
  await file.writeAsString(key, flush: true);
}
