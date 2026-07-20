// [INPUT]: Operator-provided OTP resolver argv and redacted SMS response metadata.
// [OUTPUT]: Strict, secret-free validation decisions for remote Join E2E only.
// [POS]: Shared runner/integration-test security contract; never a production bypass.

import 'dart:convert';

const String remoteMultiDeviceStagedOtpFlag =
    'AWIKI_MULTI_DEVICE_E2E_ALLOW_STAGED_OTP_ON_SMS_ERROR';

const List<String> reviewedStagedOtpResolverCommand = <String>[
  'ssh',
  'ali',
  '--',
  '/home/ecs-user/awiki-space/user-service/.venv/bin/python',
  '/home/ecs-user/awiki-space/user-service/scripts/issue_multi_device_test_otp.py',
  '--apply',
];

enum RemoteMultiDeviceSmsDecision { delivered, stagedAfterSmsError }

List<String> parseRemoteMultiDeviceOtpCommand(
  String encoded, {
  required bool requireReviewedStagedResolver,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(encoded);
  } on Object {
    throw const FormatException('OTP resolver command is invalid.');
  }
  if (decoded is! List ||
      decoded.isEmpty ||
      decoded.length > 32 ||
      decoded.any(
        (value) =>
            value is! String ||
            value.trim().isEmpty ||
            value.contains('\u0000') ||
            value.length > 2048,
      )) {
    throw const FormatException('OTP resolver command is invalid.');
  }
  final command = List<String>.unmodifiable(decoded.cast<String>());
  if (command.fold<int>(0, (sum, value) => sum + value.length) > 8192 ||
      command.any(_containsUnsafeCommandCharacter) ||
      command.any(_isShellExecutable)) {
    throw const FormatException('OTP resolver command is invalid.');
  }
  if (requireReviewedStagedResolver &&
      !_sameCommand(command, reviewedStagedOtpResolverCommand)) {
    throw const FormatException(
      'Staged OTP mode requires the reviewed resolver command.',
    );
  }
  return command;
}

bool parseRemoteMultiDeviceStagedOtpFlag(Map<String, String> environment) {
  final raw = environment[remoteMultiDeviceStagedOtpFlag]?.trim();
  if (raw == null || raw.isEmpty || raw == '0') {
    return false;
  }
  if (raw == '1') {
    return true;
  }
  throw const FormatException('Staged OTP mode flag must be 0 or 1.');
}

RemoteMultiDeviceSmsDecision evaluateRemoteMultiDeviceSmsResponse({
  required int statusCode,
  required String? contentType,
  required String body,
  required bool allowStagedOtpOnSmsError,
}) {
  if (statusCode == 200) {
    return RemoteMultiDeviceSmsDecision.delivered;
  }
  if (statusCode != 503 || !allowStagedOtpOnSmsError) {
    throw const FormatException('SMS code request was rejected.');
  }
  final mediaType = (contentType ?? '').split(';').first.trim().toLowerCase();
  if (mediaType != 'application/problem+json') {
    throw const FormatException('SMS error response is invalid.');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on Object {
    throw const FormatException('SMS error response is invalid.');
  }
  if (decoded is! Map ||
      decoded.keys.any((key) => key is! String) ||
      !_sameStringSet(decoded.keys.cast<String>(), const <String>{
        'type',
        'title',
        'status',
        'detail',
        'instance',
      }) ||
      decoded['type'] != 'about:blank' ||
      decoded['title'] != 'SMS Service Error' ||
      decoded['status'] is! int ||
      decoded['status'] != 503 ||
      decoded['detail'] is! String ||
      !(decoded['detail'] as String).startsWith('[SMS_ERROR]') ||
      decoded['instance'] != '/user-service/auth/sms-codes') {
    throw const FormatException('SMS error response is invalid.');
  }
  return RemoteMultiDeviceSmsDecision.stagedAfterSmsError;
}

bool isSixDigitAsciiOtp(String value) {
  if (value.length != 6) {
    return false;
  }
  return value.codeUnits.every((value) => value >= 0x30 && value <= 0x39);
}

bool _containsUnsafeCommandCharacter(String value) {
  for (final codeUnit in value.codeUnits) {
    final allowed =
        (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
        const <int>{
          0x25, // %
          0x2b, // +
          0x2c, // ,
          0x2d, // -
          0x2e, // .
          0x2f, // /
          0x3a, // :
          0x3d, // =
          0x40, // @
          0x5f, // _
        }.contains(codeUnit);
    if (!allowed) {
      return true;
    }
  }
  return false;
}

bool _isShellExecutable(String value) {
  final executable = value.replaceAll('\\', '/').split('/').last.toLowerCase();
  return const <String>{
    'sh',
    'bash',
    'zsh',
    'fish',
    'cmd',
    'cmd.exe',
    'powershell',
    'powershell.exe',
    'pwsh',
    'pwsh.exe',
  }.contains(executable);
}

bool _sameCommand(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

bool _sameStringSet(Iterable<String> values, Set<String> expected) {
  final actual = values.toSet();
  return actual.length == expected.length && actual.containsAll(expected);
}
