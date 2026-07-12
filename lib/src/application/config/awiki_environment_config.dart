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
    String? updateManifestUrl,
    String? releasesUrl,
    bool? agentImEnabled,
  }) {
    final normalizedBase = _normalizeBaseUrl(
      baseUrl,
      fallback: 'https://awiki.ai',
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
    this.updateManifestUrl = _normalizeBaseUrl(
      updateManifestUrl,
      fallback: _joinUrl(normalizedBase, '/downloads/awiki-me/latest.json'),
    );
    this.releasesUrl = _normalizeBaseUrl(
      releasesUrl,
      fallback: _joinUrl(normalizedBase, '/#download'),
    );
    this.agentImEnabled = agentImEnabled ?? true;
  }

  factory AwikiEnvironmentConfig.fromEnvironment() {
    return AwikiEnvironmentConfig();
  }

  late final String baseUrl;
  late final String userServiceUrl;
  late final String messageServiceUrl;
  late final String mailServiceUrl;
  late final String didDomain;
  late final String anpServiceUrl;
  late final String anpServiceDid;
  late final String daemonDownloadBaseUrl;
  late final String updateManifestUrl;
  late final String releasesUrl;
  late final bool agentImEnabled;
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
    return 'awiki.ai';
  }
  return host;
}

String _joinUrl(String baseUrl, String path) {
  final normalizedBase = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return '$normalizedBase$normalizedPath';
}
