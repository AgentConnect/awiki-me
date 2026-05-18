enum ImErrorCode {
  unauthenticated,
  sessionExpired,
  permissionDenied,
  targetRequired,
  groupRequired,
  messageTextRequired,
  attachmentRequired,
  messageNotFound,
  attachmentNotFound,
  transportUnavailable,
  connectionFailed,
  rpcRejected,
  unsupported,
  notReady,
  featureDisabled,
  storeCorrupt,
  migrationRequired,
  internal,
}

class ImErrorDto {
  const ImErrorDto({
    required this.code,
    required this.message,
    this.hint,
    required this.retryable,
    this.details = const <String, Object?>{},
  });

  final ImErrorCode code;
  final String message;
  final String? hint;
  final bool retryable;
  final Map<String, Object?> details;
}

class ImWarningDto {
  const ImWarningDto({
    required this.code,
    required this.message,
    this.hint,
    this.details = const <String, Object?>{},
  });

  final String code;
  final String message;
  final String? hint;
  final Map<String, Object?> details;
}

class ImException implements Exception {
  const ImException(this.error);

  final ImErrorDto error;

  @override
  String toString() => 'ImException(${error.code.name}: ${error.message})';
}

ImException imException(
  ImErrorCode code,
  String message, {
  String? hint,
  bool retryable = false,
  Map<String, Object?> details = const <String, Object?>{},
}) {
  return ImException(
    ImErrorDto(
      code: code,
      message: message,
      hint: hint,
      retryable: retryable,
      details: details,
    ),
  );
}
