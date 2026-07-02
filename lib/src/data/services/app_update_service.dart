import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/app_update_manifest.dart';
import '../../domain/services/update_service.dart';
import 'app_key_value_store.dart';
import 'platform_update_bridge.dart';

const String kDefaultUpdateManifestUrl = String.fromEnvironment(
  'AWIKI_UPDATE_MANIFEST_URL',
  defaultValue: 'https://awiki.ai/downloads/awiki-me/test/latest.json',
);

const String kDefaultReleasesUrl = String.fromEnvironment(
  'AWIKI_RELEASES_URL',
  defaultValue: 'https://awiki.ai/#download',
);

class AppUpdateService implements UpdateService {
  AppUpdateService({
    required AppKeyValueStore storage,
    http.Client? httpClient,
    PlatformUpdateBridge? platformBridge,
    Future<PackageInfo> Function()? packageInfoLoader,
    Future<bool> Function(Uri uri)? urlLauncher,
    String manifestUrl = kDefaultUpdateManifestUrl,
    String releasesUrl = kDefaultReleasesUrl,
  }) : _storage = storage,
       _httpClient = httpClient ?? http.Client(),
       _platformBridge = platformBridge ?? MethodChannelPlatformUpdateBridge(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _urlLauncher = urlLauncher ?? launchUrl,
       _manifestUrl = manifestUrl,
       _releasesUrl = releasesUrl;

  static const String _lastCheckAtKey = 'awiki_me_update_last_checked_at';
  static const String _lastManifestKey = 'awiki_me_update_last_manifest';
  static const Duration _autoCheckInterval = Duration(hours: 24);

  final AppKeyValueStore _storage;
  final http.Client _httpClient;
  final PlatformUpdateBridge _platformBridge;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final Future<bool> Function(Uri uri) _urlLauncher;
  final String _manifestUrl;
  final String _releasesUrl;

  bool _macOsUpdaterConfigured = false;

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
    if (!force && await _shouldSkipAutoCheck()) {
      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        latestManifest: await _loadCachedManifest(),
        wasSkipped: true,
      );
    }

    try {
      final response = await _httpClient.get(Uri.parse(_manifestUrl));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UpdateInstallFailed(
          'Update manifest request failed: ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const FormatException('Update manifest must be an object.');
      }
      final manifest = AppUpdateManifest.fromJson(
        decoded.map<String, Object?>(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        ),
      );
      await _storage.write(
        key: _lastManifestKey,
        value: jsonEncode(manifest.toJson()),
      );
      await _storage.write(
        key: _lastCheckAtKey,
        value: DateTime.now().toUtc().toIso8601String(),
      );
      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        latestManifest: manifest,
      );
    } catch (_) {
      final cachedManifest = await _loadCachedManifest();
      if (!force && cachedManifest != null) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          latestManifest: cachedManifest,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> openReleaseNotes(AppUpdateManifest? manifest) async {
    await _openUrl(
      manifest?.releaseNotesUrl.isNotEmpty == true
          ? manifest!.releaseNotesUrl
          : _releasesUrl,
    );
  }

  @override
  Future<void> openDownloadPage(AppUpdateManifest? manifest) async {
    await _openUrl(
      manifest?.githubReleaseUrl.isNotEmpty == true
          ? manifest!.githubReleaseUrl
          : _releasesUrl,
    );
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
    await openDownloadPage(manifest);
  }

  @override
  Future<void> openInstallPermissionSettings() {
    return _platformBridge.openInstallPermissionSettings();
  }

  Future<bool> _shouldSkipAutoCheck() async {
    final raw = await _storage.read(key: _lastCheckAtKey);
    if (raw == null || raw.isEmpty) {
      return false;
    }
    final checkedAt = DateTime.tryParse(raw);
    if (checkedAt == null) {
      return false;
    }
    return DateTime.now().toUtc().difference(checkedAt.toUtc()) <
        _autoCheckInterval;
  }

  Future<AppUpdateManifest?> _loadCachedManifest() async {
    final raw = await _storage.read(key: _lastManifestKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return AppUpdateManifest.fromJson(
        decoded.map<String, Object?>(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _openUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      throw UpdateInstallFailed('Invalid URL: $rawUrl');
    }
    final launched = await _urlLauncher(uri);
    if (!launched) {
      throw UpdateInstallFailed('Unable to open URL: $rawUrl');
    }
  }

  Future<void> _installMacOsUpdate(AppUpdateManifest manifest) async {
    final appcastUrl = manifest.platforms.macos.appcastUrl;
    if (appcastUrl == null || appcastUrl.isEmpty) {
      final downloadUrl = manifest.platforms.macos.downloadUrl;
      await _openUrl(
        downloadUrl == null || downloadUrl.isEmpty
            ? manifest.githubReleaseUrl
            : downloadUrl,
      );
      return;
    }
    try {
      if (!_macOsUpdaterConfigured) {
        await autoUpdater.setFeedURL(appcastUrl);
        await autoUpdater.setScheduledCheckInterval(24 * 60 * 60);
        _macOsUpdaterConfigured = true;
      }
      await autoUpdater.checkForUpdates(inBackground: false);
    } catch (_) {
      await openDownloadPage(manifest);
    }
  }

  Future<void> _installAndroidUpdate(AppUpdateManifest manifest) async {
    final platformManifest = manifest.platforms.android;
    final downloadUrl = platformManifest.downloadUrl;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      await openDownloadPage(manifest);
      return;
    }
    final canInstall = await _platformBridge.canRequestPackageInstalls();
    if (!canInstall) {
      throw const UpdateInstallPermissionRequired();
    }
    final file = await _downloadApk(
      downloadUrl: downloadUrl,
      version: manifest.version,
      buildNumber: manifest.buildNumber,
      expectedSha256: platformManifest.sha256,
    );
    await _platformBridge.installApk(file.path);
  }

  Future<File> _downloadApk({
    required String downloadUrl,
    required String version,
    required int buildNumber,
    String? expectedSha256,
  }) async {
    final uri = Uri.tryParse(downloadUrl);
    if (uri == null) {
      throw UpdateInstallFailed('Invalid APK URL: $downloadUrl');
    }

    final temporaryDirectory = await getTemporaryDirectory();
    final updateDirectory = Directory('${temporaryDirectory.path}/updates');
    await updateDirectory.create(recursive: true);
    final outputFile = File(
      '${updateDirectory.path}/awiki-me-$version+$buildNumber.apk',
    );
    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    final request = http.Request('GET', uri);
    final response = await _httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UpdateInstallFailed(
        'APK download failed with status ${response.statusCode}',
      );
    }

    final fileSink = outputFile.openWrite();
    try {
      await for (final chunk in response.stream) {
        fileSink.add(chunk);
      }
      await fileSink.close();
      final digest = (await sha256.bind(outputFile.openRead()).first)
          .toString();
      if (expectedSha256 != null &&
          expectedSha256.trim().isNotEmpty &&
          digest.toLowerCase() != expectedSha256.toLowerCase()) {
        await outputFile.delete();
        throw const UpdateInstallFailed('APK checksum verification failed.');
      }
      return outputFile;
    } catch (error) {
      await fileSink.close();
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      rethrow;
    }
  }
}
