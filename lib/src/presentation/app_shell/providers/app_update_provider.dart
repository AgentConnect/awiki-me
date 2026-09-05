import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_services.dart';
import '../../../app/ui_feedback.dart';
import '../../../domain/entities/app_update_manifest.dart';
import '../../../domain/services/update_service.dart';
import '../../../l10n/app_message.dart';

enum AppUpdateStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  installing,
  error,
}

class AppUpdateState {
  const AppUpdateState({
    this.status = AppUpdateStatus.idle,
    this.currentVersion,
    this.latestManifest,
    this.errorMessage,
    this.failureReason,
    this.cachedAt,
    this.usedCache = false,
    this.policyUnavailable = false,
    this.versionUnsupported = false,
    this.recommendationDismissed = false,
    this.manualOfficialSource,
  });

  final AppUpdateStatus status;
  final AppVersion? currentVersion;
  final AppUpdateManifest? latestManifest;
  final String? errorMessage;
  final String? failureReason;
  final DateTime? cachedAt;
  final bool usedCache;
  final bool policyUnavailable;
  final bool versionUnsupported;
  final bool recommendationDismissed;
  final AppOfficialUpdateSource? manualOfficialSource;

  bool get hasUpdate {
    final manifest = latestManifest;
    final current = currentVersion;
    if (manifest == null || current == null) return false;
    return compareAppVersionBuilds(
          AppVersion(
            version: manifest.version,
            buildNumber: manifest.buildNumber,
          ),
          current,
        ) >
        0;
  }

  bool get supportsDirectInstall {
    return false;
  }

  AppUpdateState copyWith({
    AppUpdateStatus? status,
    AppVersion? currentVersion,
    AppUpdateManifest? latestManifest,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool clearLatestManifest = false,
    String? failureReason,
    bool clearFailureReason = false,
    DateTime? cachedAt,
    bool? usedCache,
    bool? policyUnavailable,
    bool? versionUnsupported,
    bool? recommendationDismissed,
    AppOfficialUpdateSource? manualOfficialSource,
    bool clearManualOfficialSource = false,
  }) {
    return AppUpdateState(
      status: status ?? this.status,
      currentVersion: currentVersion ?? this.currentVersion,
      latestManifest: clearLatestManifest
          ? null
          : (latestManifest ?? this.latestManifest),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      failureReason: clearFailureReason
          ? failureReason
          : (failureReason ?? this.failureReason),
      cachedAt: cachedAt ?? this.cachedAt,
      usedCache: usedCache ?? this.usedCache,
      policyUnavailable: policyUnavailable ?? this.policyUnavailable,
      versionUnsupported: versionUnsupported ?? this.versionUnsupported,
      recommendationDismissed:
          recommendationDismissed ?? this.recommendationDismissed,
      manualOfficialSource: clearManualOfficialSource
          ? null
          : (manualOfficialSource ?? this.manualOfficialSource),
    );
  }
}

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(this.ref) : super(const AppUpdateState());

  final Ref ref;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    try {
      final currentVersion = await ref
          .read(updateServiceProvider)
          .getCurrentVersion();
      if (!mounted) return;
      state = state.copyWith(currentVersion: currentVersion);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        status: AppUpdateStatus.error,
        errorMessage: error.toString(),
      );
      return;
    }
    if (!mounted) return;
    await checkForUpdates(force: false, silent: true);
  }

  Future<void> checkForUpdates({
    required bool force,
    bool silent = false,
  }) async {
    if (!mounted) return;
    if (!silent) {
      state = state.copyWith(
        status: AppUpdateStatus.checking,
        clearErrorMessage: true,
      );
    }
    try {
      final result = await ref
          .read(updateServiceProvider)
          .checkForUpdates(force: force);
      final manifest = result.latestManifest;
      final ignored = manifest != null && result.hasUpdate
          ? await ref.read(updateServiceProvider).isVersionIgnored(manifest)
          : false;
      if (manifest != null && result.hasUpdate && !ignored) {
        await ref.read(updateServiceProvider).markVersionPrompted(manifest);
      }
      if (!mounted) return;
      state = state.copyWith(
        currentVersion: result.currentVersion,
        latestManifest: result.latestManifest,
        failureReason: result.failureReason,
        clearFailureReason: result.failureReason == null,
        cachedAt: result.cachedAt,
        usedCache: result.usedCache,
        policyUnavailable: result.policyUnavailable,
        versionUnsupported: result.versionUnsupported,
        recommendationDismissed: ignored,
        clearManualOfficialSource: true,
        status: result.hasUpdate
            ? AppUpdateStatus.updateAvailable
            : AppUpdateStatus.upToDate,
        clearErrorMessage: true,
      );
      if (force && !result.hasUpdate) {
        ref
            .read(uiFeedbackProvider.notifier)
            .showInfo(AppMessage.updateAlreadyLatest());
      }
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        status: AppUpdateStatus.error,
        errorMessage: error.toString(),
      );
      if (!silent) {
        ref
            .read(uiFeedbackProvider.notifier)
            .showError(AppMessage.updateCheckFailed());
      }
    }
  }

  Future<void> checkOfficialSource(AppOfficialUpdateSource source) async {
    if (!mounted) return;
    state = state.copyWith(
      status: AppUpdateStatus.checking,
      clearErrorMessage: true,
      recommendationDismissed: true,
    );
    try {
      final result = await ref
          .read(updateServiceProvider)
          .checkOfficialSource(source);
      if (!mounted) return;
      state = state.copyWith(
        currentVersion: result.currentVersion,
        latestManifest: result.latestManifest,
        failureReason: result.failureReason,
        clearFailureReason: result.failureReason == null,
        cachedAt: result.cachedAt,
        usedCache: result.usedCache,
        policyUnavailable: result.policyUnavailable,
        versionUnsupported: false,
        recommendationDismissed: true,
        manualOfficialSource: source,
        status: result.hasUpdate
            ? AppUpdateStatus.updateAvailable
            : AppUpdateStatus.upToDate,
        clearErrorMessage: true,
      );
      if (!result.hasUpdate) {
        ref
            .read(uiFeedbackProvider.notifier)
            .showInfo(AppMessage.updateAlreadyLatest());
      }
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        status: AppUpdateStatus.error,
        errorMessage: error.toString(),
        recommendationDismissed: true,
        manualOfficialSource: source,
      );
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.updateCheckFailed());
    }
  }

  Future<void> dismissRecommendation() async {
    final manifest = state.latestManifest;
    if (manifest == null) return;
    state = state.copyWith(recommendationDismissed: true);
    try {
      await ref.read(updateServiceProvider).ignoreVersion(manifest);
    } catch (_) {
      // The in-memory dismissal still avoids interrupting the current session.
    }
  }

  Future<void> openReleaseNotes() async {
    try {
      await ref
          .read(updateServiceProvider)
          .openReleaseNotes(state.latestManifest);
    } catch (_) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.updateOpenReleaseNotesFailed());
    }
  }

  Future<void> openDownloadPage() async {
    try {
      await ref
          .read(updateServiceProvider)
          .openDownloadPage(state.latestManifest);
    } catch (_) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.updateOpenDownloadFailed());
    }
  }

  Future<void> installUpdate() async {
    final manifest = state.latestManifest;
    if (manifest == null) {
      return;
    }
    state = state.copyWith(
      status: AppUpdateStatus.installing,
      clearErrorMessage: true,
    );
    try {
      await ref.read(updateServiceProvider).installUpdate(manifest);
      state = state.copyWith(status: AppUpdateStatus.installing);
    } on UpdateInstallPermissionRequired {
      state = state.copyWith(status: AppUpdateStatus.updateAvailable);
      await ref.read(updateServiceProvider).openInstallPermissionSettings();
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.updatePermissionRequired());
    } catch (error) {
      state = state.copyWith(
        status: AppUpdateStatus.error,
        errorMessage: error.toString(),
      );
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.updateInstallFailed());
    }
  }
}

final appUpdateProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>(
      (ref) => AppUpdateController(ref),
    );
