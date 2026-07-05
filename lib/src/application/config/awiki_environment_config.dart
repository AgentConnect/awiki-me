class AwikiEnvironmentConfig {
  AwikiEnvironmentConfig({
    String? baseUrl,
    String? userServiceUrl,
    String? messageServiceUrl,
    String? mailServiceUrl,
    String? didDomain,
    String? stateNamespace,
    String? anpServiceUrl,
    String? anpServiceDid,
    String? daemonDownloadBaseUrl,
    String? packageChannel,
    String? updateManifestUrl,
    String? releasesUrl,
    bool? agentImEnabled,
  }) {
    final normalizedBase = _normalizeBaseUrl(
      baseUrl ?? const String.fromEnvironment('AWIKI_BASE_URL'),
      fallback: 'https://awiki.info',
    );
    final normalizedPackageChannel = _normalizePackageChannel(
      packageChannel ?? const String.fromEnvironment('AWIKI_PACKAGE_CHANNEL'),
      fallback: 'test',
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
    this.stateNamespace = _normalizeStateNamespace(
      stateNamespace,
      didDomain: this.didDomain,
      serviceBaseUrl: normalizedBase,
    );
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
    this.packageChannel = normalizedPackageChannel;
    this.updateManifestUrl = _normalizeBaseUrl(
      updateManifestUrl,
      fallback: _joinUrl(
        normalizedBase,
        '/downloads/awiki-me/$normalizedPackageChannel/latest.json',
      ),
    );
    this.releasesUrl = _normalizeBaseUrl(
      releasesUrl,
      fallback: _joinUrl(normalizedBase, '/#download'),
    );
    this.agentImEnabled = agentImEnabled ?? true;
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
      stateNamespace: const String.fromEnvironment('AWIKI_STATE_NAMESPACE'),
      anpServiceUrl: const String.fromEnvironment('AWIKI_ANP_SERVICE_URL'),
      anpServiceDid: const String.fromEnvironment('AWIKI_ANP_SERVICE_DID'),
      daemonDownloadBaseUrl: const String.fromEnvironment(
        'AWIKI_DAEMON_DOWNLOAD_BASE_URL',
      ),
      packageChannel: const String.fromEnvironment('AWIKI_PACKAGE_CHANNEL'),
      updateManifestUrl: const String.fromEnvironment(
        'AWIKI_UPDATE_MANIFEST_URL',
      ),
      releasesUrl: const String.fromEnvironment('AWIKI_RELEASES_URL'),
      agentImEnabled: const bool.fromEnvironment(
        'AWIKI_AGENT_IM_ENABLED',
        defaultValue: true,
      ),
    );
  }

  late final String baseUrl;
  late final String userServiceUrl;
  late final String messageServiceUrl;
  late final String mailServiceUrl;
  late final String didDomain;
  late final String stateNamespace;
  late final String anpServiceUrl;
  late final String anpServiceDid;
  late final String daemonDownloadBaseUrl;
  late final String packageChannel;
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
    return 'awiki.info';
  }
  return host;
}

String _joinUrl(String baseUrl, String path) {
  final normalizedBase = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return '$normalizedBase$normalizedPath';
}

String _normalizePackageChannel(String? value, {required String fallback}) {
  final raw = _firstNonEmpty(value, fallback);
  final normalized = raw
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return normalized.isEmpty ? fallback : normalized;
}

String _normalizeStateNamespace(
  String? value, {
  required String didDomain,
  required String serviceBaseUrl,
}) {
  final explicit = _safeNamespaceSegment(value);
  if (explicit != null) {
    return explicit;
  }
  final domain = _safeNamespaceSegment(didDomain) ?? 'default';
  final baseHost = Uri.tryParse(serviceBaseUrl.trim())?.host.trim();
  final basePort = Uri.tryParse(serviceBaseUrl.trim())?.hasPort == true
      ? Uri.tryParse(serviceBaseUrl.trim())?.port
      : null;
  final baseIdentity = basePort == null
      ? baseHost
      : '${baseHost ?? ''}-$basePort';
  final base = _safeNamespaceSegment(baseIdentity);
  if (base == null || base == domain) {
    return domain;
  }
  return '$domain-$base';
}

String? _safeNamespaceSegment(String? value) {
  final trimmed = value?.trim().toLowerCase();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final normalized = trimmed
      .replaceAll(RegExp(r'^https?://'), '')
      .replaceAll(RegExp(r'[/\\:*?"<>|#?&=%]+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return normalized.isEmpty ? null : normalized;
}
