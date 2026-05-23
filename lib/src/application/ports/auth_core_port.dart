import '../models/app_auth_state.dart';

abstract interface class AuthCorePort {
  Future<AppAuthState> status();

  Future<AppAuthState> login();

  Future<AppAuthState> ensureSession();

  Future<AppAuthState> refreshSession();
}
