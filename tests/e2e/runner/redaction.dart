// [INPUT]: Known runtime secrets and untrusted runner/driver diagnostics.
// [OUTPUT]: Bounded diagnostics without credentials, full DIDs, or six-digit OTPs.
// [POS]: Shared reporting security boundary; contains no execution behavior.

class DesktopSecretRedactor {
  DesktopSecretRedactor(Iterable<String> secrets)
    : _secrets =
          secrets
              .where((secret) => secret.trim().isNotEmpty)
              .map((secret) => secret.trim())
              .toSet()
              .toList()
            ..sort((a, b) => b.length.compareTo(a.length));

  final List<String> _secrets;

  void addSecret(String secret) {
    final value = secret.trim();
    if (value.isEmpty || _secrets.contains(value)) {
      return;
    }
    _secrets.add(value);
    _secrets.sort((a, b) => b.length.compareTo(a.length));
  }

  static final _paddedLocalAuth = RegExp(
    r'((?:https?|wss?)://(?:127\.0\.0\.1|localhost|\[::1\]):[0-9]{1,5}/)([A-Za-z0-9_-]{8,}={1,2})(?![A-Za-z0-9_=-])',
    caseSensitive: false,
  );
  static final _localWebSocketAuth = RegExp(
    r'((?:https?|wss?)://(?:127\.0\.0\.1|localhost|\[::1\]):[0-9]{1,5}/)([A-Za-z0-9_-]{8,}={0,2})(?=/ws(?:[/\s?#]|$))',
    caseSensitive: false,
  );
  static final _vmBannerAuth = RegExp(
    r'(Dart VM service is listening on (?:https?|wss?)://(?:127\.0\.0\.1|localhost|\[::1\]):[0-9]{1,5}/)([A-Za-z0-9_-]{8,}={0,2})(?![A-Za-z0-9_=-])',
    caseSensitive: false,
  );

  String redact(String input) {
    // Dynamic VM authentication paths are unknown to the fixture secret list.
    // Remove them before a known value can split an otherwise matching URL.
    var output = input;
    for (final pattern in [
      _paddedLocalAuth,
      _localWebSocketAuth,
      _vmBannerAuth,
    ]) {
      output = output.replaceAllMapped(
        pattern,
        (match) => '${match.group(1)}<redacted-local-auth>',
      );
    }
    for (final secret in _secrets) {
      output = output.replaceAll(secret, '<redacted>');
    }
    output = output.replaceAll(
      RegExp(
        r'(otp|token|jwt|private[_-]?key|secret|authorization)=([^\s]+)',
        caseSensitive: false,
      ),
      '<redacted-key>=<redacted>',
    );
    output = output.replaceAllMapped(
      RegExp(r'(--otp|--phone)\s+([^\s]+)', caseSensitive: false),
      (match) => '${match.group(1)} <redacted>',
    );
    output = output.replaceAll(
      RegExp(r'did:[A-Za-z0-9._%~/-]+(?::[A-Za-z0-9._%~/-]+)+'),
      '<redacted-did>',
    );
    return output;
  }
}

String sanitizeAppPairDriverDiagnostic(
  String input,
  DesktopSecretRedactor redactor,
) {
  return redactor
      .redact(input)
      .replaceAll(
        RegExp(r'(?<![0-9])[0-9]{6}(?![0-9])'),
        '<redacted-six-digit>',
      );
}

/// Values the registration provisioner must keep out of runner diagnostics.
Iterable<String> registrationFixtureSecrets(
  Map<String, dynamic> fixture,
) sync* {
  for (final key in const [
    'inviteCode',
    'phone',
    'otp',
    'handle',
    'fourCharHandle',
    'fourCharInviteCode',
    'emailHandle',
    'emailInviteCode',
    'email',
  ]) {
    final value = fixture[key];
    if (value is String) yield value;
  }
  final caBundle = fixture['caBundle'];
  if (caBundle is String) yield caBundle;
}
