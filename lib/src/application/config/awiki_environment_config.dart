class AwikiEnvironmentConfig {
  AwikiEnvironmentConfig({
    String? baseUrl,
    String? userServiceUrl,
    String? messageServiceUrl,
    String? mailServiceUrl,
    String? didDomain,
    String? anpServiceUrl,
    String? anpServiceDid,
    String? daemonDownloadBaseUrl,
  }) {
    final normalizedBase = _normalizeBaseUrl(
      baseUrl ?? const String.fromEnvironment('AWIKI_BASE_URL'),
      fallback: 'https://awiki.info',
    );
    this.baseUrl = normalizedBase;
    this.userServiceUrl = _normalizeBaseUrl(
      userServiceUrl,
      fallback: normalizedBase,
    );
    this.messageServiceUrl = _normalizeBaseUrl(
      messageServiceUrl,
      fallback: normalizedBase,
    );
    this.mailServiceUrl = _normalizeBaseUrl(
      mailServiceUrl,
      fallback: normalizedBase,
    );
    this.didDomain = _firstNonEmpty(didDomain, _hostFromUrl(normalizedBase));
    this.anpServiceUrl = _normalizeBaseUrl(
      anpServiceUrl,
      fallback: _joinUrl(normalizedBase, '/anp-im/rpc'),
    );
    this.anpServiceDid = _firstNonEmpty(
      anpServiceDid,
      'did:wba:${this.didDomain}',
    );
    this.daemonDownloadBaseUrl = _normalizeBaseUrl(
      daemonDownloadBaseUrl,
      fallback: _joinUrl(normalizedBase, '/daemon'),
    );
  }

  factory AwikiEnvironmentConfig.fromEnvironment() {
    return AwikiEnvironmentConfig(
      baseUrl: const String.fromEnvironment('AWIKI_BASE_URL'),
      userServiceUrl: const String.fromEnvironment('AWIKI_USER_SERVICE_URL'),
      messageServiceUrl: const String.fromEnvironment(
        'AWIKI_MESSAGE_SERVICE_URL',
      ),
      mailServiceUrl: const String.fromEnvironment('AWIKI_MAIL_SERVICE_URL'),
      didDomain: const String.fromEnvironment('AWIKI_DID_DOMAIN'),
      anpServiceUrl: const String.fromEnvironment('AWIKI_ANP_SERVICE_URL'),
      anpServiceDid: const String.fromEnvironment('AWIKI_ANP_SERVICE_DID'),
      daemonDownloadBaseUrl: const String.fromEnvironment(
        'AWIKI_DAEMON_DOWNLOAD_BASE_URL',
      ),
    );
  }

  late final String baseUrl;
  late final String userServiceUrl;
  late final String messageServiceUrl;
  late final String mailServiceUrl;
  late final String didDomain;
  late final String anpServiceUrl;
  late final String anpServiceDid;
  late final String daemonDownloadBaseUrl;
}

String _normalizeBaseUrl(String? value, {required String fallback}) {
  final raw = _firstNonEmpty(value, fallback);
  return raw.replaceAll(RegExp(r'/+$'), '');
}

String _firstNonEmpty(String? value, String fallback) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return fallback;
  }
  return trimmed;
}

String _hostFromUrl(String baseUrl) {
  final host = Uri.tryParse(baseUrl.trim())?.host.trim().toLowerCase();
  if (host == null || host.isEmpty) {
    return 'awiki.info';
  }
  return host;
}

String _joinUrl(String baseUrl, String path) {
  final normalizedBase = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return '$normalizedBase$normalizedPath';
}
