import 'dart:io';

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
  });

  final AppUpdateStatus status;
  final AppVersion? currentVersion;
  final AppUpdateManifest? latestManifest;
  final String? errorMessage;

  bool get hasUpdate =>
      latestManifest != null &&
      currentVersion != null &&
      latestManifest!.buildNumber > currentVersion!.buildNumber;

  bool get supportsDirectInstall {
    if (!hasUpdate) {
      return false;
    }
    if (Platform.isAndroid) {
      return latestManifest!.platforms.android.downloadUrl?.isNotEmpty == true;
    }
    if (Platform.isMacOS) {
      return latestManifest!.platforms.macos.appcastUrl?.isNotEmpty == true;
    }
    return false;
  }

  AppUpdateState copyWith({
    AppUpdateStatus? status,
    AppVersion? currentVersion,
    AppUpdateManifest? latestManifest,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool clearLatestManifest = false,
  }) {
    return AppUpdateState(
      status: status ?? this.status,
      currentVersion: currentVersion ?? this.currentVersion,
      latestManifest:
          clearLatestManifest ? null : (latestManifest ?? this.latestManifest),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
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
      final currentVersion =
          await ref.read(updateServiceProvider).getCurrentVersion();
      state = state.copyWith(currentVersion: currentVersion);
    } catch (error) {
      state = state.copyWith(
        status: AppUpdateStatus.error,
        errorMessage: error.toString(),
      );
      return;
    }
    await checkForUpdates(force: false, silent: true);
  }

  Future<void> checkForUpdates({
    required bool force,
    bool silent = false,
  }) async {
    if (!silent) {
      state = state.copyWith(
        status: AppUpdateStatus.checking,
        clearErrorMessage: true,
      );
    }
    try {
      final result = await ref.read(updateServiceProvider).checkForUpdates(
            force: force,
          );
      state = state.copyWith(
        currentVersion: result.currentVersion,
        latestManifest: result.latestManifest,
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

  Future<void> openReleaseNotes() async {
    try {
      await ref
          .read(updateServiceProvider)
          .openReleaseNotes(state.latestManifest);
    } catch (_) {
      ref.read(uiFeedbackProvider.notifier).showError(
            AppMessage.updateOpenReleaseNotesFailed(),
          );
    }
  }

  Future<void> openDownloadPage() async {
    try {
      await ref
          .read(updateServiceProvider)
          .openDownloadPage(state.latestManifest);
    } catch (_) {
      ref.read(uiFeedbackProvider.notifier).showError(
            AppMessage.updateOpenDownloadFailed(),
          );
    }
  }

  Future<void> installUpdate() async {
    final manifest = state.latestManifest;
    if (manifest == null) {
      return;
    }
    state = state.copyWith(
      status: Platform.isAndroid
          ? AppUpdateStatus.downloading
          : AppUpdateStatus.installing,
      clearErrorMessage: true,
    );
    try {
      await ref.read(updateServiceProvider).installUpdate(manifest);
      state = state.copyWith(status: AppUpdateStatus.installing);
      if (Platform.isAndroid) {
        ref
            .read(uiFeedbackProvider.notifier)
            .showInfo(AppMessage.updateReadyToInstall());
      }
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
