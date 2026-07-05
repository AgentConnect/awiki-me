import 'dart:async';

import 'active_session_store.dart';
import 'models/app_session.dart';
import 'ports/auth_core_port.dart';
import 'ports/identity_core_port.dart';
import 'ports/im_core_runtime_port.dart';
import 'ports/realtime_core_port.dart';
import '../core/app_error_classifier.dart';

abstract interface class AppSessionService {
  Future<AppSession?> restoreSession();

  Future<AppSession?> currentSession();

  Future<List<AppSession>> listLocalIdentities();

  Future<AppSession> loginWithIdentity(String identityIdOrAlias);

  Future<AppSession> activateIdentity(AppSession identity);

  Future<AppSession?> refreshSession();

  Future<void> logout();

  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias);
}

class ImCoreAppSessionService implements AppSessionService {
  static const Duration _logoutCleanupTimeout = Duration(seconds: 5);

  ImCoreAppSessionService({
    required ImCoreRuntimePort runtime,
    required IdentityCorePort identities,
    required AuthCorePort auth,
    ActiveSessionStore? activeSessionStore,
    String? expectedDidDomain,
    RealtimeCorePort? realtime,
  }) : _runtime = runtime,
       _identities = identities,
       _auth = auth,
       _activeSessionStore = activeSessionStore,
       _expectedDidDomain = _normalizeDidDomain(expectedDidDomain),
       _realtime = realtime;

  final ImCoreRuntimePort _runtime;
  final IdentityCorePort _identities;
  final AuthCorePort _auth;
  final ActiveSessionStore? _activeSessionStore;
  final String? _expectedDidDomain;
  final RealtimeCorePort? _realtime;

  AppSession? _current;

  @override
  Future<AppSession?> restoreSession() async {
    if (_current != null) {
      return _current;
    }
    await _runtime.open();
    final activeIdentityId = await _activeSessionStore?.readActiveIdentityId();
    if (activeIdentityId == null) {
      return null;
    }
    final identity = await _localIdentityFor(
      activeIdentityId,
      allowResolve: false,
      throwOnDomainMismatch: false,
    );
    if (identity == null) {
      await _activeSessionStore?.clearActiveIdentityId();
      return null;
    }
    return activateIdentity(identity);
  }

  @override
  Future<AppSession?> currentSession() async {
    return _current;
  }

  @override
  Future<List<AppSession>> listLocalIdentities() async {
    if (!_runtime.isOpen) {
      await _runtime.open();
    }
    return (await _identities.listLocalIdentities())
        .where(_isExpectedDomainIdentity)
        .toList();
  }

  @override
  Future<AppSession> loginWithIdentity(String identityIdOrAlias) async {
    if (!_runtime.isOpen) {
      await _runtime.open();
    }
    final identity = await _localIdentityFor(identityIdOrAlias);
    if (identity == null) {
      throw StateError('local_identity_not_found: $identityIdOrAlias');
    }
    return activateIdentity(identity);
  }

  @override
  Future<AppSession> activateIdentity(AppSession identity) async {
    if (!_runtime.isOpen) {
      await _runtime.open();
    }
    _assertIdentityDomain(identity);
    await _runtime.ensureIdentityVault(identity.identityId);
    await _runtime.switchIdentity(identity.identityId);
    try {
      final auth = await _auth.ensureSession();
      _current = identity.copyWith(
        authenticated: auth.authenticated,
        expiresAt: auth.expiresAt,
        jwtToken: auth.bearerToken,
      );
    } catch (error) {
      if (!isTransientNetworkAppError(error)) {
        rethrow;
      }
      _current = identity.copyWith(
        authenticated: false,
        expiresAt: null,
        jwtToken: null,
      );
    }
    await _activeSessionStore?.writeActiveIdentityId(identity.identityId);
    return _current!;
  }

  @override
  Future<AppSession?> refreshSession() async {
    final session = _current;
    if (session == null) {
      return null;
    }
    final auth = await _auth.refreshSession();
    _current = session.copyWith(
      authenticated: auth.authenticated,
      expiresAt: auth.expiresAt,
      jwtToken: auth.bearerToken ?? session.jwtToken,
    );
    return _current;
  }

  @override
  Future<void> logout() async {
    try {
      await _activeSessionStore?.clearActiveIdentityId();
      await _stopRealtimeBestEffort();
      await _disposeRuntimeBestEffort();
    } finally {
      _current = null;
    }
  }

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) async {
    final selector = identityIdOrAlias.trim();
    if (!_runtime.isOpen) {
      await _runtime.open();
    }
    final current = _current;
    final deletingCurrent =
        current != null && _matchesIdentity(current, selector);
    if (deletingCurrent) {
      await _realtime?.stop();
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
      }
    } else {
      final activeIdentityId = await _activeSessionStore
          ?.readActiveIdentityId();
      if (activeIdentityId == deleted.identityId) {
        await _activeSessionStore?.clearActiveIdentityId();
      }
    }
    return deleted;
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
      await realtime.stop().timeout(_logoutCleanupTimeout);
    } on TimeoutException {
      return;
    } catch (_) {
      return;
    }
  }

  Future<void> _disposeRuntimeBestEffort() async {
    try {
      await _runtime.dispose().timeout(_logoutCleanupTimeout);
    } on TimeoutException {
      return;
    } catch (_) {
      return;
    }
  }
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
