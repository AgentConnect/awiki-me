import 'dart:convert';
import 'dart:io';

bool isTestBuildDefine(String key) =>
    key.startsWith('AWIKI_E2E') ||
    key.contains('_E2E_') ||
    key == 'AWIKI_MULTI_DEVICE_APP_PAIR_ROLE' ||
    key == 'AWIKI_MANUAL_APP_STATE_ROOT';

void verifyReleaseTestIsolation(
  Map<String, String> environment, {
  List<String> arguments = const [],
}) {
  if (environment.entries.any(
    (e) => isTestBuildDefine(e.key) && e.value.isNotEmpty,
  )) {
    throw const FormatException(
      'Release packaging rejects test environment settings.',
    );
  }
  final target = environment['FLUTTER_TARGET'];
  if (target != null && target.isNotEmpty && target != 'lib/main.dart') {
    throw const FormatException(
      'Release packaging requires the normal product entrypoint.',
    );
  }
  for (final argument in arguments) {
    if (argument.startsWith('--dart-define-from-file') ||
        argument.startsWith('--target') ||
        (argument.startsWith('--dart-define=') &&
            isTestBuildDefine(argument.substring(14).split('=').first))) {
      throw const FormatException(
        'Release packaging rejects test build arguments.',
      );
    }
  }
  final encoded = environment['DART_DEFINES'];
  if (encoded != null && encoded.isNotEmpty) {
    try {
      for (final item in encoded.split(',')) {
        final define = utf8.decode(base64Decode(base64.normalize(item)));
        if (!define.contains('=') ||
            isTestBuildDefine(define.split('=').first)) {
          throw const FormatException('Forbidden define.');
        }
      }
    } on FormatException {
      throw const FormatException(
        'Release packaging rejects invalid or test DART_DEFINES.',
      );
    }
  }
}

void main(List<String> arguments) {
  try {
    verifyReleaseTestIsolation(Platform.environment, arguments: arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  }
}
