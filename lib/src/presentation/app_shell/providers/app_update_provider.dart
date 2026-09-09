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
  unavailable,
  updateAvailable,
  downloading,
  installing,
  error,
}

class AppUpdateState {
  const AppUpdateState({
    this.status = AppUpdateStatus.idle,
    this.currentVersion,
    this.localStateLoaded = false,
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
  final bool localStateLoaded;
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
    bool? localStateLoaded,
    AppUpdateManifest? latestManifest,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool clearLatestManifest = false,
    String? failureReason,
    bool clearFailureReason = false,
    DateTime? cachedAt,
    bool clearCachedAt = false,
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
      localStateLoaded: localStateLoaded ?? this.localStateLoaded,
      latestManifest: clearLatestManifest
          ? null
          : (latestManifest ?? this.latestManifest),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      failureReason: clearFailureReason
          ? failureReason
          : (failureReason ?? this.failureReason),
      cachedAt: clearCachedAt ? null : (cachedAt ?? this.cachedAt),
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
  Future<void>? _localStateTask;
  Future<void>? _initializeTask;
  int _requestGeneration = 0;
  int _tenantRequestGeneration = 0;

  bool _isCurrent(int? generation) =>
      mounted && generation == _requestGeneration;

  Future<void> initialize() => _initializeTask ??= _initialize();

  Future<void> _initialize() async {
    await _ensureLocalState();
    // Only another tenant check can replace startup's compatibility check.
    if (mounted && _tenantRequestGeneration == 0) {
      await _check(force: false, silent: true, startup: true);
    }
  }

  Future<void> _ensureLocalState() => _localStateTask ??= _loadLocalState();

  Future<void> _loadLocalState() async {
    try {
      final cached = await ref.read(updateServiceProvider).loadCachedUpdate();
      if (!mounted) return;
      _publishResult(cached);
    } catch (error) {
      if (!mounted) return;
      // Unknown local state is not evidence that the tenant requires an update.
      state = state.copyWith(
        localStateLoaded: true,
        status: AppUpdateStatus.error,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> checkForUpdates({required bool force, bool silent = false}) =>
      _check(force: force, silent: silent);

  Future<void> checkOfficialSource(AppOfficialUpdateSource source) async {
    if (!mounted) return;
    await _ensureLocalState();
    // A disabled fallback action must not cancel the tenant's pending refresh.
    if (!mounted || state.versionUnsupported) return;
    await _check(force: true, source: source);
  }

  Future<void> _check({
    required bool force,
    bool silent = false,
    bool startup = false,
    AppOfficialUpdateSource? source,
  }) async {
    if (!mounted) return;
    // A background startup check preserves a user's recommendation selection.
    final generation = startup && _requestGeneration > 0
        ? null
        : ++_requestGeneration;
    final tenantGeneration = source == null ? ++_tenantRequestGeneration : null;
    bool ownsResult() => tenantGeneration == null
        ? _isCurrent(generation)
        : mounted && tenantGeneration == _tenantRequestGeneration;
    await _ensureLocalState();
    if (!ownsResult()) return;
    // An optional official-source lookup cannot lift the active tenant's gate.
    if (source != null && state.versionUnsupported) return;
    final service = ref.read(updateServiceProvider);
    final sourceChanged = state.manualOfficialSource != source;
    if (_isCurrent(generation)) {
      state = state.copyWith(
        status: AppUpdateStatus.checking,
        clearErrorMessage: true,
        clearLatestManifest: sourceChanged,
        clearCachedAt: sourceChanged,
        manualOfficialSource: source,
        clearManualOfficialSource: source == null,
        recommendationDismissed: true,
      );
    }
    try {
      final result = source == null
          ? await service.checkForUpdates(force: force)
          : await service.checkOfficialSource(source);
      if (!ownsResult()) return;
      if (!_isCurrent(generation)) {
        // Recommendation selection does not own tenant compatibility. A newly
        // verified minimum takes over the visible policy and download target,
        // and invalidates a still-pending official recommendation.
        if (source == null && result.versionUnsupported) {
          ++_requestGeneration;
          _publishResult(result);
        }
        return;
      }
      // Apply compatibility before optional prompt-history I/O.
      _publishResult(result, source: source);
      final manifest = result.latestManifest;
      if (source == null && manifest != null && result.hasUpdate) {
        var ignored = false;
        try {
          ignored = await service.isVersionIgnored(manifest);
          if (!_isCurrent(generation)) return;
          if (!ignored) await service.markVersionPrompted(manifest);
        } catch (_) {
          /* Prompt persistence cannot invalidate version policy. */
        }
        if (!_isCurrent(generation)) return;
        state = state.copyWith(recommendationDismissed: ignored);
      }
      if (!_isCurrent(generation) || silent || !force) return;
      final feedback = ref.read(uiFeedbackProvider.notifier);
      if (result.failureReason != null) {
        feedback.showError(AppMessage.updateCheckFailed());
      } else if (result.policyUnavailable) {
        feedback.showInfo(AppMessage.updatePolicyUnavailable());
      } else if (manifest != null && !result.hasUpdate) {
        feedback.showInfo(AppMessage.updateAlreadyLatest());
      }
    } catch (error) {
      if (!_isCurrent(generation)) return;
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

  void _publishResult(
    AppUpdateCheckResult result, {
    AppOfficialUpdateSource? source,
  }) {
    final status = result.failureReason != null
        ? AppUpdateStatus.error
        : result.policyUnavailable
        ? AppUpdateStatus.unavailable
        : result.latestManifest == null
        ? AppUpdateStatus.idle
        : result.hasUpdate
        ? AppUpdateStatus.updateAvailable
        : AppUpdateStatus.upToDate;
    state = state.copyWith(
      localStateLoaded: true,
      currentVersion: result.currentVersion,
      latestManifest: result.latestManifest,
      clearLatestManifest: result.latestManifest == null,
      failureReason: result.failureReason,
      clearFailureReason: result.failureReason == null,
      cachedAt: result.cachedAt,
      clearCachedAt: result.cachedAt == null,
      usedCache: result.usedCache,
      policyUnavailable: result.policyUnavailable,
      versionUnsupported: source == null
          ? result.versionUnsupported
          : state.versionUnsupported,
      recommendationDismissed: true,
      manualOfficialSource: source,
      clearManualOfficialSource: source == null,
      status: status,
      clearErrorMessage: true,
    );
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
      if (!mounted) return;
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
      if (!mounted) return;
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
    final generation = _requestGeneration;
    final previousStatus = state.status;
    final service = ref.read(updateServiceProvider);
    state = state.copyWith(
      status: AppUpdateStatus.installing,
      clearErrorMessage: true,
    );
    try {
      await service.installUpdate(manifest);
      if (!_isCurrent(generation)) return;
      state = state.copyWith(status: previousStatus);
    } on UpdateInstallPermissionRequired {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(status: AppUpdateStatus.updateAvailable);
      await service.openInstallPermissionSettings();
      if (!_isCurrent(generation)) return;
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.updatePermissionRequired());
    } catch (error) {
      if (!_isCurrent(generation)) return;
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
