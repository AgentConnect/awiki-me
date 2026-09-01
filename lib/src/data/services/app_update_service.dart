import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/config/awiki_environment_config.dart';
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
  final http.Client _httpClient;
  final PlatformUpdateBridge _platformBridge;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final Future<bool> Function(Uri uri) _urlLauncher;
  final String _tenantId;
  final Uri _policyUri;
  final String _releasesUrl;
  final bool _allowLoopbackHttp;
  final bool officialTenant;

  bool _macOsUpdaterConfigured = false;
  bool _disposed = false;

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
    _disposed = true;
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
    if (!force && await _shouldSkipAutoCheck()) {
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
        return _result(
          currentVersion: currentVersion,
          manifest: cached.manifest,
          cachedAt: cached.cachedAt,
          usedCache: cached.manifest != null,
          policyUnavailable: cached.manifest == null,
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
      final manifest = AppUpdateManifest.fromJson(
        decoded.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
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
      AppOfficialUpdateSource.china => 'https://awiki.me',
      AppOfficialUpdateSource.global => 'https://awiki.ai',
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
    return raw == AppOfficialUpdateSource.global.name
        ? AppOfficialUpdateSource.global
        : AppOfficialUpdateSource.china;
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
    final versionComparison = compareAppVersions(
      current.version,
      manifest.minimumSupportedVersion,
    );
    return versionComparison < 0 ||
        (versionComparison == 0 &&
            current.buildNumber <
                manifest.minimumBuildForPlatform(_platformName));
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
    if (Platform.isAndroid) {
      await _installAndroidUpdate(manifest);
      return;
    }
    if (Platform.isMacOS) {
      await _installMacOsUpdate(manifest);
      return;
    }
    if (Platform.isWindows) {
      await _installWindowsUpdate(manifest);
      return;
    }
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

  Future<void> _installMacOsUpdate(AppUpdateManifest manifest) async {
    final appcastUrl = manifest.platforms.macos.appcastUrl;
    if (appcastUrl == null) {
      await openDownloadPage(manifest);
      return;
    }
    _validateNetworkUri(Uri.parse(appcastUrl), label: 'appcast');
    try {
      await autoUpdater.setFeedURL(appcastUrl);
      if (!_macOsUpdaterConfigured) {
        await autoUpdater.setScheduledCheckInterval(24 * 60 * 60);
        _macOsUpdaterConfigured = true;
      }
      await autoUpdater.checkForUpdates(inBackground: false);
    } catch (_) {
      await openDownloadPage(manifest);
    }
  }

  Future<void> _installAndroidUpdate(AppUpdateManifest manifest) async {
    final artifact = manifest.platforms.android;
    if (artifact.downloadCandidates.isEmpty) {
      await openDownloadPage(manifest);
      return;
    }
    if (!await _platformBridge.canRequestPackageInstalls()) {
      throw const UpdateInstallPermissionRequired();
    }
    final file = await _downloadArtifact(
      artifact: artifact,
      filename:
          'awiki-me-${_tenantFileLabel()}-'
          '${manifest.version}+${manifest.buildNumber}.apk',
    );
    if (_disposed) return;
    await _platformBridge.installApk(file.path);
  }

  Future<void> _installWindowsUpdate(AppUpdateManifest manifest) async {
    final artifact = manifest.platforms.windows;
    if (artifact.downloadCandidates.isEmpty) {
      await openDownloadPage(manifest);
      return;
    }
    final file = await _downloadArtifact(
      artifact: artifact,
      filename:
          'awiki-me-${_tenantFileLabel()}-'
          '${manifest.version}+${manifest.buildNumber}.exe',
    );
    if (_disposed) return;
    final process = await Process.start(
      file.path,
      const <String>[],
      mode: ProcessStartMode.detached,
    );
    if (process.pid <= 0) {
      throw const UpdateInstallFailed('Unable to start Windows installer.');
    }
  }

  String _tenantFileLabel() {
    return sha256.convert(utf8.encode(_tenantId)).toString().substring(0, 12);
  }

  Future<File> _downloadArtifact({
    required AppUpdatePlatformManifest artifact,
    required String filename,
  }) async {
    Object? lastError;
    for (final rawUrl in artifact.downloadCandidates) {
      File? outputFile;
      try {
        final uri = Uri.parse(rawUrl);
        _validateNetworkUri(uri, label: 'update artifact');
        final temporaryDirectory = await getTemporaryDirectory();
        final updateDirectory = Directory('${temporaryDirectory.path}/updates');
        await updateDirectory.create(recursive: true);
        outputFile = File('${updateDirectory.path}/$filename');
        if (await outputFile.exists()) await outputFile.delete();

        final request = http.Request('GET', uri)..followRedirects = false;
        final response = await _httpClient.send(request);
        if (response.isRedirect ||
            response.statusCode < 200 ||
            response.statusCode >= 300) {
          throw UpdateInstallFailed(
            'Artifact download failed with status ${response.statusCode}',
          );
        }
        final sink = outputFile.openWrite();
        try {
          await response.stream.pipe(sink);
        } finally {
          await sink.close();
        }
        if (await outputFile.length() != artifact.sizeBytes) {
          throw const UpdateInstallFailed('Artifact size verification failed.');
        }
        final digest = (await sha256.bind(outputFile.openRead()).first)
            .toString();
        if (digest.toLowerCase() != artifact.sha256!.toLowerCase()) {
          throw const UpdateInstallFailed(
            'Artifact checksum verification failed.',
          );
        }
        return outputFile;
      } catch (error) {
        lastError = error;
        if (outputFile != null && await outputFile.exists()) {
          await outputFile.delete();
        }
      }
    }
    throw UpdateInstallFailed('All artifact mirrors failed: $lastError');
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
  return Uri.parse('${_origin(base)}/downloads/awiki-me/latest.json');
}

String _origin(Uri uri) => uri.origin;

bool _isLoopback(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}
