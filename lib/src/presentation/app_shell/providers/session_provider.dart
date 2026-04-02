import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/bridge_capabilities.dart';
import '../../../domain/entities/session_identity.dart';

class SessionState {
  const SessionState({
    this.capabilities,
    this.session,
    this.localCredentials = const <SessionIdentity>[],
  });

  final BridgeCapabilities? capabilities;
  final SessionIdentity? session;
  final List<SessionIdentity> localCredentials;

  bool get isLoggedIn => session != null;

  SessionState copyWith({
    BridgeCapabilities? capabilities,
    SessionIdentity? session,
    List<SessionIdentity>? localCredentials,
    bool clearSession = false,
  }) {
    return SessionState(
      capabilities: capabilities ?? this.capabilities,
      session: clearSession ? null : (session ?? this.session),
      localCredentials: localCredentials ?? this.localCredentials,
    );
  }
}

class SessionController extends StateNotifier<SessionState> {
  SessionController() : super(const SessionState());

  void setCapabilities(BridgeCapabilities capabilities) {
    state = state.copyWith(capabilities: capabilities);
  }

  void setLocalCredentials(List<SessionIdentity> credentials) {
    state = state.copyWith(localCredentials: credentials);
  }

  void setSession(SessionIdentity? session) {
    state = state.copyWith(session: session, clearSession: session == null);
  }

  void clear() {
    state = state.copyWith(
      localCredentials: state.localCredentials,
      clearSession: true,
    );
  }
}

final sessionProvider = StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(),
);
