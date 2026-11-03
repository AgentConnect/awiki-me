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
    'Type APPROVE to join and configure identity management on this device: ';
const String _cliMessageOnlyConfirmationPrompt =
    'Type APPROVE to join for messaging only (no root key or management permission): ';

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

/// Normal Recovery fixture preparation only: the reviewed service exchange
/// window is 300 seconds. Never retry another error, operation, or a second 429.
/// This is E2E scheduling, not an App/Core automatic retry policy.
Duration? remoteRecoveryPrepareRetryDelay({
  required String? code,
  required int? statusCode,
  required int retries,
  required String expectedOperationId,
  required String? currentOperationId,
}) {
  if (code != 'service_error' ||
      statusCode != 429 ||
      retries != 0 ||
      expectedOperationId.isEmpty ||
      currentOperationId != expectedOperationId) {
    return null;
  }
  return const Duration(seconds: 301);
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

/// Closed observations only; never include a SAS, JSON body or terminal text.
String remoteMultiDeviceCliSasDiagnostic(List<int> transcript) {
  final text = String.fromCharCodes(transcript);
  final cleanBytes = _cliConsolePromptBytes(transcript);
  if (cleanBytes == null) return 'terminalControlInvalid=true';
  final clean = String.fromCharCodes(cleanBytes);
  try {
    final state = RegExp(
      r'"remote_state"\s*:\s*"(pending|challenge_sent|response_verified|consumed|expired|cancelled|rejected)"',
    ).firstMatch(clean)?.group(1);
    final phase = RegExp(
      r'"phase"\s*:\s*"(pending|challenge_prepared|response_prepared|response_verified|approval_prepared|authorized|cancelled|expired)"',
    ).firstMatch(clean)?.group(1);
    return 'pollPrompt=${text.contains(_cliPollSasPrefix)}, '
        'approvalPrompt=${text.contains(_cliApprovalSasPrefix)}, '
        'ansi=${transcript.contains(27)}, '
        'pollSasAfterAnsi=${remoteMultiDeviceCliPollSas(cleanBytes) != null}, '
        'approvalSasAfterAnsi=${remoteMultiDeviceCliApprovalSas(cleanBytes) != null}, '
        'sasInputPrompt=${remoteMultiDeviceCliRequestsSasInput(cleanBytes)}, '
        'confirmationPrompt=${remoteMultiDeviceCliRequestsApproval(cleanBytes) || remoteMultiDeviceCliRequestsApproval(cleanBytes, managementAllowed: false)}, '
        'remoteState=${state ?? 'unclassified'}, '
        'localPhase=${phase ?? 'unclassified'}';
  } finally {
    cleanBytes.fillRange(0, cleanBytes.length, 0);
  }
}

String? _cliSasAfterPrefix(List<int> transcript, String promptPrefix) {
  if (!transcript.contains(0x1b))
    return _cliPlainSasAfterPrefix(transcript, promptPrefix);
  final normalized = _cliConsolePromptBytes(transcript);
  if (normalized == null) return null;
  try {
    return _cliPlainSasAfterPrefix(normalized, promptPrefix);
  } finally {
    normalized.fillRange(0, normalized.length, 0);
  }
}

String? _cliPlainSasAfterPrefix(List<int> transcript, String promptPrefix) {
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
    _cliContainsConsolePrompt(transcript, _cliApprovalSasInputPrompt);

bool remoteMultiDeviceCliRequestsApproval(
  List<int> transcript, {
  bool managementAllowed = true,
}) => _cliContainsConsolePrompt(
  transcript,
  managementAllowed
      ? _cliApprovalConfirmationPrompt
      : _cliMessageOnlyConfirmationPrompt,
);

bool _cliContainsConsolePrompt(List<int> transcript, String prompt) {
  if (!transcript.contains(0x1b))
    return _indexOfBytes(transcript, prompt.codeUnits) >= 0;
  final normalized = _cliConsolePromptBytes(transcript);
  if (normalized == null) return false;
  try {
    return _indexOfBytes(normalized, prompt.codeUnits) >= 0;
  } finally {
    normalized.fillRange(0, normalized.length, 0);
  }
}

// ConPTY 可将提示行空格编码为 CSI n C；仅删除控制序列会把可见空格丢掉。
// 只投影有界提示文本，缓冲使用后擦除，不持久化终端内容或 SAS。
List<int>? _cliConsolePromptBytes(List<int> transcript) {
  const maximum = 1024 * 1024;
  if (transcript.length > maximum) return null;
  final result = <int>[];
  for (var index = 0; index < transcript.length; index++) {
    if (transcript[index] == 0x1b &&
        index + 1 < transcript.length &&
        transcript[index + 1] == 0x5d) {
      // Windows 可在两次写入之间插入 OSC 标题；标题不能成为可见提示的一部分。
      var end = index + 2;
      while (end < transcript.length &&
          transcript[end] != 0x07 &&
          !(transcript[end] == 0x1b &&
              end + 1 < transcript.length &&
              transcript[end + 1] == 0x5c)) {
        end++;
      }
      if (end == transcript.length) {
        result.fillRange(0, result.length, 0);
        return null;
      }
      index = transcript[end] == 0x07 ? end : end + 1;
      continue;
    }
    if (transcript[index] == 0x1b &&
        index + 1 < transcript.length &&
        transcript[index + 1] == 0x5b) {
      var end = index + 2;
      while (end < transcript.length &&
          (transcript[end] < 0x40 || transcript[end] > 0x7e)) {
        if (transcript[end] < 0x20 || transcript[end] > 0x3f) {
          result.fillRange(0, result.length, 0);
          return null;
        }
        end++;
      }
      if (end == transcript.length) {
        result.fillRange(0, result.length, 0);
        return null;
      }
      if (transcript[end] == 0x43) {
        var columns = end == index + 2 ? 1 : 0;
        for (var digit = index + 2; digit < end; digit++) {
          final value = transcript[digit] - 0x30;
          if (value < 0 || value > 9 || columns > 160) {
            result.fillRange(0, result.length, 0);
            return null;
          }
          columns = columns * 10 + value;
        }
        if (columns < 1 || columns > 160 || result.length + columns > maximum) {
          result.fillRange(0, result.length, 0);
          return null;
        }
        result.addAll(List<int>.filled(columns, 0x20));
      }
      index = end;
      continue;
    }
    if (result.length == maximum) {
      result.fillRange(0, result.length, 0);
      return null;
    }
    result.add(transcript[index]);
  }
  return result;
}

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
