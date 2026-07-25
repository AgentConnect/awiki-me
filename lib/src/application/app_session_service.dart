import 'dart:async';

import 'active_session_store.dart';
import 'models/app_session.dart';
import 'ports/auth_core_port.dart';
import 'ports/identity_core_port.dart';
import 'ports/im_core_runtime_port.dart';
import 'ports/realtime_core_port.dart';
import '../core/app_error_classifier.dart';

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
    implements AppSessionService {
  static const Duration _defaultRealtimeCleanupTimeout = Duration(seconds: 5);

  ImCoreAppSessionService({
    required ImCoreRuntimePort runtime,
    required IdentityCorePort identities,
    required AuthCorePort auth,
    ActiveSessionStore? activeSessionStore,
    String? expectedDidDomain,
    RealtimeCorePort? realtime,
    Duration realtimeCleanupTimeout = _defaultRealtimeCleanupTimeout,
  }) : _runtime = runtime,
       _identities = identities,
       _auth = auth,
       _activeSessionStore = activeSessionStore,
       _expectedDidDomain = _normalizeDidDomain(expectedDidDomain),
       _realtime = realtime,
       _realtimeCleanupTimeout = realtimeCleanupTimeout;

  final ImCoreRuntimePort _runtime;
  final IdentityCorePort _identities;
  final AuthCorePort _auth;
  final ActiveSessionStore? _activeSessionStore;
  final String? _expectedDidDomain;
  final RealtimeCorePort? _realtime;
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
    if (_current != null) {
      markSessionTransitionCommitted(transition);
      return _current;
    }
    await _runtime.open();
    _requireCurrentTransition(transition);
    final activeIdentityId = await _activeSessionStore?.readActiveIdentityId();
    _requireCurrentTransition(transition);
    if (activeIdentityId == null) {
      return null;
    }
    final identity = await _localIdentityFor(
      activeIdentityId,
      allowResolve: false,
      throwOnDomainMismatch: false,
    );
    if (identity == null) {
      _requireCurrentTransition(transition);
      await _activeSessionStore?.clearActiveIdentityId();
      return null;
    }
    return _activateIdentity(identity, transition: transition);
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
    late final AppSession candidate;
    try {
      final auth = await _auth.ensureSession();
      _requireCurrentTransition(transition);
      candidate = identity.copyWith(
        authenticated: auth.authenticated,
        expiresAt: auth.expiresAt,
        jwtToken: auth.bearerToken,
      );
    } catch (error) {
      if (!isTransientNetworkAppError(error)) {
        rethrow;
      }
      _requireCurrentTransition(transition);
      candidate = identity.copyWith(
        authenticated: false,
        expiresAt: null,
        jwtToken: null,
      );
    }
    if (initializeIdentitySession != null) {
      await initializeIdentitySession(candidate);
      _requireCurrentTransition(transition);
    }
    await _activeSessionStore?.writeActiveIdentityId(identity.identityId);
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
    final session = _current;
    if (session == null ||
        transition == null ||
        !isSessionTransitionCurrent(transition)) {
      return null;
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
      () => _deleteLocalIdentity(identityIdOrAlias, transition),
    );
  }

  Future<AppSession> _deleteLocalIdentity(
    String identityIdOrAlias,
    AppSessionTransition transition,
  ) async {
    _requireCurrentTransition(transition);
    final selector = identityIdOrAlias.trim();
    if (!_runtime.isOpen) {
      await _runtime.open();
    }
    _requireCurrentTransition(transition);
    final current = _current;
    final deletingCurrent =
        current != null && _matchesIdentity(current, selector);
    if (deletingCurrent) {
      _current = null;
      clearCommittedSessionTransition();
      await _stopRealtimeBestEffort();
    }
    final deleted = await _identities.deleteLocalIdentity(identityIdOrAlias);
    if (current != null &&
        (_matchesIdentity(current, selector) ||
            _matchesIdentity(current, deleted.identityId) ||
            _matchesIdentity(current, deleted.did) ||
            (deleted.localAlias != null &&
                _matchesIdentity(current, deleted.localAlias!)) ||
            (deleted.handle != null &&
                _matchesIdentity(current, deleted.handle!)))) {
      try {
        await _activeSessionStore?.clearActiveIdentityId();
        await _runtime.dispose();
      } finally {
        _current = null;
        clearCommittedSessionTransition();
      }
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
