// [INPUT]: Operator-provided OTP resolver argv and redacted SMS response metadata.
// [OUTPUT]: Strict, secret-free validation and resolver-continuation decisions
//           for the deployed Globe remote Join E2E path only.
// [POS]: Shared runner/integration-test security gate; rejects provider drift,
//        extra markers, and secret-like details before invoking the resolver.

import 'dart:convert';

const String remoteMultiDeviceStagedOtpFlag =
    'AWIKI_MULTI_DEVICE_E2E_ALLOW_STAGED_OTP_ON_SMS_ERROR';
const String _stagedSmsProviderCode = 'MOBILE_NUMBER_ILLEGAL';

final RegExp _stagedSmsDetailPattern = RegExp(
  r'^\[SMS_ERROR\] Globe SMS send failed: '
  r'\[([A-Z][A-Z0-9_]*)\] ([^\r\n]{1,256})$',
);
final RegExp _stagedSmsMarkerPattern = RegExp(r'\[[A-Z][A-Z0-9_]*\]');
final RegExp _stagedSmsSecretWordPattern = RegExp(
  r'\b(?:otp|token|secret|password|authorization)\b',
  caseSensitive: false,
);
final RegExp _stagedSmsDigitRunPattern = RegExp(r'[0-9]+');

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
  if (contentType != 'application/problem+json') {
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
      decoded['instance'] != '/user-service/auth/sms-codes') {
    throw const FormatException('SMS error response is invalid.');
  }
  final detail = decoded['detail'] as String;
  final match = _stagedSmsDetailPattern.firstMatch(detail);
  if (match == null ||
      match.group(0) != detail ||
      match.group(1) != _stagedSmsProviderCode ||
      !_hasExactStagedSmsMarkers(detail) ||
      !_isSafeStagedSmsProviderMessage(match.group(2)!)) {
    throw const FormatException('SMS error response is invalid.');
  }
  return RemoteMultiDeviceSmsDecision.stagedAfterSmsError;
}

T continueRemoteMultiDeviceOtpAfterSmsResponse<T>({
  required int statusCode,
  required String? contentType,
  required String body,
  required bool allowStagedOtpOnSmsError,
  required T Function() resolveOtp,
}) {
  evaluateRemoteMultiDeviceSmsResponse(
    statusCode: statusCode,
    contentType: contentType,
    body: body,
    allowStagedOtpOnSmsError: allowStagedOtpOnSmsError,
  );
  return resolveOtp();
}

bool isSixDigitAsciiOtp(String value) {
  if (value.length != 6) {
    return false;
  }
  return value.codeUnits.every((value) => value >= 0x30 && value <= 0x39);
}

bool _hasExactStagedSmsMarkers(String detail) {
  final markers = _stagedSmsMarkerPattern
      .allMatches(detail)
      .map((match) => match.group(0))
      .toList(growable: false);
  return markers.length == 2 &&
      markers[0] == '[SMS_ERROR]' &&
      markers[1] == '[$_stagedSmsProviderCode]';
}

bool _isSafeStagedSmsProviderMessage(String message) {
  if (message != message.trim() ||
      _stagedSmsSecretWordPattern.hasMatch(message)) {
    return false;
  }
  return !_stagedSmsDigitRunPattern
      .allMatches(message)
      .any((match) => match.group(0)!.length == 6);
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
