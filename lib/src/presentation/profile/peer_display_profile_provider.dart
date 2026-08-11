import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../domain/entities/peer_display_profile.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/services/peer_display_name_resolver.dart';
import '../app_shell/providers/session_provider.dart';

class PeerDisplayProfileState {
  const PeerDisplayProfileState({
    this.ownerDid,
    this.profilesByPersonaId = const <String, PeerDisplayProfile>{},
    this.unresolvedProfilesByDid = const <String, PeerDisplayProfile>{},
    this.personaIdByDid = const <String, String>{},
  });

  final String? ownerDid;
  final Map<String, PeerDisplayProfile> profilesByPersonaId;
  final Map<String, PeerDisplayProfile> unresolvedProfilesByDid;
  final Map<String, String> personaIdByDid;

  PeerDisplayProfile? forPeer({String? peerPersonaId, String? did}) {
    final personaId = peerPersonaId?.trim() ?? '';
    if (personaId.isNotEmpty) {
      return profilesByPersonaId[personaId];
    }
    return forDid(did);
  }

  PeerDisplayProfile? forDid(String? did) {
    final key = did?.trim() ?? '';
    if (key.isEmpty) {
      return null;
    }
    final personaId = personaIdByDid[key];
    if (personaId != null) {
      return profilesByPersonaId[personaId];
    }
    return unresolvedProfilesByDid[key];
  }
}

final class _PeerDisplayOwnerOperation {
  const _PeerDisplayOwnerOperation({
    required this.ownerDid,
    required this.epoch,
    required this.generation,
  });

  final String ownerDid;
  final SessionEpoch? epoch;
  final int generation;
}

class PeerDisplayProfileController
    extends StateNotifier<PeerDisplayProfileState> {
  PeerDisplayProfileController(this.ref)
    : super(const PeerDisplayProfileState());

  final Ref ref;
  final Map<String, Future<void>> _remoteLoads = <String, Future<void>>{};
  final Set<String> _completedRemoteLoads = <String>{};
  int _stateGeneration = 0;

  Future<void> loadCached({
    required String ownerDid,
    required Iterable<String> dids,
    Map<String, String> peerPersonaIdsByDid = const <String, String>{},
    SessionEpoch? expectedEpoch,
  }) async {
    final normalizedOwner = ownerDid.trim();
    if (normalizedOwner.isEmpty) {
      clear();
      return;
    }
    final operation = _beginOwnerOperation(
      normalizedOwner,
      expectedEpoch: expectedEpoch,
    );
    if (operation == null) {
      return;
    }
    await _loadCached(
      operation: operation,
      dids: dids,
      peerPersonaIdsByDid: peerPersonaIdsByDid,
    );
  }

  Future<void> _loadCached({
    required _PeerDisplayOwnerOperation operation,
    required Iterable<String> dids,
    required Map<String, String> peerPersonaIdsByDid,
  }) async {
    _registerPersonaRoutes(peerPersonaIdsByDid);
    final missing = dids
        .map((did) => did.trim())
        .where((did) => did.isNotEmpty && state.forDid(did) == null)
        .toSet();
    if (missing.isEmpty) {
      return;
    }
    final List<PeerDisplayProfile> profiles;
    try {
      profiles = await ref
          .read(directoryApplicationServiceProvider)
          .loadCachedDisplayProfiles(missing);
    } catch (_) {
      // The local projection is an optimization. A missing/legacy cache must
      // not prevent conversations or relationship lists from rendering.
      return;
    }
    if (!_isOwnerOperationCurrent(operation)) {
      return;
    }
    _merge(
      profiles.where((profile) => state.forDid(profile.did) == null),
      peerPersonaIdsByDid: peerPersonaIdsByDid,
    );
  }

  void updateFromRemote({
    required String ownerDid,
    required UserProfile profile,
    String? peerPersonaId,
    SessionEpoch? expectedEpoch,
  }) {
    final normalizedOwner = ownerDid.trim();
    final did = profile.did.trim();
    if (normalizedOwner.isEmpty || did.isEmpty) {
      return;
    }
    final operation = _beginOwnerOperation(
      normalizedOwner,
      expectedEpoch: expectedEpoch,
    );
    if (operation == null) {
      return;
    }
    _mergeRemoteProfile(profile, peerPersonaId: peerPersonaId);
  }

  void _mergeRemoteProfile(UserProfile profile, {String? peerPersonaId}) {
    final did = profile.did.trim();
    final rawDisplayName = profile.displayName.trim();
    final compactDid = PeerDisplayNameResolver.compactDid(did);
    final nickname =
        rawDisplayName.isNotEmpty &&
            rawDisplayName != did &&
            rawDisplayName != compactDid
        ? rawDisplayName
        : null;
    final projection = PeerDisplayProfile(
      did: did,
      peerPersonaId: peerPersonaId,
      displayName: nickname,
      handle: profile.fullHandle ?? profile.handle,
      avatarUri: profile.avatarUri,
    );
    _merge(<PeerDisplayProfile>[projection]);
  }

  Future<void> refreshRemoteProfilesIfNeeded({
    required String ownerDid,
    required Iterable<String> dids,
    Duration timeout = const Duration(seconds: 12),
    SessionEpoch? expectedEpoch,
  }) async {
    final normalizedOwner = ownerDid.trim();
    final requested = dids
        .map((did) => did.trim())
        .where((did) => did.isNotEmpty)
        .toSet();
    if (normalizedOwner.isEmpty || requested.isEmpty) {
      return;
    }
    final operation = _beginOwnerOperation(
      normalizedOwner,
      expectedEpoch: expectedEpoch,
    );
    if (operation == null) {
      return;
    }
    await _loadCached(
      operation: operation,
      dids: requested,
      peerPersonaIdsByDid: const <String, String>{},
    );
    if (!_isOwnerOperationCurrent(operation)) {
      return;
    }
    final missing = requested
        .where((did) {
          final key = _remoteLoadKey(operation, did);
          return !_completedRemoteLoads.contains(key) &&
              _needsRemoteProfileRefresh(state.forDid(did), did);
        })
        .toList(growable: false);
    await Future.wait<void>(
      missing.map((did) {
        final key = _remoteLoadKey(operation, did);
        return _remoteLoad(
          operation: operation,
          did: did,
          timeout: timeout,
          loadKey: key,
        );
      }),
    );
  }

  Future<void> _loadRemoteProfile({
    required _PeerDisplayOwnerOperation operation,
    required String did,
    required Duration timeout,
    required String loadKey,
  }) async {
    try {
      final profile = await ref
          .read(profileApplicationServiceProvider)
          .loadPublicProfile(did)
          .timeout(timeout);
      if (!_isOwnerOperationCurrent(operation)) {
        return;
      }
      _mergeRemoteProfile(profile);
      _completedRemoteLoads.add(loadKey);
    } catch (error) {
      debugPrint(
        '[awiki_me][profile_projection] remote_profile_refresh_failed '
        'did=$did error=${error.runtimeType}',
      );
    }
  }

  Future<void> _remoteLoad({
    required _PeerDisplayOwnerOperation operation,
    required String did,
    required Duration timeout,
    required String loadKey,
  }) {
    final existing = _remoteLoads[loadKey];
    if (existing != null) {
      return existing;
    }
    late final Future<void> load;
    load =
        _loadRemoteProfile(
          operation: operation,
          did: did,
          timeout: timeout,
          loadKey: loadKey,
        ).whenComplete(() {
          if (identical(_remoteLoads[loadKey], load)) {
            _remoteLoads.remove(loadKey);
          }
        });
    _remoteLoads[loadKey] = load;
    return load;
  }

  void clear() {
    _stateGeneration += 1;
    _remoteLoads.clear();
    _completedRemoteLoads.clear();
    state = const PeerDisplayProfileState();
  }

  void _selectOwner(String ownerDid) {
    if (state.ownerDid == ownerDid) {
      return;
    }
    _stateGeneration += 1;
    _remoteLoads.clear();
    _completedRemoteLoads.clear();
    state = PeerDisplayProfileState(ownerDid: ownerDid);
  }

  _PeerDisplayOwnerOperation? _beginOwnerOperation(
    String ownerDid, {
    SessionEpoch? expectedEpoch,
  }) {
    final currentEpoch = ref.read(sessionProvider).activeEpoch;
    if (expectedEpoch != null && currentEpoch != expectedEpoch) {
      return null;
    }
    if (currentEpoch != null && currentEpoch.ownerDid != ownerDid) {
      return null;
    }
    _selectOwner(ownerDid);
    return _PeerDisplayOwnerOperation(
      ownerDid: ownerDid,
      epoch: currentEpoch,
      generation: _stateGeneration,
    );
  }

  bool _isOwnerOperationCurrent(_PeerDisplayOwnerOperation operation) {
    return mounted &&
        operation.generation == _stateGeneration &&
        operation.ownerDid == state.ownerDid &&
        operation.epoch == ref.read(sessionProvider).activeEpoch;
  }

  String _remoteLoadKey(_PeerDisplayOwnerOperation operation, String did) {
    final epoch = operation.epoch;
    return '${operation.generation}\u0000'
        '${epoch?.ownerDid ?? ''}\u0000'
        '${epoch?.identityKey ?? ''}\u0000'
        '${epoch?.generation ?? -1}\u0000'
        '${operation.ownerDid}\u0000$did';
  }

  void _registerPersonaRoutes(Map<String, String> peerPersonaIdsByDid) {
    if (peerPersonaIdsByDid.isEmpty) {
      return;
    }
    final byPersona = <String, PeerDisplayProfile>{
      ...state.profilesByPersonaId,
    };
    final unresolvedByDid = <String, PeerDisplayProfile>{
      ...state.unresolvedProfilesByDid,
    };
    final routes = <String, String>{...state.personaIdByDid};
    for (final entry in peerPersonaIdsByDid.entries) {
      final did = entry.key.trim();
      final personaId = entry.value.trim();
      if (did.isNotEmpty && personaId.isNotEmpty) {
        final existingPersonaId = routes[did];
        if (existingPersonaId != null && existingPersonaId != personaId) {
          continue;
        }
        routes[did] = personaId;
        final unresolved = unresolvedByDid.remove(did);
        if (unresolved != null && !byPersona.containsKey(personaId)) {
          byPersona[personaId] = PeerDisplayProfile(
            did: did,
            peerPersonaId: personaId,
            displayName: unresolved.displayName,
            handle: unresolved.handle,
            avatarUri: unresolved.avatarUri,
            isStale: unresolved.isStale,
            legacyFallback: unresolved.legacyFallback,
          );
        }
      }
    }
    state = PeerDisplayProfileState(
      ownerDid: state.ownerDid,
      profilesByPersonaId: byPersona,
      unresolvedProfilesByDid: unresolvedByDid,
      personaIdByDid: routes,
    );
  }

  void _merge(
    Iterable<PeerDisplayProfile> profiles, {
    Map<String, String> peerPersonaIdsByDid = const <String, String>{},
  }) {
    final byPersona = <String, PeerDisplayProfile>{
      ...state.profilesByPersonaId,
    };
    final unresolvedByDid = <String, PeerDisplayProfile>{
      ...state.unresolvedProfilesByDid,
    };
    final routes = <String, String>{...state.personaIdByDid};
    for (final profile in profiles) {
      final did = profile.did.trim();
      if (did.isEmpty) {
        continue;
      }
      final personaId =
          profile.peerPersonaId?.trim() ??
          peerPersonaIdsByDid[did]?.trim() ??
          routes[did];
      if (personaId != null && personaId.isNotEmpty) {
        routes[did] = personaId;
        byPersona[personaId] = PeerDisplayProfile(
          did: did,
          peerPersonaId: personaId,
          displayName: profile.displayName,
          handle: profile.handle,
          avatarUri: profile.avatarUri,
          isStale: profile.isStale,
          legacyFallback: profile.legacyFallback,
        );
        unresolvedByDid.remove(did);
      } else {
        unresolvedByDid[did] = profile;
      }
    }
    state = PeerDisplayProfileState(
      ownerDid: state.ownerDid,
      profilesByPersonaId: byPersona,
      unresolvedProfilesByDid: unresolvedByDid,
      personaIdByDid: routes,
    );
  }
}

bool _needsRemoteProfileRefresh(PeerDisplayProfile? profile, String did) {
  if (profile == null) {
    return true;
  }
  if (profile.isStale || profile.legacyFallback) {
    return true;
  }
  final displayName = profile.displayName?.trim() ?? '';
  final handle = profile.handle?.trim() ?? '';
  final compactDid = PeerDisplayNameResolver.compactDid(did);
  final hasNickname =
      displayName.isNotEmpty && displayName != did && displayName != compactDid;
  return !hasNickname || handle.isEmpty;
}

final peerDisplayProfileProvider =
    StateNotifierProvider<
      PeerDisplayProfileController,
      PeerDisplayProfileState
    >((ref) => PeerDisplayProfileController(ref));

String? peerAvatarUri(
  PeerDisplayProfileState state,
  String? did, {
  String? peerPersonaId,
}) {
  final value =
      state
          .forPeer(peerPersonaId: peerPersonaId, did: did)
          ?.avatarUri
          ?.trim() ??
      '';
  return value.isEmpty ? null : value;
}

class PeerDisplayNameRequest {
  const PeerDisplayNameRequest({
    this.peerPersonaId,
    this.did,
    this.nickname,
    this.fullHandle,
    this.senderNameSnapshot,
    this.unknownLabel = '',
  });

  final String? peerPersonaId;
  final String? did;
  final String? nickname;
  final String? fullHandle;
  final String? senderNameSnapshot;
  final String unknownLabel;

  @override
  bool operator ==(Object other) =>
      other is PeerDisplayNameRequest &&
      other.peerPersonaId == peerPersonaId &&
      other.did == did &&
      other.nickname == nickname &&
      other.fullHandle == fullHandle &&
      other.senderNameSnapshot == senderNameSnapshot &&
      other.unknownLabel == unknownLabel;

  @override
  int get hashCode => Object.hash(
    peerPersonaId,
    did,
    nickname,
    fullHandle,
    senderNameSnapshot,
    unknownLabel,
  );
}

final peerDisplayNameProvider = Provider.family<String, PeerDisplayNameRequest>(
  (ref, request) {
    final profile = ref.watch(
      peerDisplayProfileProvider.select((state) {
        return state.forPeer(
          peerPersonaId: request.peerPersonaId,
          did: request.did,
        );
      }),
    );
    return _resolvePeerDisplayName(profile: profile, request: request);
  },
);

String resolvePeerDisplayName(
  PeerDisplayProfileState state,
  PeerDisplayNameRequest request,
) {
  return _resolvePeerDisplayName(
    profile: state.forPeer(
      peerPersonaId: request.peerPersonaId,
      did: request.did,
    ),
    request: request,
  );
}

String _resolvePeerDisplayName({
  required PeerDisplayProfile? profile,
  required PeerDisplayNameRequest request,
}) {
  return const PeerDisplayNameResolver().resolve(
    nickname: profile?.displayName?.trim().isNotEmpty == true
        ? profile!.displayName
        : request.nickname,
    fullHandle: profile?.handle?.trim().isNotEmpty == true
        ? profile!.handle
        : request.fullHandle,
    senderNameSnapshot: request.senderNameSnapshot,
    did: request.did,
    unknownLabel: request.unknownLabel,
    compactQualifiedHandle: true,
  );
}

/// Resolves public identity surfaces that intentionally do not use a local
/// contact note or a historical sender snapshot. Identity lookup results and
/// group system events share this product order: nickname, full Handle, DID.
class PublicIdentityDisplayNameRequest {
  const PublicIdentityDisplayNameRequest({
    required this.did,
    this.nickname,
    this.fullHandle,
    this.unknownLabel = '',
  });

  final String? did;
  final String? nickname;
  final String? fullHandle;
  final String unknownLabel;

  @override
  bool operator ==(Object other) =>
      other is PublicIdentityDisplayNameRequest &&
      other.did == did &&
      other.nickname == nickname &&
      other.fullHandle == fullHandle &&
      other.unknownLabel == unknownLabel;

  @override
  int get hashCode => Object.hash(did, nickname, fullHandle, unknownLabel);
}

final publicIdentityDisplayNameProvider =
    Provider.family<String, PublicIdentityDisplayNameRequest>((ref, request) {
      final profile = ref.watch(
        peerDisplayProfileProvider.select((state) => state.forDid(request.did)),
      );
      return const PeerDisplayNameResolver().resolve(
        nickname: profile?.displayName?.trim().isNotEmpty == true
            ? profile!.displayName
            : request.nickname,
        fullHandle: profile?.handle?.trim().isNotEmpty == true
            ? profile!.handle
            : request.fullHandle,
        did: request.did,
        unknownLabel: request.unknownLabel,
      );
    });
