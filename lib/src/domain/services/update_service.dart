import '../entities/app_update_manifest.dart';

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    this.latestManifest,
    this.wasSkipped = false,
  });

  final AppVersion currentVersion;
  final AppUpdateManifest? latestManifest;
  final bool wasSkipped;

  bool get hasUpdate =>
      latestManifest != null &&
      latestManifest!.buildNumber > currentVersion.buildNumber;
}

abstract class UpdateService {
  Future<AppVersion> getCurrentVersion();

  Future<AppUpdateCheckResult> checkForUpdates({required bool force});

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
