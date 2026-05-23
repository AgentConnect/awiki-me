import 'package:awiki_im_core/awiki_im_core.dart' as core;

class ImCoreMappedError {
  const ImCoreMappedError({
    required this.code,
    required this.message,
    this.field,
    this.statusCode,
    this.capability,
  });

  final String code;
  final String message;
  final String? field;
  final int? statusCode;
  final String? capability;

  bool get isUnsupported => code == 'unsupported_capability';
}

class AwikiImCoreErrorMapper {
  const AwikiImCoreErrorMapper();

  ImCoreMappedError map(Object error) {
    if (error is core.AwikiImCoreException) {
      return ImCoreMappedError(
        code: error.code,
        message: _sanitize(error.message),
        field: error.field,
        statusCode: error.statusCode,
        capability: error.capability,
      );
    }
    if (error is UnsupportedError) {
      return ImCoreMappedError(
        code: 'unsupported_capability',
        message: _sanitize(
          error.message ?? 'IM Core capability is not available yet',
        ),
      );
    }
    return ImCoreMappedError(
      code: 'internal',
      message: _sanitize(error.toString()),
    );
  }

  UnsupportedError unsupported(String capability) {
    return UnsupportedError('IM Core $capability is not available yet');
  }
}

String _sanitize(String input) {
  var output = input;
  final patterns = <RegExp>[
    RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    RegExp(r'Authorization:\s*[^\s,;]+', caseSensitive: false),
    RegExp(
      r'(token|jwt|private[_-]?key|signature)=([^\s,;]+)',
      caseSensitive: false,
    ),
  ];
  for (final pattern in patterns) {
    output = output.replaceAllMapped(pattern, (match) {
      final key = match.groupCount >= 1 ? match.group(1) : null;
      return key == null ? '<redacted>' : '$key=<redacted>';
    });
  }
  return output;
}
