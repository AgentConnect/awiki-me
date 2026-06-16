import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IM Core migration boundary', () {
    test('legacy Dart-only lib/src/im_core contract has been removed', () {
      expect(
        Directory('lib/src/im_core').existsSync(),
        isFalse,
        reason:
            'Rust SDK adapters under lib/src/data/im_core are now the only IM Core boundary.',
      );
    });

    test('old hand-written IM/account/realtime production files are removed', () {
      final removedFiles = <String>[
        'lib/src/data/gateways/awiki_anp_gateway.dart',
        'lib/src/data/services/awiki_account_service.dart',
        'lib/src/data/services/awiki_ws_realtime_gateway.dart',
        'lib/src/data/services/awiki_ws_channel_connector.dart',
        'lib/src/data/services/awiki_ws_channel_connector_io.dart',
        'lib/src/data/services/awiki_local_cache.dart',
        'lib/src/data/services/awiki_local_store.dart',
        'lib/src/data/services/dart_did_registration_facade.dart',
        'lib/src/domain/services/did_registration_facade.dart',
      ];

      for (final path in removedFiles) {
        expect(File(path).existsSync(), isFalse, reason: '$path is legacy');
      }
      expect(
        Directory('lib/src/data/awiki_sdk').existsSync(),
        isFalse,
        reason:
            'old app-side ANP/IM SDK helpers must not remain as a production fallback',
      );
    });

    test(
      'UI/domain layers do not import legacy im_core or Rust SDK adapters',
      () {
        final protectedFiles = <File>[
          File('lib/src/app/awiki_me_app.dart'),
          ..._dartFilesUnder('lib/src/domain'),
          ..._dartFilesUnder('lib/src/presentation'),
        ];

        for (final file in protectedFiles) {
          expect(file.existsSync(), isTrue, reason: '${file.path} must exist');
          for (final import in _importsIn(file)) {
            expect(
              import,
              isNot(
                anyOf(
                  startsWith('package:awiki_im_core/'),
                  startsWith('package:awiki_me/src/data/im_core/'),
                  contains('/src/data/im_core/'),
                  contains('../data/im_core/'),
                  startsWith('package:awiki_me/src/im_core/'),
                  contains('../im_core/'),
                ),
              ),
              reason:
                  '${file.path} must depend on application services, not SDK/adapter internals',
            );
          }
        }
      },
    );

    test(
      'only Rust SDK adapter production files import package:awiki_im_core',
      () {
        final productionFiles = _dartFilesUnder('lib/src');

        for (final file in productionFiles) {
          for (final import in _importsIn(file)) {
            if (!import.startsWith('package:awiki_im_core/')) {
              continue;
            }

            expect(
              file.path,
              startsWith('lib/src/data/im_core/'),
              reason:
                  '${file.path} must not import the Rust SDK outside the adapter layer',
            );
            expect(
              import,
              'package:awiki_im_core/awiki_im_core.dart',
              reason: '${file.path} must use the public SDK barrel only',
            );
            expect(
              _importStatementFor(file, import),
              contains(' as core'),
              reason: '${file.path} must alias the SDK import as core',
            );
          }
        }
      },
    );

    test(
      'production code does not keep raw IM/ANP/WebSocket fallback imports',
      () {
        final productionFiles = _dartFilesUnder('lib/src');

        for (final file in productionFiles) {
          final text = file.readAsStringSync();
          expect(
            text,
            isNot(
              anyOf(<Matcher>[
                contains("package:anp/"),
                contains("package:web_socket_channel/"),
                contains("package:archive/"),
                contains('AwikiAnpGateway'),
                contains('AwikiAccountService'),
                contains('AwikiWsRealtimeGateway'),
                contains('AwikiMessageClient'),
                contains('AwikiAnpProofBuilder'),
              ]),
            ),
            reason:
                '${file.path} must not keep old IM production fallback code',
          );
        }
      },
    );

    test(
      'awiki-me does not add Rust sources, local FFI package, or feature flag cutover',
      () {
        expect(File('Cargo.toml').existsSync(), isFalse);
        expect(Directory('rust').existsSync(), isFalse);
        expect(Directory('packages/awiki_im_core').existsSync(), isFalse);
        expect(
          _repoFiles((path) => path.endsWith('.rs')),
          isEmpty,
          reason: 'awiki-me must not add Rust sources',
        );

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

String _importStatementFor(File file, String import) {
  final pattern = RegExp(
    '''import\\s+['"]${RegExp.escape(import)}['"][^;]*;''',
  );
  return pattern.firstMatch(file.readAsStringSync())?.group(0) ?? '';
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
