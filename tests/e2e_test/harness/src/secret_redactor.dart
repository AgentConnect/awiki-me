final class SecretRedactor {
  const SecretRedactor();

  String redact(String input) {
    var output = input;
    for (final rule in _rules) {
      output = output.replaceAllMapped(rule.pattern, rule.replacement);
    }
    return output;
  }

  Object? redactJson(Object? value) {
    if (value is String) {
      return redact(value);
    }
    if (value is List) {
      return value.map(redactJson).toList(growable: false);
    }
    if (value is Map) {
      return value.map((key, nested) {
        final keyText = key.toString();
        if (_sensitiveJsonKey(keyText)) {
          return MapEntry(keyText, _placeholderForKey(keyText));
        }
        return MapEntry(keyText, redactJson(nested));
      });
    }
    return value;
  }
}

final class _RedactionRule {
  const _RedactionRule(this.pattern, this.replacement);

  final RegExp pattern;
  final String Function(Match match) replacement;
}

final _rules = <_RedactionRule>[
  _RedactionRule(
    RegExp(
      r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----',
      multiLine: true,
    ),
    (_) => '<REDACTED_PRIVATE_KEY>',
  ),
  _RedactionRule(
    RegExp(r'(bearer\s+)([A-Za-z0-9._~+\-/=]{12,})', caseSensitive: false),
    (match) => '${match.group(1)}<REDACTED_TOKEN>',
  ),
  _RedactionRule(
    RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'),
    (_) => '<REDACTED_JWT>',
  ),
  _RedactionRule(
    RegExp(
      r'("?(?:access_token|refresh_token|runtime_registration_token|runtime_rpc_token|runtime_token|token|jwt)"?\s*[:=]\s*"?)([^"<\s,}]{6,})',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}<REDACTED_TOKEN>',
  ),
  _RedactionRule(
    RegExp(
      r'("?(?:private_key_pem|private_key_multibase|private_key|daemon_subkey_private_package)"?\s*[:=]\s*"?)([^"<\n,}]{3,})',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}<REDACTED_PRIVATE_KEY>',
  ),
  _RedactionRule(
    RegExp(
      r'(\b(?:otp|code|verification_code)\b\s*[:=]\s*"?)(\d{4,8})',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}<REDACTED_OTP>',
  ),
  _RedactionRule(
    RegExp(
      r'(--(?:otp|code|verification-code)\s+)(\d{4,8})',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}<REDACTED_OTP>',
  ),
  _RedactionRule(
    RegExp(
      r'(--(?:token|jwt|runtime-token)\s+)([^<\s]{6,})',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}<REDACTED_TOKEN>',
  ),
  _RedactionRule(RegExp(r'\+\d{8,15}'), (_) => '<REDACTED_PHONE>'),
];

bool _sensitiveJsonKey(String key) {
  final normalized = key.toLowerCase();
  return normalized.contains('private_key') ||
      normalized.contains('subkey_private') ||
      normalized == 'token' ||
      normalized.endsWith('_token') ||
      normalized == 'jwt' ||
      normalized == 'otp' ||
      normalized == 'otp_code' ||
      normalized == 'verification_code' ||
      normalized == 'phone';
}

String _placeholderForKey(String key) {
  final normalized = key.toLowerCase();
  if (normalized.contains('private') || normalized.contains('subkey')) {
    return '<REDACTED_PRIVATE_KEY>';
  }
  if (normalized == 'otp' ||
      normalized == 'otp_code' ||
      normalized == 'verification_code') {
    return '<REDACTED_OTP>';
  }
  if (normalized == 'phone') {
    return '<REDACTED_PHONE>';
  }
  return '<REDACTED_TOKEN>';
}
