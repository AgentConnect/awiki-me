// Test-only retention of the wrapping key needed to inspect an unresolved run.
import 'dart:io';
import 'protected_files.dart';

Future<void> retainRootTransferFixtureKey(String home, String key) async {
  final directory = await Directory(home).create(recursive: true);
  final file = File('${directory.path}/.root-transfer-vault-key.local');
  if (await file.exists()) {
    throw StateError('root_transfer_fixture_key_already_exists');
  }
  protectE2ePathSync(directory.path, directory: true);
  await file.create();
  protectE2ePathSync(file.path);
  await file.writeAsString(key, flush: true);
}
