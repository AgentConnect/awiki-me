enum AppErrorKind {
  authentication,
  didNotFoundOrRevoked,
  networkUnavailable,
  timeout,
  other,
}

AppErrorKind classifyAppError(Object error) {
  final raw = normalizeAppError(error);
  if (raw.isEmpty) {
    return AppErrorKind.other;
  }
  if (isAuthenticationErrorText(raw)) {
    return AppErrorKind.authentication;
  }
  if (isDidNotFoundOrRevokedText(raw)) {
    return AppErrorKind.didNotFoundOrRevoked;
  }
  if (isTimeoutErrorText(raw)) {
    return AppErrorKind.timeout;
  }
  if (isNetworkUnavailableText(raw)) {
    return AppErrorKind.networkUnavailable;
  }
  return AppErrorKind.other;
}

bool isTransientNetworkAppError(Object error) {
  final kind = classifyAppError(error);
  return kind == AppErrorKind.networkUnavailable ||
      kind == AppErrorKind.timeout;
}

String normalizeAppError(Object error) {
  final raw = error.toString().trim();
  if (raw.startsWith('Exception: ')) {
    return raw.substring('Exception: '.length);
  }
  if (raw.startsWith('StateError: ')) {
    return raw.substring('StateError: '.length);
  }
  if (raw.startsWith('Unsupported operation: ')) {
    return raw.substring('Unsupported operation: '.length);
  }
  if (raw.startsWith('UnsupportedError: ')) {
    return raw.substring('UnsupportedError: '.length);
  }
  if (raw.startsWith('ArgumentError: ')) {
    return raw.substring('ArgumentError: '.length);
  }
  if (raw.startsWith('Bad state: ')) {
    return raw.substring('Bad state: '.length);
  }
  return raw;
}

bool isAuthenticationErrorText(String raw) {
  final normalized = raw.toLowerCase();
  final compact = normalized.replaceAll(RegExp(r'\s+'), '');
  return normalized.contains('missing or invalid authorization header') ||
      normalized.contains('missing authentication headers') ||
      compact.contains('http401') ||
      normalized.contains('invalid token') ||
      normalized.contains('empty token') ||
      normalized.contains('token expired') ||
      normalized.contains('session expired') ||
      normalized.contains('unauthenticated') ||
      normalized.contains('current user did is required') ||
      normalized.contains('current user did is not bound') ||
      normalized.contains('controller_scope_mismatch');
}

bool isDidNotFoundOrRevokedText(String raw) {
  final normalized = raw.toLowerCase();
  final compact = normalized.replaceAll(RegExp(r'\s+'), '');
  return compact.contains('didnotfoundorrevoked') ||
      (normalized.contains('did not found') &&
          normalized.contains('revoked')) ||
      (normalized.contains('did not exist') && normalized.contains('revoked'));
}

bool isTimeoutErrorText(String raw) {
  final normalized = raw.toLowerCase();
  return normalized.contains('timeoutexception') ||
      normalized.contains('timed out') ||
      normalized.contains('timeout') ||
      normalized.contains('operation timed out');
}

bool isNetworkUnavailableText(String raw) {
  final normalized = raw.toLowerCase();
  return normalized.contains('transport_unavailable') ||
      normalized.contains('transport unavailable') ||
      normalized.contains('error sending request for url') ||
      normalized.contains('socketexception') ||
      normalized.contains('clientexception') ||
      normalized.contains('failed host lookup') ||
      normalized.contains('no address associated with hostname') ||
      normalized.contains('connection refused') ||
      normalized.contains('connection reset') ||
      normalized.contains('connection reset by peer') ||
      normalized.contains('connection closed') ||
      normalized.contains('connection aborted') ||
      normalized.contains('network is unreachable') ||
      normalized.contains('network unreachable') ||
      normalized.contains('host is unreachable') ||
      normalized.contains('connection failed') ||
      normalized.contains('proxy connection failed') ||
      normalized.contains('proxy error') ||
      normalized.contains('tls error') ||
      normalized.contains('handshake error') ||
      normalized.contains('handshakeexception') ||
      normalized.contains('certificate verify failed');
}
