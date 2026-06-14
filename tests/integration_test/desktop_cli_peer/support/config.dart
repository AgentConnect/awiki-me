part of '../desktop_cli_peer_e2e.dart';

class _DesktopCliPeerSmokeConfig {
  const _DesktopCliPeerSmokeConfig({
    required this.runId,
    required this.platform,
    required this.appHandle,
    required this.cliHandle,
    required this.otpPhone,
    required this.otpCode,
    required this.cliBin,
    required this.cliWorkspace,
    required this.cliHome,
  });

  factory _DesktopCliPeerSmokeConfig.fromEnvironment() {
    return _DesktopCliPeerSmokeConfig(
      runId: _requiredDefine('AWIKI_E2E_RUN_ID', _runId),
      platform: _requiredDefine('AWIKI_E2E_PLATFORM', _platform),
      appHandle: _requiredDefine('AWIKI_E2E_APP_HANDLE', _appHandle),
      cliHandle: _requiredDefine('AWIKI_E2E_CLI_HANDLE', _cliHandle),
      otpPhone: _requiredDefine('DEV_OTP_PHONE', _otpPhone),
      otpCode: _requiredDefine('DEV_OTP_CODE', _otpCode),
      cliBin: _requiredDefine('AWIKI_CLI_BIN', _cliBin),
      cliWorkspace: _requiredDefine(
        'AWIKI_CLI_WORKSPACE_HOME_DIR',
        _cliWorkspace,
      ),
      cliHome: _requiredDefine('AWIKI_CLI_HOME_DIR', _cliHome),
    );
  }

  final String runId;
  final String platform;
  final String appHandle;
  final String cliHandle;
  final String otpPhone;
  final String otpCode;
  final String cliBin;
  final String cliWorkspace;
  final String cliHome;
}

class _AppIdentityAttempt {
  const _AppIdentityAttempt._({this.session, required this.errorText});

  factory _AppIdentityAttempt.session(AppSession session) {
    return _AppIdentityAttempt._(session: session, errorText: '');
  }

  factory _AppIdentityAttempt.error(String errorText) {
    return _AppIdentityAttempt._(errorText: errorText);
  }

  final AppSession? session;
  final String errorText;
}

String _requiredDefine(String name, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw StateError('$name is required for Desktop CLI peer E2E.');
  }
  return trimmed;
}

String _messageNonce() {
  final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
  return micros.toRadixString(36);
}

String _groupSlug(String runId, String nonce) {
  final raw = 'awiki-e2e-$runId-$nonce'.toLowerCase();
  final slug = raw
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  if (slug.length <= 48) {
    return slug;
  }
  return slug.substring(0, 48).replaceAll(RegExp(r'-$'), '');
}

String _normalizeIdentityRef(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.endsWith('.awiki.ai')) {
    return normalized.substring(0, normalized.length - '.awiki.ai'.length);
  }
  return normalized;
}

bool _looksRecoverableForRegister(String output) {
  final lower = output.toLowerCase();
  return lower.contains('not found') ||
      lower.contains('handle_not_found') ||
      lower.contains('not_registered') ||
      lower.contains('not registered') ||
      lower.contains('404');
}

String _sanitizeDiagnostic(String input) {
  var output = input;
  for (final secret in <String>[_otpPhone, _otpCode, _cliWorkspace, _cliHome]) {
    if (secret.trim().isNotEmpty) {
      output = output.replaceAll(secret, '<redacted>');
    }
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
  return output;
}
