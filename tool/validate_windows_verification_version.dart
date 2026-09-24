import 'dart:io';

/// Windows uses three numeric product components and a fourth build component.
/// Core sends the product version on the wire and rejects prerelease suffixes.
void validateWindowsVerificationVersion(String version, String build) {
  final component = RegExp(r'^(0|[1-9][0-9]*)$');
  final parts = version.split('.');
  if (parts.length != 3 ||
      [...parts, build].any(
        (value) =>
            !component.hasMatch(value) ||
            (int.tryParse(value) ?? 65536) > 65535,
      ) ||
      build == '0') {
    throw const FormatException(
      'Use a canonical numeric x.y.z version (components 0..65535) and '
      'build 1..65535. Put test labels in the installer filename, '
      'not the product version.',
    );
  }
}

void main(List<String> args) {
  try {
    if (args.length != 2) {
      throw const FormatException('Expected VERSION BUILD arguments.');
    }
    validateWindowsVerificationVersion(args[0], args[1]);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}
