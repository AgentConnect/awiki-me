import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/config/awiki_environment_config.dart';
import '../../application/tenant/app_tenant.dart';
import '../../domain/entities/app_update_manifest.dart';
import '../../domain/services/update_service.dart';
import 'app_key_value_store.dart';
import 'platform_update_bridge.dart';

final AwikiEnvironmentConfig _defaultUpdateEnvironment =
    AwikiEnvironmentConfig.fromEnvironment();

final String kDefaultUpdateManifestUrl =
    _defaultUpdateEnvironment.updateManifestUrl;

final String kDefaultReleasesUrl = _defaultUpdateEnvironment.releasesUrl;

class AppUpdateService implements UpdateService, DisposableUpdateService {
  AppUpdateService({
    required AppKeyValueStore storage,
    required String tenantId,
    required String backendBaseUrl,
    this.officialTenant = true,
    http.Client? httpClient,
    PlatformUpdateBridge? platformBridge,
    Future<PackageInfo> Function()? packageInfoLoader,
    Future<bool> Function(Uri uri)? urlLauncher,
    String? manifestUrl,
    String? releasesUrl,
    bool? allowLoopbackHttp,
  }) : _storage = storage,
       _ownsHttpClient = httpClient == null,
       _httpClient = httpClient ?? http.Client(),
       _platformBridge = platformBridge ?? MethodChannelPlatformUpdateBridge(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _urlLauncher = urlLauncher ?? launchUrl,
       _tenantId = tenantId,
       _policyUri = _buildPolicyUri(backendBaseUrl, manifestUrl),
       _releasesUrl =
           releasesUrl ?? '${_origin(Uri.parse(backendBaseUrl))}/#download',
       _allowLoopbackHttp = allowLoopbackHttp ?? kDebugMode;

  static const Duration _autoCheckInterval = Duration(hours: 24);
  static const int _maximumPolicyBytes = 1024 * 1024;

  final AppKeyValueStore _storage;
  final bool _ownsHttpClient;
  final http.Client _httpClient;
  final PlatformUpdateBridge _platformBridge;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final Future<bool> Function(Uri uri) _urlLauncher;
  final String _tenantId;
  final Uri _policyUri;
  final String _releasesUrl;
  final bool _allowLoopbackHttp;
  final bool officialTenant;

  String get policyOrigin => _origin(_policyUri);
  String get policyUrl => _policyUri.toString();
  String get _cacheNamespace {
    final originHash = sha256.convert(utf8.encode(policyOrigin)).toString();
    final tenantHash = sha256.convert(utf8.encode(_tenantId)).toString();
    return 'awiki_me_update_${tenantHash}_'
        '${originHash}_awiki-me_stable';
  }

  String get _lastCheckAtKey => '${_cacheNamespace}_checked_at';
  String get _lastManifestKey => '${_cacheNamespace}_manifest';
  String get _lastManifestCachedAtKey => '${_cacheNamespace}_cached_at';
  String get _lastPromptedVersionKey => '${_cacheNamespace}_prompted_version';
  String get _ignoredVersionKey => '${_cacheNamespace}_ignored_version';
  String get _preferredOfficialSourceKey {
    final tenantHash = sha256.convert(utf8.encode(_tenantId)).toString();
    return 'awiki_me_update_${tenantHash}_preferred_official_source';
  }

  String _versionIdentity(AppUpdateManifest manifest) =>
      '${manifest.version}+${manifest.buildNumber}';

  @override
  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }

  @override
  Future<AppVersion> getCurrentVersion() async {
    final info = await _packageInfoLoader();
    return AppVersion(
      version: info.version,
      buildNumber: int.tryParse(info.buildNumber) ?? 0,
    );
  }

  @override
  Future<AppUpdateCheckResult> checkForUpdates({required bool force}) async {
    final currentVersion = await getCurrentVersion();
    final cached = await _loadCachedManifest();
    final cachedLocksCurrentVersion =
        cached.manifest != null &&
        _isUnsupported(currentVersion, cached.manifest!);
    if (!force && !cachedLocksCurrentVersion && await _shouldSkipAutoCheck()) {
      return _result(
        currentVersion: currentVersion,
        manifest: cached.manifest,
        cachedAt: cached.cachedAt,
        wasSkipped: true,
        usedCache: cached.manifest != null,
      );
    }

    try {
      _validateNetworkUri(_policyUri, label: 'update policy');
      final response = await _sendBounded(_policyUri);
      if (response.statusCode == 404 && !officialTenant) {
        await _storage.delete(key: _lastManifestKey);
        await _storage.delete(key: _lastManifestCachedAtKey);
        await _storage.write(
          key: _lastCheckAtKey,
          value: DateTime.now().toUtc().toIso8601String(),
        );
        return _result(
          currentVersion: currentVersion,
          manifest: null,
          policyUnavailable: true,
          failureReason: 'This tenant does not provide an update policy.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UpdateInstallFailed(
          'Update policy request failed: ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const FormatException('Update policy must be an object.');
      }
      final document = decoded.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      final manifestJson = _appManifestFromResponse(document);
      if (manifestJson == null) {
        await _storage.delete(key: _lastManifestKey);
        await _storage.delete(key: _lastManifestCachedAtKey);
        return _result(
          currentVersion: currentVersion,
          manifest: null,
          policyUnavailable: true,
          failureReason: 'This tenant does not provide an App update policy.',
        );
      }
      final manifest = AppUpdateManifest.fromJson(manifestJson);
      if (manifest.policyOrigin != policyOrigin) {
        throw const FormatException(
          'Update policy origin does not match the selected tenant.',
        );
      }
      if (cached.manifest != null &&
          manifest.policyRevision < cached.manifest!.policyRevision) {
        throw const FormatException('Update policy revision moved backwards.');
      }
      _validateManifestUris(manifest);
      final cachedAt = DateTime.now().toUtc();
      await _storage.write(
        key: _lastManifestKey,
        value: jsonEncode(manifest.toJson()),
      );
      await _storage.write(
        key: _lastManifestCachedAtKey,
        value: cachedAt.toIso8601String(),
      );
      await _storage.write(
        key: _lastCheckAtKey,
        value: cachedAt.toIso8601String(),
      );
      return _result(
        currentVersion: currentVersion,
        manifest: manifest,
        cachedAt: cachedAt,
      );
    } catch (error) {
      if (cached.manifest != null) {
        return _result(
          currentVersion: currentVersion,
          manifest: cached.manifest,
          cachedAt: cached.cachedAt,
          usedCache: true,
          failureReason: error.toString(),
        );
      }
      rethrow;
    }
  }

  @override
  Future<AppUpdateCheckResult> checkOfficialSource(
    AppOfficialUpdateSource source,
  ) async {
    final origin = switch (source) {
      AppOfficialUpdateSource.primary => primaryBuiltinTenantBackendBaseUrl,
      AppOfficialUpdateSource.secondary => secondaryBuiltinTenantBackendBaseUrl,
    };
    await _storage.write(key: _preferredOfficialSourceKey, value: source.name);
    final service = AppUpdateService(
      storage: _storage,
      tenantId: _tenantId,
      backendBaseUrl: origin,
      officialTenant: true,
      httpClient: _httpClient,
      platformBridge: _platformBridge,
      packageInfoLoader: _packageInfoLoader,
      urlLauncher: _urlLauncher,
      allowLoopbackHttp: _allowLoopbackHttp,
    );
    final result = await service.checkForUpdates(force: true);
    return AppUpdateCheckResult(
      currentVersion: result.currentVersion,
      latestManifest: result.latestManifest,
      wasSkipped: result.wasSkipped,
      usedCache: result.usedCache,
      policyUnavailable: result.policyUnavailable,
      failureReason: result.failureReason,
      cachedAt: result.cachedAt,
      versionUnsupported: false,
    );
  }

  @override
  Future<AppOfficialUpdateSource> loadPreferredOfficialSource() async {
    final raw = await _storage.read(key: _preferredOfficialSourceKey);
    return raw == AppOfficialUpdateSource.secondary.name
        ? AppOfficialUpdateSource.secondary
        : AppOfficialUpdateSource.primary;
  }

  @override
  Future<bool> isVersionIgnored(AppUpdateManifest manifest) async {
    return await _storage.read(key: _ignoredVersionKey) ==
        _versionIdentity(manifest);
  }

  @override
  Future<void> markVersionPrompted(AppUpdateManifest manifest) {
    return _storage.write(
      key: _lastPromptedVersionKey,
      value: _versionIdentity(manifest),
    );
  }

  @override
  Future<void> ignoreVersion(AppUpdateManifest manifest) {
    return _storage.write(
      key: _ignoredVersionKey,
      value: _versionIdentity(manifest),
    );
  }

  AppUpdateCheckResult _result({
    required AppVersion currentVersion,
    required AppUpdateManifest? manifest,
    DateTime? cachedAt,
    bool wasSkipped = false,
    bool usedCache = false,
    bool policyUnavailable = false,
    String? failureReason,
  }) {
    return AppUpdateCheckResult(
      currentVersion: currentVersion,
      latestManifest: manifest,
      cachedAt: cachedAt,
      wasSkipped: wasSkipped,
      usedCache: usedCache,
      policyUnavailable: policyUnavailable,
      failureReason: failureReason,
      versionUnsupported:
          manifest != null && _isUnsupported(currentVersion, manifest),
    );
  }

  bool _isUnsupported(AppVersion current, AppUpdateManifest manifest) {
    return compareAppVersionBuilds(
          current,
          AppVersion(
            version: manifest.minimumSupportedVersion,
            buildNumber: manifest.minimumBuildForPlatform(_platformName),
          ),
        ) <
        0;
  }

  String get _platformName {
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return Platform.operatingSystem;
  }

  @override
  Future<void> openReleaseNotes(AppUpdateManifest? manifest) async {
    await _openUrl(manifest?.releaseNotesUrl ?? _releasesUrl);
  }

  @override
  Future<void> openDownloadPage(AppUpdateManifest? manifest) async {
    await _openUrl(manifest?.githubReleaseUrl ?? _releasesUrl);
  }

  @override
  Future<void> installUpdate(AppUpdateManifest manifest) async {
    await openDownloadPage(manifest);
  }

  @override
  Future<void> openInstallPermissionSettings() {
    return _platformBridge.openInstallPermissionSettings();
  }

  Future<bool> _shouldSkipAutoCheck() async {
    final raw = await _storage.read(key: _lastCheckAtKey);
    final checkedAt = raw == null ? null : DateTime.tryParse(raw);
    return checkedAt != null &&
        DateTime.now().toUtc().difference(checkedAt.toUtc()) <
            _autoCheckInterval;
  }

  Future<({AppUpdateManifest? manifest, DateTime? cachedAt})>
  _loadCachedManifest() async {
    final raw = await _storage.read(key: _lastManifestKey);
    final cachedAtRaw = await _storage.read(key: _lastManifestCachedAtKey);
    if (raw == null || raw.trim().isEmpty) {
      return (manifest: null, cachedAt: null);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return (manifest: null, cachedAt: null);
      final manifest = AppUpdateManifest.fromJson(
        decoded.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
      if (manifest.policyOrigin != policyOrigin) {
        return (manifest: null, cachedAt: null);
      }
      return (
        manifest: manifest,
        cachedAt: cachedAtRaw == null ? null : DateTime.tryParse(cachedAtRaw),
      );
    } catch (_) {
      return (manifest: null, cachedAt: null);
    }
  }

  Future<void> _openUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) throw UpdateInstallFailed('Invalid URL: $rawUrl');
    _validateNetworkUri(uri, label: 'update link');
    if (!await _urlLauncher(uri)) {
      throw UpdateInstallFailed('Unable to open URL: $rawUrl');
    }
  }

  Future<http.Response> _sendBounded(Uri uri) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    final streamed = await _httpClient.send(request);
    if (streamed.isRedirect) {
      throw const UpdateInstallFailed(
        'Cross-origin update policy redirects are not allowed.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in streamed.stream) {
      bytes.addAll(chunk);
      if (bytes.length > _maximumPolicyBytes) {
        throw const UpdateInstallFailed('Update policy response is too large.');
      }
    }
    return http.Response.bytes(
      bytes,
      streamed.statusCode,
      request: request,
      headers: streamed.headers,
    );
  }

  void _validateManifestUris(AppUpdateManifest manifest) {
    _validateNetworkUri(
      Uri.parse(manifest.releaseNotesUrl),
      label: 'release notes',
    );
    _validateNetworkUri(
      Uri.parse(manifest.githubReleaseUrl),
      label: 'download page',
    );
    for (final artifact in <AppUpdatePlatformManifest>[
      manifest.platforms.android,
      manifest.platforms.macos,
      manifest.platforms.windows,
    ]) {
      for (final value in artifact.downloadCandidates) {
        _validateNetworkUri(Uri.parse(value), label: 'update artifact');
      }
      if (artifact.appcastUrl != null) {
        final appcast = Uri.parse(artifact.appcastUrl!);
        _validateNetworkUri(appcast, label: 'appcast');
        if (_origin(appcast) != policyOrigin) {
          throw const FormatException(
            'The appcast must belong to the selected tenant.',
          );
        }
      }
    }
  }

  void _validateNetworkUri(Uri uri, {required String label}) {
    if (uri.userInfo.isNotEmpty || uri.host.isEmpty) {
      throw FormatException('Invalid $label URL.');
    }
    if (uri.scheme == 'https') return;
    if (_allowLoopbackHttp && uri.scheme == 'http' && _isLoopback(uri.host)) {
      return;
    }
    throw FormatException('$label must use HTTPS.');
  }
}

Uri _buildPolicyUri(String backendBaseUrl, String? override) {
  if (override != null) return Uri.parse(override);
  final base = Uri.parse(backendBaseUrl);
  return Uri.parse(
    '${_origin(base)}/user-service/v1/server-info?client_platform=app',
  );
}

Map<String, Object?>? _appManifestFromResponse(Map<String, Object?> response) {
  if (!response.containsKey('client_versions')) return response;
  if (response['schema_version'] != 1) {
    throw const FormatException('Invalid server-info response.');
  }
  final releases = _mapOrNull(response['client_versions']);
  if (releases == null) return null;
  final products = _mapOrNull(releases['products']);
  final app = _mapOrNull(products?['app']);
  if (releases['schema_version'] != 1 ||
      releases['channel'] != 'stable' ||
      app == null) {
    throw const FormatException('Invalid App release policy.');
  }
  if (app['enabled'] == false) return null;
  if (app['enabled'] != true) {
    throw const FormatException('Invalid App release policy.');
  }
  final platforms = _mapOrNull(app['platforms']);
  if (platforms == null) {
    throw const FormatException('Invalid App platform policy.');
  }
  final currentPlatform = Platform.isAndroid
      ? 'android'
      : Platform.isMacOS
      ? 'macos'
      : Platform.isWindows
      ? 'windows'
      : null;
  final current = currentPlatform == null
      ? null
      : _mapOrNull(platforms[currentPlatform]);
  final downloadPage = current?['download_page_url']?.toString();
  Map<String, Object?> platform(String name) {
    final policy = _mapOrNull(platforms[name]);
    if (policy == null || policy['enabled'] != true) {
      return <String, Object?>{};
    }
    final artifact = _mapOrNull(policy['artifact']);
    return <String, Object?>{
      if (artifact != null) ...<String, Object?>{
        'downloadUrl': artifact['url'],
        'sha256': artifact['sha256'],
        'sizeBytes': artifact['size_bytes'],
        'mirrors': (artifact['mirrors'] as List<Object?>? ?? const <Object?>[])
            .map((url) => <String, Object?>{'url': url})
            .toList(growable: false),
      },
      if (policy['appcast_url'] != null) 'appcastUrl': policy['appcast_url'],
      if (policy['minimum_supported_build_number'] != null)
        'minSupportedBuildNumber': policy['minimum_supported_build_number'],
    };
  }

  return <String, Object?>{
    'product': 'awiki-me',
    'channel': releases['channel'],
    'policy_origin': releases['policy_origin'],
    'policy_revision': releases['policy_revision'],
    'version': app['recommended_version'],
    'buildNumber': app['recommended_build_number'],
    'minimum_supported_version': app['minimum_supported_version'],
    'minimum_supported_build_number': app['minimum_supported_build_number'],
    'published_at': releases['published_at'],
    'release_notes_url': app['release_notes_url'],
    'githubReleaseUrl': downloadPage ?? app['release_notes_url'],
    'platforms': <String, Object?>{
      'android': platform('android'),
      'macos': platform('macos'),
      'windows-x64': platform('windows'),
    },
  };
}

Map<String, Object?>? _mapOrNull(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : null;

String _origin(Uri uri) => uri.origin;

bool _isLoopback(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}
