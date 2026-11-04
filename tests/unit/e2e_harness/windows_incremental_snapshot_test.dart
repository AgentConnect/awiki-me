import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../tool/windows_e2e_workspace.dart';

void main() {
  test(
    'compatible refresh preserves final-byte mtimes and caches, removes deleted inputs',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'incremental-snapshot-',
      );
      addTearDown(() => root.delete(recursive: true));
      expect(
        (await Process.run('git', [
          'init',
        ], workingDirectory: root.path)).exitCode,
        0,
      );
      final input = File('${root.path}/lib/main.dart');
      await input.parent.create(recursive: true);
      await input.writeAsString('source');
      final removed = File('${root.path}/lib/removed.dart');
      await removed.writeAsString('old');
      final out = Directory('${root.path}/.e2e/slot/s');
      Future<Directory> configure(
        Directory _,
        Directory target,
        String bundle,
        String name,
      ) async {
        final file = File('${target.path}/lib/main.dart');
        file.writeAsStringSync('${file.readAsStringSync()} configured');
        return target;
      }

      Future<void> refresh(String key) => prepareWindowsE2eWorkspace(
        projectRoot: root,
        destination: out,
        bundleId: 'ai.awiki.test',
        name: 'test',
        compatibilityKey: key,
        configure: configure,
      ).then((_) {});
      await refresh('dependency-lock-a');
      final output = File('${out.path}/lib/main.dart');
      final oldTime = DateTime.utc(2020);
      output.setLastModifiedSync(oldTime);
      final cache = File('${out.path}/.dart_tool/incremental-cache');
      await cache.parent.create(recursive: true);
      await cache.writeAsString('keep');
      await removed.delete();
      await refresh('dependency-lock-a');
      expect(output.readAsStringSync(), 'source configured');
      expect(
        output.lastModifiedSync().microsecondsSinceEpoch,
        oldTime.microsecondsSinceEpoch,
      );
      expect(cache.readAsStringSync(), 'keep');
      expect(File('${out.path}/lib/removed.dart').existsSync(), isFalse);
      await input.writeAsString('changed');
      await refresh('dependency-lock-a');
      expect(output.readAsStringSync(), 'changed configured');
      expect(
        output.lastModifiedSync().microsecondsSinceEpoch,
        isNot(oldTime.microsecondsSinceEpoch),
      );
      await refresh('dependency-lock-b');
      expect(cache.existsSync(), isFalse);
      await expectLater(
        prepareWindowsE2eWorkspace(
          projectRoot: root,
          destination: Directory('${root.path}/lib'),
          bundleId: 'ai.awiki.test',
          name: 'test',
          compatibilityKey: 'dependency-lock-b',
          configure: configure,
        ),
        throwsStateError,
      );
      expect(input.readAsStringSync(), 'changed');
    },
  );
}
