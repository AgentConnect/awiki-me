import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../e2e/root_transfer_fixture_state.dart';

void main() {
  test(
    'unresolved root transfer retains its wrapping key privately without overwrite',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'root-transfer-fixture-',
      );
      addTearDown(() => root.delete(recursive: true));
      await retainRootTransferFixtureKey(root.path, 'fixture-wrapping-key');
      final file = File('${root.path}/.root-transfer-vault-key.local');
      expect(await file.readAsString(), 'fixture-wrapping-key');
      expect((await root.stat()).mode & 0x1ff, 0x1c0);
      expect((await file.stat()).mode & 0x1ff, 0x180);
      await expectLater(
        retainRootTransferFixtureKey(root.path, 'replacement'),
        throwsStateError,
      );
      expect(await file.readAsString(), 'fixture-wrapping-key');
    },
    skip: Platform.isWindows,
  );
}
