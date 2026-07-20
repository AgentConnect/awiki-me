// [INPUT]: Compile-time flags and optional tenant/service overrides.
// [OUTPUT]: Normalized AWiki runtime endpoints and default-off product capability gates.
// [POS]: Application configuration boundary shared by bootstrap and feature providers.

const String primaryTenantDomainEnvironmentKey = 'AWIKI_PRIMARY_TENANT_DOMAIN';
const String primaryTenantDomain = String.fromEnvironment(
  primaryTenantDomainEnvironmentKey,
  defaultValue: 'awiki.ai',
);
const String primaryTenantBaseUrl = 'https://$primaryTenantDomain';
const bool defaultMultiDeviceJoinEnabled = bool.fromEnvironment(
  'AWIKI_MULTI_DEVICE_ENABLED',
  defaultValue: false,
);
const bool defaultMultiDeviceRootTransferEnabled = bool.fromEnvironment(
  'AWIKI_MULTI_DEVICE_ROOT_TRANSFER_ENABLED',
  defaultValue: false,
);
const bool defaultMultiDeviceDeviceRevokeEnabled = bool.fromEnvironment(
  'AWIKI_MULTI_DEVICE_DEVICE_REVOKE_ENABLED',
  defaultValue: false,
);
const bool defaultMultiDeviceDirectE2eeEnabled = bool.fromEnvironment(
  'AWIKI_MULTI_DEVICE_DIRECT_E2EE_ENABLED',
  defaultValue: false,
);
const bool defaultMultiDeviceGroupE2eeEnabled = bool.fromEnvironment(
  'AWIKI_MULTI_DEVICE_GROUP_E2EE_ENABLED',
  defaultValue: false,
);
const bool defaultHandleRecoveryEnabled = bool.fromEnvironment(
  'AWIKI_HANDLE_RECOVERY_ENABLED',
  defaultValue: false,
);
const Set<String> agentDaemonTenantDomainAllowlist = <String>{
  'awiki.ai',
  'anpclaw.com',
  'awiki.info',
};

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
    bool? multiDeviceJoinEnabled,
    bool? multiDeviceRootTransferEnabled,
    bool? multiDeviceDeviceRevokeEnabled,
    bool? multiDeviceDirectE2eeEnabled,
    bool? multiDeviceGroupE2eeEnabled,
    bool? handleRecoveryEnabled,
  }) {
    final normalizedBase = _normalizeBaseUrl(
      baseUrl,
      fallback: primaryTenantBaseUrl,
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
    this.agentImEnabled =
        agentImEnabled ??
        isAgentDaemonTenantRealmAllowed(
          backendBaseUrl: normalizedBase,
          didHost: this.didDomain,
        );
    this.multiDeviceJoinEnabled =
        multiDeviceJoinEnabled ?? defaultMultiDeviceJoinEnabled;
    this.multiDeviceRootTransferEnabled =
        multiDeviceRootTransferEnabled ?? defaultMultiDeviceRootTransferEnabled;
    this.multiDeviceDeviceRevokeEnabled =
        multiDeviceDeviceRevokeEnabled ?? defaultMultiDeviceDeviceRevokeEnabled;
    this.multiDeviceDirectE2eeEnabled =
        multiDeviceDirectE2eeEnabled ?? defaultMultiDeviceDirectE2eeEnabled;
    this.multiDeviceGroupE2eeEnabled =
        multiDeviceGroupE2eeEnabled ?? defaultMultiDeviceGroupE2eeEnabled;
    this.handleRecoveryEnabled =
        handleRecoveryEnabled ?? defaultHandleRecoveryEnabled;
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
  late final bool multiDeviceJoinEnabled;
  late final bool multiDeviceRootTransferEnabled;
  late final bool multiDeviceDeviceRevokeEnabled;
  late final bool multiDeviceDirectE2eeEnabled;
  late final bool multiDeviceGroupE2eeEnabled;
  late final bool handleRecoveryEnabled;
}

bool isAgentDaemonTenantRealmAllowed({
  required String backendBaseUrl,
  required String didHost,
}) {
  final backend = Uri.tryParse(backendBaseUrl.trim());
  if (backend == null ||
      backend.scheme.toLowerCase() != 'https' ||
      backend.host.isEmpty ||
      backend.hasPort ||
      backend.userInfo.isNotEmpty ||
      (backend.path.isNotEmpty && backend.path != '/') ||
      backend.hasQuery ||
      backend.hasFragment) {
    return false;
  }
  final backendHost = backend.host.toLowerCase();
  final normalizedDidHost = didHost
      .trim()
      .replaceAll(RegExp(r'^\.+|\.+$'), '')
      .toLowerCase();
  return backendHost == normalizedDidHost &&
      agentDaemonTenantDomainAllowlist.contains(backendHost);
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
    return primaryTenantDomain;
  }
  return host;
}

String _joinUrl(String baseUrl, String path) {
  final normalizedBase = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return '$normalizedBase$normalizedPath';
}
