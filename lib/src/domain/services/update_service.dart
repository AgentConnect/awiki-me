import '../entities/app_update_manifest.dart';

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    this.latestManifest,
    this.wasSkipped = false,
    this.usedCache = false,
    this.policyUnavailable = false,
    this.failureReason,
    this.cachedAt,
    this.versionUnsupported = false,
  });

  final AppVersion currentVersion;
  final AppUpdateManifest? latestManifest;
  final bool wasSkipped;
  final bool usedCache;
  final bool policyUnavailable;
  final String? failureReason;
  final DateTime? cachedAt;
  final bool versionUnsupported;

  bool get hasUpdate {
    final manifest = latestManifest;
    if (manifest == null) return false;
    final comparison = compareAppVersions(
      manifest.version,
      currentVersion.version,
    );
    return comparison > 0 ||
        (comparison == 0 && manifest.buildNumber > currentVersion.buildNumber);
  }
}

enum AppOfficialUpdateSource { china, global }

abstract interface class DisposableUpdateService {
  void dispose();
}

abstract class UpdateService {
  Future<AppVersion> getCurrentVersion();

  Future<AppUpdateCheckResult> checkForUpdates({required bool force});

  Future<AppUpdateCheckResult> checkOfficialSource(
    AppOfficialUpdateSource source,
  );

  Future<AppOfficialUpdateSource> loadPreferredOfficialSource();

  Future<bool> isVersionIgnored(AppUpdateManifest manifest);

  Future<void> markVersionPrompted(AppUpdateManifest manifest);

  Future<void> ignoreVersion(AppUpdateManifest manifest);

  Future<void> openReleaseNotes(AppUpdateManifest? manifest);

  Future<void> openDownloadPage(AppUpdateManifest? manifest);

  Future<void> installUpdate(AppUpdateManifest manifest);

  Future<void> openInstallPermissionSettings();
}

class UpdateInstallPermissionRequired implements Exception {
  const UpdateInstallPermissionRequired();

  @override
  String toString() => 'UPDATE_INSTALL_PERMISSION_REQUIRED';
}

class UpdateInstallFailed implements Exception {
  const UpdateInstallFailed(this.message);

  final String message;

  @override
  String toString() => message;
}
