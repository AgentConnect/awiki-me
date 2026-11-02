import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/protected_files.dart';
import '../../e2e/root_transfer_fixture_state.dart';

void main() {
  test('retained fixture key is private and cannot be overwritten', () async {
    final root = await Directory.systemTemp.createTemp('awiki-fixture-key-');
    addTearDown(() => root.delete(recursive: true));
    const syntheticKey = 'synthetic-offline-fixture-wrapping-key';
    await retainRootTransferFixtureKey(root.path, syntheticKey);
    final file = File('${root.path}/.root-transfer-vault-key.local');
    expect(isPrivateE2eFile(file), isTrue);
    expect(await file.readAsString(), syntheticKey);
    await expectLater(
      retainRootTransferFixtureKey(root.path, 'replacement-must-not-win'),
      throwsStateError,
    );
    expect(await file.readAsString(), syntheticKey);
  });
}
