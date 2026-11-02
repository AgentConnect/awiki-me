import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import '../../e2e/desktop_paths.dart';

void main() {
  final root = Directory(
    Platform.isWindows ? 'D:/awiki-space/awiki-me' : '/tmp/awiki-me',
  );
  final temp = Directory(Platform.isWindows ? 'D:/temp' : '/tmp');
  Directory select(
    String scope,
    String run, {
    Directory? project,
    Directory? temporary,
  }) => desktopRuntimeStateRoot(
    projectRoot: project ?? root,
    suiteScope: scope,
    runId: run,
    operatingSystem: 'windows',
    systemTemporaryDirectory: temporary ?? temp,
  );
  test(
    'Windows SQLite canonical-upgrade backup fits despite long suite/run IDs',
    () {
      final state = select(
        'multi-device-app-pair-recovery-registration-resume',
        'win-full-20261102-02-11',
      );
      final backup = p.join(
        state.path,
        'j',
        'support',
        'awiki-me',
        'storage-scopes',
        '00000000-0000-0000-0000-000000000000',
        'product',
        'canonical-conversation-overlay-upgrade',
        'awiki_me_product_store.pre-canonical-v2.sqlite.tmp',
      );
      expect(backup.length, lessThan(250));
      expect(state.path, isNot(contains('registration-resume')));
    },
  );
  test('Windows state roots remain stable and distinct per scope and run', () {
    expect(select('recovery', 'run-1').path, select('recovery', 'run-1').path);
    expect(
      select('recovery', 'run-1').path,
      isNot(select('recovery', 'run-2').path),
    );
    expect(
      select('recovery', 'run-1').path,
      isNot(select('join', 'run-1').path),
    );
  });
  test(
    'A deep workspace uses only the selected temporary root and stays bounded',
    () {
      final temporary = temp;
      final selected = select(
        'recovery',
        'run-1',
        project: Directory('${root.path}/${'deep' * 40}'),
        temporary: temporary,
      );
      expect(
        p.normalize(selected.parent.path),
        p.normalize(temporary.absolute.path),
      );
      expect(
        () => select(
          'recovery',
          'run-1',
          project: Directory('${root.path}/${'deep' * 40}'),
          temporary: Directory('${temporary.path}/${'deep' * 40}'),
        ),
        throwsStateError,
      );
    },
  );
  test('Other desktop platforms retain the existing runtime layout', () {
    for (final platform in ['macos', 'linux']) {
      expect(
        desktopRuntimeStateRoot(
          projectRoot: root,
          suiteScope: 'recovery',
          runId: 'run-1',
          operatingSystem: platform,
        ).path,
        '${root.path}/.e2e/recovery/run-1',
      );
    }
  });
}
