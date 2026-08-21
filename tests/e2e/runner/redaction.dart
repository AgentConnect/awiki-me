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

  String redact(String input) {
    var output = input;
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
