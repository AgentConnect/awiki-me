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
  Future<AppSession> loginWithIdentity(String identityIdOrAlias) {
    // TODO(im-core): enable explicit local identity switching after the SDK
    // exposes stable active/default identity semantics and awiki-me stores an
    // activeIdentityId preference. First cut only restores SDK default identity.
    throw UnsupportedError(
      'IM Core explicit local identity login is not available yet',
    );
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
    );
    return _current;
  }

  @override
  Future<void> logout() async {
    _current = null;
    await _realtime?.stop();
    await _runtime.dispose();
  }
}
