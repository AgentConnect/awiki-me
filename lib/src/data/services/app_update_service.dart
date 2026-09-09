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
    this.requestTimeout = const Duration(seconds: 15),
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
  final Duration requestTimeout;
  bool _disposed = false;
  Future<AppUpdateCheckResult>? _checkTask;
  _CachedUpdatePolicy? _lastKnownPolicy;
  final _activeRequests = <Completer<void>>{};
  final _officialServices = <AppOfficialUpdateSource, AppUpdateService>{};

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
  String get _policyCacheKey => '${_cacheNamespace}_policy_v1';
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
    if (_disposed) return;
    _disposed = true;
    for (final request in _activeRequests.toList()) {
      if (!request.isCompleted) request.complete();
    }
    for (final service in _officialServices.values) {
      service.dispose();
    }
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
  Future<AppUpdateCheckResult> loadCachedUpdate() async {
    final current = await getCurrentVersion();
    final cached = await _loadCachedPolicy();
    return _result(
      currentVersion: current,
      manifest: cached.manifest,
      cachedAt: cached.cachedAt,
      usedCache: cached.isKnown,
      policyUnavailable: cached.unavailable,
      wasSkipped: true,
    );
  }

  @override
  Future<AppUpdateCheckResult> checkForUpdates({required bool force}) {
    if (_disposed) return Future.error(StateError('Update service disposed.'));
    final pending = _checkTask;
    if (pending != null) {
      // A manual check may share a network request, but must not settle for an
      // automatic check which only read the fresh cache.
      return pending.then(
        (result) =>
            force && result.wasSkipped ? checkForUpdates(force: true) : result,
      );
    }
    late final Future<AppUpdateCheckResult> task;
    task = _checkForUpdates(force: force).whenComplete(() {
      if (identical(_checkTask, task)) _checkTask = null;
    });
    _checkTask = task;
    return task;
  }

  Future<AppUpdateCheckResult> _checkForUpdates({required bool force}) async {
    final currentVersion = await getCurrentVersion();
    final cached = await _loadCachedPolicy();
    final cachedLocksCurrentVersion =
        cached.manifest != null &&
        _isUnsupported(currentVersion, cached.manifest!);
    if (!force &&
        cached.isKnown &&
        !cachedLocksCurrentVersion &&
        await _shouldSkipAutoCheck()) {
      return _result(
        currentVersion: currentVersion,
        manifest: cached.manifest,
        cachedAt: cached.cachedAt,
        wasSkipped: true,
        usedCache: cached.isKnown,
        policyUnavailable: cached.unavailable,
      );
    }
    try {
      _validateNetworkUri(_policyUri, label: 'update policy');
      final response = await _sendBounded(_policyUri);
      if (_disposed) throw StateError('Update service disposed.');
      if (response.statusCode == 404 && !officialTenant) {
        return _acceptPolicy(
          currentVersion,
          _CachedUpdatePolicy(
            unavailable: true,
            revision: cached.revision,
            cachedAt: DateTime.now().toUtc(),
          ),
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
      // Disabled products must pass the same origin/revision checks as an
      // enabled product before they are allowed to remove a cached minimum.
      final revision = _validateResponsePolicy(document, cached.revision);
      final manifestJson = _appManifestFromResponse(document);
      final manifest = manifestJson == null
          ? null
          : AppUpdateManifest.fromJson(manifestJson);
      if (manifest != null) _validateManifestUris(manifest);
      return _acceptPolicy(
        currentVersion,
        _CachedUpdatePolicy(
          manifest: manifest,
          unavailable: manifest == null,
          revision: revision,
          cachedAt: DateTime.now().toUtc(),
        ),
      );
    } catch (error) {
      if (cached.isKnown) {
        return _result(
          currentVersion: currentVersion,
          manifest: cached.manifest,
          cachedAt: cached.cachedAt,
          usedCache: true,
          policyUnavailable: cached.unavailable,
          failureReason: error.toString(),
        );
      }
      rethrow;
    }
  }

  int _validateResponsePolicy(
    Map<String, Object?> document,
    int minimumRevision,
  ) {
    Object? raw = document;
    if (document.containsKey('client_versions')) {
      if (document['schema_version'] != 1) {
        throw const FormatException('Invalid server-info response.');
      }
      raw = document['client_versions'];
      if (raw == null) return minimumRevision;
    }
    if (raw is! Map || raw['policy_origin'] != policyOrigin) {
      throw const FormatException(
        'Update policy origin does not match the selected tenant.',
      );
    }
    final value = raw['policy_revision'];
    final revision = value is int
        ? value
        : value is String
        ? int.tryParse(value)
        : null;
    if (revision == null || revision < 1) {
      throw const FormatException('Invalid update policy revision.');
    }
    if (revision < minimumRevision) {
      throw const FormatException('Update policy revision moved backwards.');
    }
    return revision;
  }

  Future<AppUpdateCheckResult> _acceptPolicy(
    AppVersion current,
    _CachedUpdatePolicy policy,
  ) async {
    if (_disposed) throw StateError('Update service disposed.');
    _lastKnownPolicy = policy;
    // Persistence is a cache, not authority over a successfully verified live
    // policy. Retain that policy in memory even when local writes fail.
    try {
      // One record replaces the manifest and the explicit absence together;
      // interrupted auxiliary writes cannot resurrect the previous state.
      await _storage.write(
        key: _policyCacheKey,
        value: jsonEncode({
          'schema_version': 1,
          'policy_origin': policyOrigin,
          'policy_revision': policy.revision,
          'cached_at': policy.cachedAt?.toIso8601String(),
          'unavailable': policy.unavailable,
          'manifest': policy.manifest?.toJson(),
        }),
      );
      await _storage.write(
        key: _lastCheckAtKey,
        value: policy.cachedAt!.toIso8601String(),
      );
    } catch (_) {
      /* Keep the current verified in-memory policy. */
    }
    return _result(
      currentVersion: current,
      manifest: policy.manifest,
      cachedAt: policy.cachedAt,
      policyUnavailable: policy.unavailable,
    );
  }

  @override
  Future<AppUpdateCheckResult> checkOfficialSource(
    AppOfficialUpdateSource source,
  ) async {
    if (_disposed) throw StateError('Update service disposed.');
    final origin = switch (source) {
      AppOfficialUpdateSource.primary => primaryBuiltinTenantBackendBaseUrl,
      AppOfficialUpdateSource.secondary => secondaryBuiltinTenantBackendBaseUrl,
    };
    await _storage.write(key: _preferredOfficialSourceKey, value: source.name);
    if (_disposed) throw StateError('Update service disposed.');
    final service = _officialServices.putIfAbsent(
      source,
      () => AppUpdateService(
        storage: _storage,
        tenantId: _tenantId,
        backendBaseUrl: origin,
        officialTenant: true,
        httpClient: _httpClient,
        platformBridge: _platformBridge,
        packageInfoLoader: _packageInfoLoader,
        urlLauncher: _urlLauncher,
        allowLoopbackHttp: _allowLoopbackHttp,
        requestTimeout: requestTimeout,
      ),
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
    try {
      final raw = await _storage.read(key: _lastCheckAtKey);
      final checkedAt = raw == null ? null : DateTime.tryParse(raw);
      return checkedAt != null &&
          DateTime.now().toUtc().difference(checkedAt.toUtc()) <
              _autoCheckInterval;
    } catch (_) {
      return false;
    }
  }

  Future<_CachedUpdatePolicy> _loadCachedPolicy() async {
    if (_lastKnownPolicy != null) return _lastKnownPolicy!;
    var cached = const _CachedUpdatePolicy();
    try {
      final record = await _storage.read(key: _policyCacheKey);
      if (record != null) {
        final value = jsonDecode(record);
        if (value is Map &&
            value['schema_version'] == 1 &&
            value['policy_origin'] == policyOrigin &&
            value['policy_revision'] is int &&
            (value['policy_revision'] as int) >= 0) {
          final rawManifest = _mapOrNull(value['manifest']);
          final manifest = rawManifest == null
              ? null
              : AppUpdateManifest.fromJson(rawManifest);
          if (manifest != null) {
            if (manifest.policyOrigin != policyOrigin ||
                manifest.policyRevision != value['policy_revision']) {
              throw const FormatException('Inconsistent cached policy.');
            }
            _validateManifestUris(manifest);
          }
          if (value['unavailable'] != (manifest == null)) {
            throw const FormatException('Inconsistent cached policy state.');
          }
          cached = _CachedUpdatePolicy(
            manifest: manifest,
            unavailable: manifest == null,
            revision: value['policy_revision'] as int,
            cachedAt: DateTime.tryParse(value['cached_at']?.toString() ?? ''),
          );
        }
        // A present new record supersedes the legacy cache, even if corrupt.
        return _lastKnownPolicy ??= cached;
      }
      // Read existing installations' cache until a verified refresh replaces it.
      final raw = await _storage.read(key: _lastManifestKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final value = jsonDecode(raw);
        if (value is Map) {
          final manifest = AppUpdateManifest.fromJson(
            value.map<String, Object?>(
              (key, value) => MapEntry(key.toString(), value),
            ),
          );
          if (manifest.policyOrigin == policyOrigin) {
            _validateManifestUris(manifest);
            final timestamp = await _storage.read(
              key: _lastManifestCachedAtKey,
            );
            cached = _CachedUpdatePolicy(
              manifest: manifest,
              revision: manifest.policyRevision,
              cachedAt: DateTime.tryParse(timestamp ?? ''),
            );
          }
        }
      }
    } catch (_) {
      /* An unreadable cache cannot establish a version requirement. */
    }
    return _lastKnownPolicy ??= cached;
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
    if (_disposed) throw StateError('Update service disposed.');
    final abort = Completer<void>();
    _activeRequests.add(abort);
    StreamIterator<List<int>>? iterator;
    Future<http.Response> read() async {
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..followRedirects = false;
      final streamed = await _httpClient.send(request);
      final body = StreamIterator(streamed.stream);
      iterator = body;
      if (abort.isCompleted) {
        unawaited(body.cancel());
        throw const UpdateInstallFailed('Update request cancelled.');
      }
      if (streamed.isRedirect) {
        throw const UpdateInstallFailed(
          'Cross-origin update policy redirects are not allowed.',
        );
      }
      if ((streamed.contentLength ?? 0) > _maximumPolicyBytes) {
        throw const UpdateInstallFailed('Update policy response is too large.');
      }
      final bytes = <int>[];
      while (await body.moveNext()) {
        bytes.addAll(body.current);
        if (bytes.length > _maximumPolicyBytes) {
          throw const UpdateInstallFailed(
            'Update policy response is too large.',
          );
        }
      }
      return http.Response.bytes(
        bytes,
        streamed.statusCode,
        request: request,
        headers: streamed.headers,
      );
    }

    try {
      return await Future.any<http.Response>([
        read(),
        abort.future.then<http.Response>(
          (_) => throw const UpdateInstallFailed('Update request cancelled.'),
        ),
      ]).timeout(requestTimeout);
    } finally {
      if (!abort.isCompleted) abort.complete();
      _activeRequests.remove(abort);
      // Do not let a stalled adapter's cancellation delay the UI timeout.
      unawaited(
        iterator?.cancel().catchError((Object _) {}) ?? Future<void>.value(),
      );
    }
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

class _CachedUpdatePolicy {
  const _CachedUpdatePolicy({
    this.manifest,
    this.cachedAt,
    this.unavailable = false,
    this.revision = 0,
  });
  final AppUpdateManifest? manifest;
  final DateTime? cachedAt;
  final bool unavailable;
  final int revision;
  bool get isKnown => manifest != null || unavailable;
}
