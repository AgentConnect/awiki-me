import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/bridge_capabilities.dart';
import '../../../domain/entities/session_identity.dart';

class SessionState {
  const SessionState({
    this.capabilities,
    this.session,
    this.localCredentials = const <SessionIdentity>[],
    this.generation = 0,
  });

  final BridgeCapabilities? capabilities;
  final SessionIdentity? session;
  final List<SessionIdentity> localCredentials;
  final int generation;

  bool get isLoggedIn => session != null;

  SessionEpoch? get activeEpoch {
    final current = session;
    if (current == null) {
      return null;
    }
    return SessionEpoch(
      ownerDid: current.did,
      identityKey: current.credentialName,
      generation: generation,
    );
  }

  SessionAccountBinding? get accountBinding => session?.accountBinding;

  bool get hasActiveSyncAccountBinding => accountBinding != null;

  SessionState copyWith({
    BridgeCapabilities? capabilities,
    SessionIdentity? session,
    List<SessionIdentity>? localCredentials,
    bool clearSession = false,
    int? generation,
  }) {
    return SessionState(
      capabilities: capabilities ?? this.capabilities,
      session: clearSession ? null : (session ?? this.session),
      localCredentials: localCredentials ?? this.localCredentials,
      generation: generation ?? this.generation,
    );
  }
}

class SessionEpoch {
  SessionEpoch({
    required String ownerDid,
    required String identityKey,
    required this.generation,
  }) : ownerDid = ownerDid.trim(),
       identityKey = identityKey.trim();

  final String ownerDid;
  final String identityKey;
  final int generation;

  bool matches(SessionState state) => this == state.activeEpoch;

  @override
  bool operator ==(Object other) {
    return other is SessionEpoch &&
        other.ownerDid == ownerDid &&
        other.identityKey == identityKey &&
        other.generation == generation;
  }

  @override
  int get hashCode => Object.hash(ownerDid, identityKey, generation);
}

StateError sessionEpochChangedError() => StateError('session_epoch_changed');

bool isSessionEpochChangedError(Object error) {
  return error is StateError && error.message == 'session_epoch_changed';
}

class SessionController extends StateNotifier<SessionState> {
  SessionController() : super(const SessionState());

  void setCapabilities(BridgeCapabilities capabilities) {
    state = state.copyWith(capabilities: capabilities);
  }

  void setLocalCredentials(List<SessionIdentity> credentials) {
    state = state.copyWith(localCredentials: credentials);
  }

  void upsertLocalCredential(SessionIdentity credential) {
    final next = <SessionIdentity>[
      for (final item in state.localCredentials)
        if (item.credentialName != credential.credentialName) item,
      credential,
    ]..sort((a, b) => a.credentialName.compareTo(b.credentialName));
    state = state.copyWith(localCredentials: next);
  }

  void setSession(SessionIdentity? session) {
    final activeIdentityChanged = !_sameActiveIdentity(state.session, session);
    state = state.copyWith(
      session: session,
      clearSession: session == null,
      generation: activeIdentityChanged
          ? state.generation + 1
          : state.generation,
    );
  }

  void activateSession(SessionIdentity session) {
    state = state.copyWith(session: session, generation: state.generation + 1);
  }

  bool updateSessionMetadataIfCurrent(SessionIdentity session) {
    if (!_sameActiveIdentity(state.session, session)) {
      return false;
    }
    state = state.copyWith(session: session);
    return true;
  }

  void clear() {
    state = state.copyWith(
      localCredentials: state.localCredentials,
      clearSession: true,
      generation: state.generation + 1,
    );
  }
}

bool _sameActiveIdentity(SessionIdentity? first, SessionIdentity? second) {
  if (identical(first, second)) {
    return true;
  }
  if (first == null || second == null) {
    return false;
  }
  return first.did.trim() == second.did.trim() &&
      first.credentialName.trim() == second.credentialName.trim();
}

final sessionProvider = StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(),
);
