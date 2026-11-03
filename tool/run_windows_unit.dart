// Native Windows unit entrypoint. Stage only SQLite, never an older App Core DLL.
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'ensure_windows_im_core.dart' show windowsFileSha256, windowsPeMachine;

Future<void> main(List<String> args) async {
  try {
    if (!Platform.isWindows) throw StateError('Native Windows is required.');
    final separator = args.indexOf('--');
    if (separator != 1 ||
        !args.first.startsWith('--sqlite-dll=') ||
        separator == args.length - 1) {
      throw ArgumentError(
        'Use --sqlite-dll=<built App bundle/sqlite3.dll> -- <flutter test arguments>.',
      );
    }
    final root = Directory.current.absolute;
    if (!File(
      p.join(root.path, 'pubspec.yaml'),
    ).readAsStringSync().contains('name: awiki_me')) {
      throw StateError('Run from the awiki-me project.');
    }
    final source = File(
      p.absolute(args.first.substring('--sqlite-dll='.length)),
    );
    if (!source.existsSync() ||
        windowsPeMachine(await source.readAsBytes()) != 0x8664) {
      throw StateError('A built Windows x64 SQLite DLL is required.');
    }
    final hash = await windowsFileSha256(source);
    final directory = Directory(
      p.join(root.path, '.e2e', 'windows-unit-deps', 'sqlite3', hash),
    );
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, 'sqlite3.dll'));
    if (!target.existsSync()) await source.copy(target.path);
    if (await windowsFileSha256(target) != hash)
      throw StateError('SQLite artifact hash mismatch.');
    final configured = Platform.environment['FLUTTER_ROOT'];
    final cache = configured != null && configured.isNotEmpty
        ? Directory(p.join(configured, 'bin', 'cache'))
        : File(Platform.resolvedExecutable).parent.parent.parent;
    final flutterTool = File(p.join(cache.path, 'flutter_tools.snapshot'));
    if (!flutterTool.existsSync())
      throw StateError('Use Flutter bundled Dart or set FLUTTER_ROOT.');
    final dart = File(p.join(cache.path, 'dart-sdk', 'bin', 'dart.exe'));
    if (!dart.existsSync())
      throw StateError('Flutter Dart executable is unavailable.');
    final proof = <String, Object?>{
      'schemaVersion': 1,
      'platform': 'windows-x64',
      'sqliteSha256': hash,
      'sqliteBytes': await target.length(),
      'machine': '8664',
      'pubspecLockSha256': await windowsFileSha256(
        File(p.join(root.path, 'pubspec.lock')),
      ),
      'sourceIsInProject': p.isWithin(root.path, source.path),
      'onlySqliteStaged': true,
    };
    await File(
      p.join(directory.path, 'provenance.json'),
    ).writeAsString(jsonEncode(proof));
    stdout.writeln(jsonEncode(proof));
    final environment = <String, String>{
      ...Platform.environment,
      'FLUTTER_ROOT': cache.parent.parent.path,
      'PATH': '${directory.path};${Platform.environment['PATH'] ?? ''}',
    };
    // Bypass flutter.bat so regex metacharacters remain one argv value.
    final process = await Process.start(
      dart.path,
      [flutterTool.path, 'test', ...args.skip(separator + 1)],
      environment: environment,
      includeParentEnvironment: false,
      workingDirectory: root.path,
    );
    await process.stdin.close();
    final output = Future.wait([
      stdout.addStream(process.stdout),
      stderr.addStream(process.stderr),
    ]);
    exitCode = await process.exitCode;
    await output;
  } on Object catch (error) {
    stderr.writeln('Windows unit preparation failed (${error.runtimeType}).');
    exitCode = 2;
  }
}
