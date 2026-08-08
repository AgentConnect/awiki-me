// [INPUT]: Retry-After metadata and in-memory output from real foreground CLI
//          poll/approval processes.
// [OUTPUT]: Bounded retry timing, fixed-OTP shape validation, and exact CLI SAS
//           prompt recognition for remote Join E2E only.
// [POS]: Shared runner/integration-test contract. The fixed test OTP is loaded
//        only from the ignored protected runner configuration.

const String _cliPollSasPrefix = "This device's one-time SAS: ";
const String _cliApprovalSasPrefix =
    'Compare this one-time SAS with the new device: ';
const String _cliApprovalSasInputPrompt =
    'Type the same 6-digit SAS to continue: ';
const String _cliApprovalConfirmationPrompt =
    'Type APPROVE to confirm local user presence and authorize this device: ';

Duration remoteMultiDeviceOtpRetryDelay(String? retryAfter) {
  final parsed = int.tryParse(retryAfter?.trim() ?? '');
  final seconds = parsed == null || parsed < 1 || parsed > 300 ? 60 : parsed;
  return Duration(seconds: seconds + 1);
}

Duration remoteHandleRecoveryPhoneCooldownDelay({
  required DateTime retryAt,
  required DateTime now,
}) {
  final remaining = retryAt.toUtc().difference(now.toUtc());
  if (remaining <= Duration.zero) {
    return Duration.zero;
  }
  if (remaining > const Duration(seconds: 90)) {
    throw const FormatException(
      'Handle Recovery phone cooldown exceeds the bounded E2E window.',
    );
  }
  return remaining + const Duration(seconds: 1);
}

bool isSixDigitAsciiOtp(String value) {
  if (value.length != 6) {
    return false;
  }
  return value.codeUnits.every((value) => value >= 0x30 && value <= 0x39);
}

/// Extracts the locally derived SAS only from the production CLI's exact
/// foreground prompt. Callers must keep the transcript in memory and erase it
/// after the child process exits; this helper never renders or persists it.
String? remoteMultiDeviceCliPollSas(List<int> transcript) =>
    _cliSasAfterPrefix(transcript, _cliPollSasPrefix);

String? remoteMultiDeviceCliApprovalSas(List<int> transcript) =>
    _cliSasAfterPrefix(transcript, _cliApprovalSasPrefix);

String? _cliSasAfterPrefix(List<int> transcript, String promptPrefix) {
  final prefix = promptPrefix.codeUnits;
  final offset = _indexOfBytes(transcript, prefix);
  if (offset < 0) {
    return null;
  }
  final sasStart = offset + prefix.length;
  final sasEnd = sasStart + 6;
  if (sasEnd > transcript.length) {
    return null;
  }
  final sasBytes = transcript.sublist(sasStart, sasEnd);
  if (sasBytes.any((value) => value < 0x30 || value > 0x39)) {
    return null;
  }
  if (sasEnd == transcript.length ||
      (transcript[sasEnd] != 0x0a && transcript[sasEnd] != 0x0d)) {
    return null;
  }
  return String.fromCharCodes(sasBytes);
}

bool remoteMultiDeviceCliRequestsSasInput(List<int> transcript) =>
    _indexOfBytes(transcript, _cliApprovalSasInputPrompt.codeUnits) >= 0;

bool remoteMultiDeviceCliRequestsApproval(List<int> transcript) =>
    _indexOfBytes(transcript, _cliApprovalConfirmationPrompt.codeUnits) >= 0;

int _indexOfBytes(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) {
    return -1;
  }
  final last = haystack.length - needle.length;
  for (var start = 0; start <= last; start += 1) {
    var matches = true;
    for (var index = 0; index < needle.length; index += 1) {
      if (haystack[start + index] != needle[index]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return start;
    }
  }
  return -1;
}
