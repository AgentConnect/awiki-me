import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:awiki_me/src/data/avatar/avatar_picker_files.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String> getTemporaryPath() async => root;
}

void main() {
  test(
    'discards only picker copies within the App temporary directory',
    () async {
      final previous = PathProviderPlatform.instance;
      final root = await Directory.systemTemp.createTemp('avatar-picker-test-');
      final cache = await Directory('${root.path}/cache').create();
      PathProviderPlatform.instance = _Paths(cache.path);
      try {
        final copy = await File(
          '${cache.path}/picked.jpg',
        ).writeAsString('copy');
        final original = await File(
          '${root.path}/original.jpg',
        ).writeAsString('original');
        final link = await Link('${cache.path}/link.jpg').create(original.path);
        await discardAvatarPickerFile(original.path);
        await discardAvatarPickerFile(link.path);
        expect(await original.readAsString(), 'original');
        expect(await link.exists(), isTrue);
        await discardAvatarPickerFile(copy.path);
        expect(await copy.exists(), isFalse);
        await discardAvatarPickerFile(copy.path); // OS already removed it.
      } finally {
        PathProviderPlatform.instance = previous;
        await root.delete(recursive: true);
      }
    },
  );
}
