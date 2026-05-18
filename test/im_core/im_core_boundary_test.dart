import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IM Core import boundary', () {
    test(
      'lib/src/im_core stays independent from app UI/domain/data services',
      () {
        final files = _dartFilesUnder('lib/src/im_core');
        expect(files, isNotEmpty);

        const forbiddenImports = <String>[
          'package:flutter/',
          'package:flutter_riverpod/',
          'lib/src/domain/',
          '../domain/',
          'lib/src/presentation/',
          '../presentation/',
          'lib/src/app/',
          '../app/',
          'notification_facade',
          'notification_service',
          'lib/src/data/gateways/',
          '../data/gateways/',
          'lib/src/data/services/',
          '../data/services/',
          'awiki_anp_gateway',
          'awiki_message_client',
          'awiki_wire_mapper',
          'awiki_local_cache',
          'awiki_ws_realtime_gateway',
        ];

        for (final file in files) {
          final imports = _importsIn(file);
          for (final import in imports) {
            for (final forbidden in forbiddenImports) {
              expect(
                import,
                isNot(contains(forbidden)),
                reason: '${file.path} must not import $forbidden',
              );
            }
          }
        }
      },
    );
  });

  group('Phase 1 scope guards', () {
    test('protected production wiring does not import im_core', () {
      final protectedFiles = <File>[
        File('lib/src/app/app_services.dart'),
        File('lib/src/app/bootstrap.dart'),
        File('lib/src/app/awiki_me_app.dart'),
        File('lib/src/data/gateways/awiki_anp_gateway.dart'),
        ..._dartFilesUnder('lib/src/presentation'),
      ];

      for (final file in protectedFiles) {
        expect(file.existsSync(), isTrue, reason: '${file.path} must exist');
        for (final import in _importsIn(file)) {
          expect(
            import,
            isNot(
              anyOf(
                contains('/im_core'),
                contains('src/im_core'),
                contains('../im_core'),
              ),
            ),
            reason: '${file.path} must not import Phase 1 im_core',
          );
        }
      }
    });

    test(
      'protected real Dart IM implementation files still exist and are not cut over',
      () {
        final protectedFiles = <File>[
          File('lib/src/data/gateways/awiki_anp_gateway.dart'),
          File('lib/src/data/awiki_sdk/awiki_message_client.dart'),
          File('lib/src/data/awiki_sdk/awiki_wire_mapper.dart'),
          File('lib/src/data/services/awiki_local_cache.dart'),
          File('lib/src/data/services/awiki_ws_realtime_gateway.dart'),
        ];

        for (final file in protectedFiles) {
          expect(file.existsSync(), isTrue, reason: '${file.path} must exist');
          final text = file.readAsStringSync();
          expect(
            text,
            isNot(contains('src/im_core')),
            reason: '${file.path} must not be wrapped by im_core in Phase 1',
          );
        }
      },
    );

    test(
      'Phase 1 does not add Rust, FFI, standalone package, or feature flag cutover',
      () {
        expect(File('Cargo.toml').existsSync(), isFalse);
        expect(Directory('rust').existsSync(), isFalse);
        expect(Directory('packages/awiki_im_core').existsSync(), isFalse);
        expect(
          _repoFiles((path) => path.endsWith('.rs')),
          isEmpty,
          reason: 'Phase 1 must not add Rust sources',
        );

        final imCoreText = _dartFilesUnder(
          'lib/src/im_core',
        ).map((file) => file.readAsStringSync()).join('\n');
        expect(imCoreText, isNot(contains('dart:ffi')));

        final appText = <File>[
          File('lib/src/app/app_services.dart'),
          File('lib/src/app/bootstrap.dart'),
          File('lib/src/app/awiki_me_app.dart'),
        ].map((file) => file.readAsStringSync()).join('\n');
        expect(
          appText,
          isNot(
            anyOf(
              contains('enableImCore'),
              contains('useImCore'),
              contains('imCoreEnabled'),
              contains('enableRustIm'),
              contains('useRustIm'),
              contains('rustImEnabled'),
            ),
          ),
        );
      },
    );
  });
}

List<File> _dartFilesUnder(String path) {
  final directory = Directory(path);
  if (!directory.existsSync()) {
    return const <File>[];
  }
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

List<String> _importsIn(File file) {
  final importPattern = RegExp(r'''import\s+['"]([^'"]+)['"]''');
  return importPattern
      .allMatches(file.readAsStringSync())
      .map((match) => match.group(1)!)
      .toList();
}

List<File> _repoFiles(bool Function(String path) include) {
  return Directory.current
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) => !file.path.contains(
          '${Platform.pathSeparator}.git${Platform.pathSeparator}',
        ),
      )
      .where(
        (file) => !file.path.contains(
          '${Platform.pathSeparator}.omx${Platform.pathSeparator}',
        ),
      )
      .where((file) => include(file.path))
      .toList();
}
