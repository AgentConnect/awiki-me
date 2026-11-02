import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../tool/windows_nuget_cache.dart';

void main() {
  test(
    'verified prior download is reused and corrupt cache is rejected',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-nuget-cache-');
      addTearDown(() => root.delete(recursive: true));
      final candidate = await File(
        '${root.path}/source.exe',
      ).writeAsBytes([1, 2, 3]);
      final target = File('${root.path}/cache/nuget.exe');
      final digest = sha256.convert([1, 2, 3]).toString();
      var downloads = 0;
      Future<List<int>> download() async {
        downloads++;
        return [1, 2, 3];
      }

      await cacheVerifiedWindowsTool(
        target: target,
        candidates: [candidate],
        expectedSha256: digest,
        download: download,
      );
      expect(await target.readAsBytes(), [1, 2, 3]);
      expect(downloads, 0);
      await cacheVerifiedWindowsTool(
        target: target,
        candidates: [],
        expectedSha256: digest,
        download: download,
      );
      expect(downloads, 0);
      await target.writeAsBytes([9]);
      await expectLater(
        cacheVerifiedWindowsTool(
          target: target,
          candidates: [candidate],
          expectedSha256: digest,
          download: download,
        ),
        throwsStateError,
      );
    },
  );
  test(
    'download bytes must match the dependency hash before caching',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki-nuget-integrity-',
      );
      addTearDown(() => root.delete(recursive: true));
      final target = File('${root.path}/nuget.exe');
      final digest = sha256.convert([1, 2, 3]).toString();
      await expectLater(
        cacheVerifiedWindowsTool(
          target: target,
          candidates: [],
          expectedSha256: digest,
          download: () async => [9],
        ),
        throwsStateError,
      );
      expect(target.existsSync(), isFalse);
      await cacheVerifiedWindowsTool(
        target: target,
        candidates: [],
        expectedSha256: digest,
        download: () async => [1, 2, 3],
      );
      expect(await target.readAsBytes(), [1, 2, 3]);
    },
  );
}
