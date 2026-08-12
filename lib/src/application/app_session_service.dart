import 'dart:async';

import 'active_session_store.dart';
import 'app_bootstrap_epoch_barrier.dart';
import 'models/app_session.dart';
import 'ports/auth_core_port.dart';
import 'ports/identity_core_port.dart';
import 'ports/im_core_runtime_port.dart';
import 'ports/legacy_identity_upgrade_port.dart';
import 'ports/realtime_core_port.dart';
import '../core/app_error_classifier.dart';
import '../domain/entities/session_identity.dart';

abstract interface class AppSessionService {
  AppSessionTransition beginSessionTransition();

  bool isSessionTransitionCurrent(AppSessionTransition transition);

  bool isLatestSessionTransition(AppSessionTransition transition);

  void cancelPendingSessionTransition(AppSessionTransition transition);

  Future<bool> abortSessionIfCurrent(AppSessionLease lease);

  Future<AppSession?> restoreSession();

  Future<AppSession?> currentSession();

  Future<AppSessionLease?> currentSessionLease();

  Future<List<AppSession>> listLocalIdentities();

  Future<AppSession> loginWithIdentity(
    String identityIdOrAlias, {
    AppSessionTransition? transition,
  });

  Future<AppSession> activateIdentity(
    AppSession identity, {
    AppSessionTransition? transition,
    Future<void> Function(AppSession session)? initializeIdentitySession,
  });

  Future<AppSession?> refreshSession();

  Future<void> logout();

  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias);
}

abstract interface class LocalIdentityDataDeletionSessionService {
  Future<AppSession> deleteLocalIdentityData(String identityIdOrAlias);
}

final class AppSessionTransition {
  AppSessionTransition._(this._previousCommittedTransition);

  final AppSessionTransition? _previousCommittedTransition;

  bool isPredecessorLease(AppSessionLease lease) {
    return identical(_previousCommittedTransition, lease.transition);
  }
}

final class AppSessionLease {
  const AppSessionLease({required this.session, required this.transition});

  final AppSession session;
  final AppSessionTransition transition;
}

mixin AppSessionTransitionGuard {
  AppSessionTransition? _activeSessionTransition;
  AppSessionTransition? _committedSessionTransition;
  AppSessionTransition? _latestSessionTransition;

  AppSessionTransition beginSessionTransition() {
    final transition = AppSessionTransition._(_committedSessionTransition);
    _activeSessionTransition = transition;
    _latestSessionTransition = transition;
    return transition;
  }

  bool isSessionTransitionCurrent(AppSessionTransition transition) {
    return identical(_activeSessionTransition, transition);
  }

  bool isLatestSessionTransition(AppSessionTransition transition) {
    return identical(_latestSessionTransition, transition);
  }

  void cancelPendingSessionTransition(AppSessionTransition transition) {
    if (!isSessionTransitionCurrent(transition) ||
        identical(_committedSessionTransition, transition)) {
      return;
    }
    _activeSessionTransition =
        _committedSessionTransition ?? AppSessionTransition._(null);
  }

  Future<bool> abortSessionIfCurrent(AppSessionLease lease) async => false;

  bool isCommittedSessionTransition(AppSessionTransition transition) {
    return identical(_committedSessionTransition, transition);
  }

  void restoreCommittedSessionTransition(AppSessionTransition transition) {
    if (isCommittedSessionTransition(transition)) {
      _activeSessionTransition = transition;
    }
  }

  void markSessionTransitionCommitted(AppSessionTransition transition) {
    if (!isSessionTransitionCurrent(transition)) {
      throw const AppSessionTransitionSuperseded();
    }
    _committedSessionTransition = transition;
  }

  void clearCommittedSessionTransition() {
    _committedSessionTransition = null;
  }

  AppSessionLease? sessionLeaseFor(AppSession? session) {
    if (session == null) {
      return null;
    }
    var transition = _committedSessionTransition;
    if (transition == null && _activeSessionTransition == null) {
      transition = beginSessionTransition();
      markSessionTransitionCommitted(transition);
    }
    if (transition == null || !isSessionTransitionCurrent(transition)) {
      return null;
    }
    return AppSessionLease(session: session, transition: transition);
  }
}

class ImCoreAppSessionService
    with AppSessionTransitionGuard
    implements AppSessionService, LocalIdentityDataDeletionSessionService {
  static const Duration _defaultRealtimeCleanupTimeout = Duration(seconds: 5);

  ImCoreAppSessionService({
    required ImCoreRuntimePort runtime,
    required IdentityCorePort identities,
    required AuthCorePort auth,
    LegacyIdentityUpgradePort? legacyUpgrades,
    ActiveSessionStore? activeSessionStore,
    String? expectedDidDomain,
    RealtimeCorePort? realtime,
    required AppBootstrapEpochBarrierPort bootstrapEpochBarrier,
    Duration realtimeCleanupTimeout = _defaultRealtimeCleanupTimeout,
  }) : _runtime = runtime,
       _identities = identities,
       _auth = auth,
       _legacyUpgrades = legacyUpgrades,
       _activeSessionStore = activeSessionStore,
       _expectedDidDomain = _normalizeDidDomain(expectedDidDomain),
       _realtime = realtime,
       _bootstrapEpochBarrier = bootstrapEpochBarrier,
       _realtimeCleanupTimeout = realtimeCleanupTimeout;

  final ImCoreRuntimePort _runtime;
  final IdentityCorePort _identities;
  final AuthCorePort _auth;
  final LegacyIdentityUpgradePort? _legacyUpgrades;
  final ActiveSessionStore? _activeSessionStore;
  final String? _expectedDidDomain;
  final RealtimeCorePort? _realtime;
  final AppBootstrapEpochBarrierPort _bootstrapEpochBarrier;
  final Duration _realtimeCleanupTimeout;

  AppSession? _current;
  Future<void> _sessionTransitionTail = Future<void>.value();

  @override
  Future<AppSession?> restoreSession() {
    final transition = beginSessionTransition();
    return _runOwnedSessionTransition(
      transition,
      () => _restoreSession(transition),
    );
  }

  Future<AppSession?> _restoreSession(AppSessionTransition transition) async {
    _requireCurrentTransition(transition);
    final current = _current;
    if (current != null) {
      final ready = await _revalidateCurrentSessionEpoch(current, transition);
      _current = ready.session;
      markSessionTransitionCommitted(transition);
      return ready.session;
    }
    await _runtime.open();
    _requireCurrentTransition(transition);
    final activeIdentityId = await _activeSessionStore?.readActiveIdentityId();
    _requireCurrentTransition(transition);
    if (activeIdentityId == null) {
      return null;
    }
    var identity = await _localIdentityFor(
      activeIdentityId,
      allowResolve: false,
      throwOnDomainMismatch: false,
    );
    if (identity == null) {
      _requireCurrentTransition(transition);
      await _activeSessionStore?.clearActiveIdentityId();
      return null;
    }
    if (!await _ensureLegacyIdentityReady(identity.identityId)) {
      return null;
    }
    _requireCurrentTransition(transition);
    identity = await _localIdentityFor(
      activeIdentityId,
      allowResolve: false,
      throwOnDomainMismatch: false,
    );
    if (identity == null) {
      return null;
    }
    return _activateIdentity(identity, transition: transition);
  }

  Future<bool> _ensureLegacyIdentityReady(String identityId) async {
    final legacyUpgrades = _legacyUpgrades;
    if (legacyUpgrades == null) {
      return true;
    }
    var status = await legacyUpgrades.legacyUpgradeStatus(identityId);
    if (status.phase == LegacyIdentityUpgradePhase.completed) {
      return true;
    }
    status = await legacyUpgrades.upgradeLegacyIdentity(identityId);
    return status.phase == LegacyIdentityUpgradePhase.completed;
  }

  @override
  Future<AppSession?> currentSession() async {
    return _current;
  }

  @override
  Future<AppSessionLease?> currentSessionLease() async {
    return sessionLeaseFor(_current);
  }

  @override
  Future<bool> abortSessionIfCurrent(AppSessionLease lease) {
    if (!isSessionTransitionCurrent(lease.transition) ||
        !isCommittedSessionTransition(lease.transition)) {
      return Future<bool>.value(false);
    }
    final abortTransition = beginSessionTransition();
    return _runSessionTransition(
      () => _abortSessionIfStillCurrent(lease, abortTransition),
    );
  }

  Future<bool> _abortSessionIfStillCurrent(
    AppSessionLease lease,
    AppSessionTransition abortTransition,
  ) async {
    if (!isSessionTransitionCurrent(abortTransition) ||
        !isCommittedSessionTransition(lease.transition)) {
      return false;
    }
    final current = _current;
    if (current == null || current.identityId != lease.session.identityId) {
      restoreCommittedSessionTransition(lease.transition);
      return false;
    }
    _current = null;
    clearCommittedSessionTransition();
    try {
      final activeIdentityId = await _activeSessionStore
          ?.readActiveIdentityId();
      if (activeIdentityId == lease.session.identityId) {
        await _activeSessionStore?.clearActiveIdentityId();
      }
    } finally {
      await _stopRealtimeBestEffort();
    }
    return true;
  }

  @override
  Future<List<AppSession>> listLocalIdentities() {
    return _runSessionTransition(_listLocalIdentities);
  }

  Future<List<AppSession>> _listLocalIdentities() async {
    if (!_runtime.isOpen) {
      await _runtime.open();
    }
    return (await _identities.listLocalIdentities())
        .where(_isExpectedDomainIdentity)
        .toList();
  }

  @override
  Future<AppSession> loginWithIdentity(
    String identityIdOrAlias, {
    AppSessionTransition? transition,
  }) {
    final requestedTransition = transition ?? beginSessionTransition();
    return _runOwnedSessionTransition(
      requestedTransition,
      () => _loginWithIdentity(identityIdOrAlias, requestedTransition),
    );
  }

  Future<AppSession> _loginWithIdentity(
    String identityIdOrAlias,
    AppSessionTransition transition,
  ) async {
    _requireCurrentTransition(transition);
    if (!_runtime.isOpen) {
      await _runtime.open();
    }
    _requireCurrentTransition(transition);
    final identity = await _localIdentityFor(identityIdOrAlias);
    _requireCurrentTransition(transition);
    if (identity == null) {
      throw StateError('local_identity_not_found: $identityIdOrAlias');
    }
    return _activateIdentity(identity, transition: transition);
  }

  @override
  Future<AppSession> activateIdentity(
    AppSession identity, {
    AppSessionTransition? transition,
    Future<void> Function(AppSession session)? initializeIdentitySession,
  }) {
    final requestedTransition = transition ?? beginSessionTransition();
    return _runOwnedSessionTransition(
      requestedTransition,
      () => _activateIdentity(
        identity,
        transition: requestedTransition,
        initializeIdentitySession: initializeIdentitySession,
      ),
    );
  }

  Future<AppSession> _activateIdentity(
    AppSession identity, {
    required AppSessionTransition transition,
    Future<void> Function(AppSession session)? initializeIdentitySession,
  }) async {
    _requireCurrentTransition(transition);
    if (!_runtime.isOpen) {
      await _runtime.open();
    }
    _requireCurrentTransition(transition);
    _assertIdentityDomain(identity);
    await _runtime.ensureIdentityVault(identity.identityId);
    _requireCurrentTransition(transition);
    final previousActiveIdentityId = await _activeSessionStore
        ?.readActiveIdentityId();
    _requireCurrentTransition(transition);
    final shouldReleaseCurrentOwner =
        _current != null || (_realtime?.isRunning ?? false);
    _current = null;
    clearCommittedSessionTransition();
    if (shouldReleaseCurrentOwner) {
      await _stopRealtimeBestEffort();
    }
    _requireCurrentTransition(transition);
    await _runtime.switchIdentity(identity.identityId);
    _requireCurrentTransition(transition);
    late final SessionAccountBinding accountBinding;
    try {
      accountBinding = await _identities.activeSyncAccountBinding();
      _requireCurrentTransition(transition);
      _assertActiveSyncAccountBinding(identity, accountBinding);
    } catch (error, stackTrace) {
      _requireCurrentTransition(transition);
      await _clearFailedActivationState();
      Error.throwWithStackTrace(error, stackTrace);
    }
    final boundIdentity = identity.copyWith(accountBinding: accountBinding);
    try {
      await _bootstrapEpochBarrier.ensureReady(
        identity: boundIdentity,
        binding: accountBinding,
      );
      _requireCurrentTransition(transition);
    } catch (error, stackTrace) {
      _requireCurrentTransition(transition);
      await _clearFailedActivationState();
      Error.throwWithStackTrace(error, stackTrace);
    }
    late final AppSession candidate;
    try {
      final auth = await _auth.ensureSession();
      _requireCurrentTransition(transition);
      candidate = boundIdentity.copyWith(
        authenticated: auth.authenticated,
        expiresAt: auth.expiresAt,
        jwtToken: auth.bearerToken,
      );
    } catch (error) {
      _requireCurrentTransition(transition);
      if (!isTransientNetworkAppError(error)) {
        await _clearFailedActivationState();
        rethrow;
      }
      candidate = boundIdentity.copyWith(
        authenticated: false,
        clearExpiresAt: true,
        clearJwtToken: true,
      );
    }
    if (initializeIdentitySession != null) {
      await initializeIdentitySession(candidate);
      _requireCurrentTransition(transition);
    }
    try {
      await _activeSessionStore?.writeActiveIdentityId(identity.identityId);
    } catch (error, stackTrace) {
      _current = null;
      try {
        final persistedIdentityId = await _activeSessionStore
            ?.readActiveIdentityId();
        if (persistedIdentityId != previousActiveIdentityId) {
          await _activeSessionStore?.clearActiveIdentityId();
        }
      } catch (_) {
        // Preserve the authoritative activation write failure.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (!isSessionTransitionCurrent(transition)) {
      if (previousActiveIdentityId == null) {
        await _activeSessionStore?.clearActiveIdentityId();
      } else {
        await _activeSessionStore?.writeActiveIdentityId(
          previousActiveIdentityId,
        );
      }
      throw const AppSessionTransitionSuperseded();
    }
    _current = candidate;
    markSessionTransitionCommitted(transition);
    return candidate;
  }

  @override
  Future<AppSession?> refreshSession() {
    final transition = _committedSessionTransition;
    return _runSessionTransition(() => _refreshSession(transition));
  }

  Future<AppSession?> _refreshSession(AppSessionTransition? transition) async {
    var session = _current;
    if (session == null ||
        transition == null ||
        !isSessionTransitionCurrent(transition)) {
      return null;
    }
    final ready = await _revalidateCurrentSessionEpoch(session, transition);
    session = ready.session;
    if (ready.reactivated) {
      return session;
    }
    final auth = await _auth.refreshSession();
    if (!isSessionTransitionCurrent(transition) ||
        !identical(_current, session)) {
      return null;
    }
    final refreshed = session.copyWith(
      authenticated: auth.authenticated,
      expiresAt: auth.expiresAt,
      jwtToken: auth.bearerToken ?? session.jwtToken,
    );
    _current = refreshed;
    return refreshed;
  }

  Future<({AppSession session, bool reactivated})>
  _revalidateCurrentSessionEpoch(
    AppSession session,
    AppSessionTransition transition,
  ) async {
    _requireCurrentTransition(transition);
    try {
      final binding = await _identities.activeSyncAccountBinding();
      _requireCurrentTransition(transition);
      if (binding.ownerIdentityId != session.identityId) {
        throw StateError('active_sync_account_binding_identity_mismatch');
      }
      if (binding.currentDid != session.did) {
        final latest = await _localIdentityFor(
          session.identityId,
          allowResolve: false,
        );
        _requireCurrentTransition(transition);
        if (latest == null) {
          throw StateError('active_sync_account_binding_identity_missing');
        }
        _assertActiveSyncAccountBinding(latest, binding);
        final activated = await _activateIdentity(
          latest,
          transition: transition,
        );
        return (session: activated, reactivated: true);
      }
      _assertActiveSyncAccountBinding(session, binding);
      final bound = session.copyWith(accountBinding: binding);
      await _bootstrapEpochBarrier.ensureReady(
        identity: bound,
        binding: binding,
      );
      _requireCurrentTransition(transition);
      _current = bound;
      return (session: bound, reactivated: false);
    } catch (error, stackTrace) {
      if (!isSessionTransitionCurrent(transition)) {
        throw const AppSessionTransitionSuperseded();
      }
      await _failClosedCurrentSession();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> logout() {
    final transition = beginSessionTransition();
    return _runOwnedSessionTransition(transition, () => _logout(transition));
  }

  Future<void> _logout(AppSessionTransition transition) async {
    _requireCurrentTransition(transition);
    _current = null;
    clearCommittedSessionTransition();
    try {
      await _activeSessionStore?.clearActiveIdentityId();
    } finally {
      await _stopRealtimeBestEffort();
    }
  }

  Future<void> disposeRuntime() {
    final transition = beginSessionTransition();
    return _runOwnedSessionTransition(
      transition,
      () => _disposeRuntime(transition),
    );
  }

  Future<void> _disposeRuntime(AppSessionTransition transition) async {
    _requireCurrentTransition(transition);
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> disposeStep(Future<void> Function() action) async {
      try {
        await action().timeout(_realtimeCleanupTimeout);
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    try {
      final realtime = _realtime;
      if (realtime != null) {
        await disposeStep(realtime.stop);
      }
      await disposeStep(_runtime.dispose);
    } finally {
      _current = null;
      clearCommittedSessionTransition();
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
  }

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) {
    final transition = beginSessionTransition();
    return _runOwnedSessionTransition(
      transition,
      () => _deleteLocalIdentity(
        identityIdOrAlias,
        transition,
        deleteOwnerData: false,
      ),
    );
  }

  @override
  Future<AppSession> deleteLocalIdentityData(String identityIdOrAlias) {
    final transition = beginSessionTransition();
    return _runOwnedSessionTransition(
      transition,
      () => _deleteLocalIdentity(
        identityIdOrAlias,
        transition,
        deleteOwnerData: true,
      ),
    );
  }

  Future<AppSession> _deleteLocalIdentity(
    String identityIdOrAlias,
    AppSessionTransition transition, {
    required bool deleteOwnerData,
  }) async {
    _requireCurrentTransition(transition);
    final selector = identityIdOrAlias.trim();
    if (!_runtime.isOpen) {
      await _runtime.open();
    }
    _requireCurrentTransition(transition);
    final current = _current;
    final deletingCurrent =
        current != null && _matchesIdentity(current, selector);
    Future<void>? realtimeCleanup;
    if (deletingCurrent) {
      _current = null;
      clearCommittedSessionTransition();
      await _activeSessionStore?.clearActiveIdentityId();
      realtimeCleanup = _stopRealtimeBestEffort();
      if (deleteOwnerData) {
        await realtimeCleanup;
      }
    }
    final deleted = deleteOwnerData
        ? await _deleteLocalIdentityData(identityIdOrAlias)
        : await _identities.deleteLocalIdentity(identityIdOrAlias);
    if (current != null &&
        (_matchesIdentity(current, selector) ||
            _matchesIdentity(current, deleted.identityId) ||
            _matchesIdentity(current, deleted.did) ||
            (deleted.localAlias != null &&
                _matchesIdentity(current, deleted.localAlias!)) ||
            (deleted.handle != null &&
                _matchesIdentity(current, deleted.handle!)))) {
      _current = null;
      unawaited(_cleanupRetiredRuntimeBestEffort(realtimeCleanup));
    } else {
      final activeIdentityId = await _activeSessionStore
          ?.readActiveIdentityId();
      if (activeIdentityId == deleted.identityId) {
        await _activeSessionStore?.clearActiveIdentityId();
      }
    }
    _requireCurrentTransition(transition);
    if (_current != null) {
      markSessionTransitionCommitted(transition);
    }
    return deleted;
  }

  Future<AppSession> _deleteLocalIdentityData(String identityIdOrAlias) {
    final identities = _identities;
    if (identities is! LocalIdentityDataDeletionPort) {
      throw UnsupportedError('local_identity_data_deletion_unavailable');
    }
    return (identities as LocalIdentityDataDeletionPort)
        .deleteLocalIdentityData(identityIdOrAlias);
  }

  void _requireCurrentTransition(AppSessionTransition transition) {
    if (!isSessionTransitionCurrent(transition)) {
      throw const AppSessionTransitionSuperseded();
    }
  }

  Future<AppSession?> _localIdentityFor(
    String identityIdOrAlias, {
    bool allowResolve = true,
    bool throwOnDomainMismatch = true,
  }) async {
    final trimmed = identityIdOrAlias.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        identityIdOrAlias,
        'identityIdOrAlias',
        'must not be empty',
      );
    }
    final identities = await _identities.listLocalIdentities();
    for (final identity in identities) {
      if (!_matchesIdentity(identity, trimmed)) {
        continue;
      }
      if (_isExpectedDomainIdentity(identity)) {
        return identity;
      }
      if (throwOnDomainMismatch) {
        _assertIdentityDomain(identity);
      }
      return null;
    }
    if (!allowResolve) {
      return null;
    }
    final resolved = await _identities.resolveIdentity(trimmed);
    _assertIdentityDomain(resolved);
    return resolved;
  }

  bool _isExpectedDomainIdentity(AppSession identity) {
    final expected = _expectedDidDomain;
    return expected == null || _didDomain(identity.did) == expected;
  }

  void _assertIdentityDomain(AppSession identity) {
    final expected = _expectedDidDomain;
    if (expected == null) {
      return;
    }
    final actual = _didDomain(identity.did);
    if (actual == null || actual != expected) {
      throw StateError(
        'identity_domain_mismatch: expected $expected, got ${actual ?? 'unknown'}',
      );
    }
  }

  Future<void> _stopRealtimeBestEffort() async {
    final realtime = _realtime;
    if (realtime == null) {
      return;
    }
    try {
      await realtime.stop().timeout(_realtimeCleanupTimeout);
    } on TimeoutException {
      return;
    } catch (_) {
      return;
    }
  }

  Future<T> _runSessionTransition<T>(Future<T> Function() action) {
    final previous = _sessionTransitionTail;
    final completed = Completer<void>();
    _sessionTransitionTail = completed.future;

    return () async {
      await previous;
      try {
        return await action();
      } finally {
        if (!completed.isCompleted) {
          completed.complete();
        }
      }
    }();
  }

  Future<T> _runOwnedSessionTransition<T>(
    AppSessionTransition transition,
    Future<T> Function() action,
  ) {
    return _runSessionTransition(() async {
      try {
        return await action();
      } catch (_) {
        if (!isSessionTransitionCurrent(transition)) {
          throw const AppSessionTransitionSuperseded();
        }
        cancelPendingSessionTransition(transition);
        rethrow;
      }
    });
  }

  Future<void> _disposeRuntimeBestEffort() async {
    try {
      await _runtime.dispose().timeout(_realtimeCleanupTimeout);
    } on TimeoutException {
      return;
    } catch (_) {
      return;
    }
  }

  Future<void> _cleanupRetiredRuntimeBestEffort(
    Future<void>? realtimeCleanup,
  ) async {
    await (realtimeCleanup ?? _stopRealtimeBestEffort());
    await _disposeRuntimeBestEffort();
  }

  Future<void> _clearFailedActivationState() async {
    _current = null;
    try {
      await _activeSessionStore?.clearActiveIdentityId();
    } catch (_) {
      // The activation failure remains authoritative.
    }
  }

  Future<void> _failClosedCurrentSession() async {
    _current = null;
    clearCommittedSessionTransition();
    try {
      await _activeSessionStore?.clearActiveIdentityId();
    } catch (_) {
      // Preserve the epoch validation failure.
    }
    if (_realtime?.isRunning ?? false) {
      await _stopRealtimeBestEffort();
    }
  }
}

class AppSessionTransitionSuperseded implements Exception {
  const AppSessionTransitionSuperseded();

  @override
  String toString() => 'session_transition_superseded';
}

bool _matchesIdentity(AppSession identity, String value) {
  return identity.identityId == value ||
      identity.did == value ||
      identity.localAlias == value ||
      _matchesHandle(identity.handle, value);
}

bool _matchesHandle(String? handle, String value) {
  final expected = _normalizeHandleSelector(handle);
  final actual = _normalizeHandleSelector(value);
  if (expected == null || actual == null) {
    return false;
  }
  if (expected == actual) {
    return true;
  }
  return _handleLocalPart(expected) == actual;
}

String? _normalizeHandleSelector(String? value) {
  final trimmed = _trimLeadingAt(value?.trim())?.toLowerCase();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _handleLocalPart(String handle) {
  final dot = handle.indexOf('.');
  return dot < 0 ? handle : handle.substring(0, dot);
}

String? _trimLeadingAt(String? value) {
  if (value == null) {
    return null;
  }
  var start = 0;
  while (start < value.length && value.codeUnitAt(start) == 0x40) {
    start += 1;
  }
  return value.substring(start);
}

String? _normalizeDidDomain(String? value) {
  final trimmed = value?.trim().toLowerCase();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _didDomain(String did) {
  final segments = did.trim().split(':');
  if (segments.length < 4 || segments[0] != 'did' || segments[1] != 'wba') {
    return null;
  }
  final domain = segments[2].trim().toLowerCase();
  return domain.isEmpty ? null : domain;
}

void _assertActiveSyncAccountBinding(
  AppSession identity,
  SessionAccountBinding binding,
) {
  _requireExactBindingValue(
    binding.ownerIdentityId,
    'active_sync_account_binding_owner_unavailable',
  );
  _requireExactBindingValue(
    binding.accountId,
    'active_sync_account_binding_account_unavailable',
  );
  _requireExactBindingValue(
    binding.currentDid,
    'active_sync_account_binding_did_unavailable',
  );
  _requireExactBindingValue(
    binding.protocolDeviceId,
    'active_sync_account_binding_device_unavailable',
  );
  if (binding.ownerIdentityId != identity.identityId ||
      binding.currentDid != identity.did) {
    throw StateError('active_sync_account_binding_identity_mismatch');
  }
  if (binding.protocolDeviceId == 'default') {
    throw StateError('active_sync_account_binding_device_reserved');
  }
  if (!_isCanonicalPositiveDecimal(
        binding.identityGeneration,
        maxDigits: 255,
      ) ||
      !_isCanonicalPositiveDecimal(binding.deviceAuthGeneration)) {
    throw StateError('active_sync_account_binding_generation_invalid');
  }
}

void _requireExactBindingValue(String value, String code) {
  if (value.isEmpty || value.trim() != value) {
    throw StateError(code);
  }
}

bool _isCanonicalPositiveDecimal(String value, {int? maxDigits}) {
  if (value.isEmpty ||
      (maxDigits != null && value.length > maxDigits) ||
      value.codeUnitAt(0) < 0x31 ||
      value.codeUnitAt(0) > 0x39) {
    return false;
  }
  for (var index = 1; index < value.length; index += 1) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit < 0x30 || codeUnit > 0x39) {
      return false;
    }
  }
  return true;
}
