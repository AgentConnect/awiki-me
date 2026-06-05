import 'models/app_session.dart';
import 'ports/auth_core_port.dart';
import 'ports/identity_core_port.dart';
import 'ports/im_core_runtime_port.dart';
import 'ports/realtime_core_port.dart';

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
  ImCoreAppSessionService({
    required ImCoreRuntimePort runtime,
    required IdentityCorePort identities,
    required AuthCorePort auth,
    RealtimeCorePort? realtime,
  }) : _runtime = runtime,
       _identities = identities,
       _auth = auth,
       _realtime = realtime;

  final ImCoreRuntimePort _runtime;
  final IdentityCorePort _identities;
  final AuthCorePort _auth;
  final RealtimeCorePort? _realtime;

  AppSession? _current;

  @override
  Future<AppSession?> restoreSession() async {
    if (_current != null) {
      return _current;
    }
    await _runtime.open();
    final identity = await _identities.defaultIdentity();
    if (identity == null) {
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
    return _identities.listLocalIdentities();
  }

  @override
  Future<AppSession> loginWithIdentity(String identityIdOrAlias) async {
    if (!_runtime.isOpen) {
      await _runtime.open();
    }
    final identity = await _localIdentityFor(identityIdOrAlias);
    return activateIdentity(identity);
  }

  @override
  Future<AppSession> activateIdentity(AppSession identity) async {
    if (!_runtime.isOpen) {
      await _runtime.open();
    }
    await _runtime.switchIdentity(identity.identityId);
    final auth = await _auth.ensureSession();
    _current = identity.copyWith(
      authenticated: auth.authenticated,
      expiresAt: auth.expiresAt,
      jwtToken: auth.bearerToken,
    );
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
      await _realtime?.stop();
      await _runtime.dispose();
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
        await _runtime.dispose();
      } finally {
        _current = null;
      }
    }
    return deleted;
  }

  Future<AppSession> _localIdentityFor(String identityIdOrAlias) async {
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
      if (_matchesIdentity(identity, trimmed)) {
        return identity;
      }
    }
    return _identities.resolveIdentity(trimmed);
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
