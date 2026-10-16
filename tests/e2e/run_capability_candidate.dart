/// Focused native acceptance using production bootstrap and a real CLI peer.
/// This does not replace the complete product catalog or other platform lanes.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  const required = {'run-root', 'cli', 'tenant-config'};
  final args = <String, String>{};
  if (arguments.length != 6) {
    throw ArgumentError(
      'Required: --run-root PATH --cli PATH --tenant-config PATH',
    );
  }
  for (var i = 0; i < arguments.length; i += 2) {
    final option = arguments[i];
    if (!option.startsWith('--') ||
        !required.contains(option.substring(2)) ||
        args.containsKey(option.substring(2))) {
      throw ArgumentError('Unknown or duplicate argument: $option');
    }
    args[option.substring(2)] = arguments[i + 1];
  }
  if (!Platform.isMacOS) {
    throw UnsupportedError('This focused candidate lane requires native macOS');
  }
  final root = Directory(args['run-root']!).absolute;
  if (await FileSystemEntity.type(root.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError('Use a fresh isolated run root');
  }
  final catalog = await File(args['tenant-config']!).readAsBytes();
  final values = jsonDecode(utf8.decode(catalog)) as Map<String, dynamic>;
  final tenants = values['tenants'] as Map<String, dynamic>;
  final origins = tenants.values.map((e) => e['backend_origin']).toSet();
  const allowed = {
    'https://openserver-adapt.anpclaw.com',
    'https://backend-adapt.anpclaw.com',
  };
  if (origins.length != allowed.length || !origins.containsAll(allowed)) {
    throw StateError('Only the two isolated task candidates are allowed');
  }
  final cli = await File(args['cli']!).resolveSymbolicLinks();
  await root.create(recursive: true);
  if ((await Process.run('chmod', ['700', root.path])).exitCode != 0) {
    throw StateError('Cannot protect the isolated run root');
  }
  final fixture = File('${root.path}/fixture.json');
  await fixture.writeAsString(
    jsonEncode({
      'runRoot': '${root.path}/state',
      'cli': cli,
      'origin': 'https://openserver-adapt.anpclaw.com',
    }),
  );
  if ((await Process.run('chmod', ['600', fixture.path])).exitCode != 0) {
    throw StateError('Cannot protect the fixture');
  }
  final config = File('${root.path}/Candidate.xcconfig');
  await config.writeAsString('''
AWIKI_MACOS_DEV_BUNDLE_ID = ai.awiki.awikime.dev.capability.e2e
AWIKI_APP_DISPLAY_NAME = AWiki Capability E2E
MACOSX_DEPLOYMENT_TARGET = 15.0
''');
  final catalogHash = sha256.convert(catalog).toString();
  final process = await Process.start(
    'flutter',
    [
      'test',
      '--no-pub',
      '-d',
      'macos',
      'integration_test/backend_capabilities_test.dart',
      '--dart-define=AWIKI_E2E=true',
      '--dart-define=AWIKI_CAPABILITY_FIXTURE=${fixture.path}',
      '--dart-define=AWIKI_BUILTIN_TENANTS_BASE64=${base64Encode(catalog)}',
      '--dart-define=AWIKI_BUILTIN_TENANTS_SHA256=$catalogHash',
    ],
    environment: {'XCODE_XCCONFIG_FILE': config.path},
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  await File('${root.path}/invocation.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'exit_code': code,
      'normal_app_bootstrap': true,
      'authentication_override': false,
      'test_ui_semantics': true,
      'manual_state': 'untouched',
      'tenant_config_sha256': catalogHash,
    }),
  );
  exitCode = code;
}
