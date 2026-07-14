import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../domain/entities/peer_display_profile.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/services/peer_display_name_resolver.dart';

class PeerDisplayProfileState {
  const PeerDisplayProfileState({
    this.ownerDid,
    this.profilesByPersonaId = const <String, PeerDisplayProfile>{},
    this.unresolvedProfilesByDid = const <String, PeerDisplayProfile>{},
    this.personaIdByDid = const <String, String>{},
    this.localNotesByPersonaId = const <String, String>{},
  });

  final String? ownerDid;
  final Map<String, PeerDisplayProfile> profilesByPersonaId;
  final Map<String, PeerDisplayProfile> unresolvedProfilesByDid;
  final Map<String, String> personaIdByDid;
  final Map<String, String> localNotesByPersonaId;

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

  String? localNoteForPeer({String? peerPersonaId, String? did}) {
    final requestedPersonaId = peerPersonaId?.trim() ?? '';
    final didKey = did?.trim() ?? '';
    final personaId = requestedPersonaId.isNotEmpty
        ? requestedPersonaId
        : personaIdByDid[didKey] ?? '';
    return personaId.isEmpty ? null : localNotesByPersonaId[personaId];
  }
}

class PeerDisplayProfileController
    extends StateNotifier<PeerDisplayProfileState> {
  PeerDisplayProfileController(this.ref)
    : super(const PeerDisplayProfileState());

  final Ref ref;
  final Map<String, Future<void>> _remoteLoads = <String, Future<void>>{};

  Future<void> loadCached({
    required String ownerDid,
    required Iterable<String> dids,
    Map<String, String> peerPersonaIdsByDid = const <String, String>{},
  }) async {
    final normalizedOwner = ownerDid.trim();
    if (normalizedOwner.isEmpty) {
      clear();
      return;
    }
    _selectOwner(normalizedOwner);
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
    if (state.ownerDid != normalizedOwner) {
      return;
    }
    _merge(profiles, peerPersonaIdsByDid: peerPersonaIdsByDid);
  }

  void updateFromRemote({
    required String ownerDid,
    required UserProfile profile,
    String? peerPersonaId,
  }) {
    final normalizedOwner = ownerDid.trim();
    final did = profile.did.trim();
    if (normalizedOwner.isEmpty || did.isEmpty) {
      return;
    }
    _selectOwner(normalizedOwner);
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

  Future<void> refreshRemoteMissing({
    required String ownerDid,
    required Iterable<String> dids,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final normalizedOwner = ownerDid.trim();
    final requested = dids
        .map((did) => did.trim())
        .where((did) => did.isNotEmpty)
        .toSet();
    if (normalizedOwner.isEmpty || requested.isEmpty) {
      return;
    }
    await loadCached(ownerDid: normalizedOwner, dids: requested);
    if (state.ownerDid != normalizedOwner) {
      return;
    }
    final missing = requested
        .where((did) => state.forDid(did) == null)
        .toList(growable: false);
    await Future.wait<void>(
      missing.map((did) {
        final key = '$normalizedOwner\u0000$did';
        return _remoteLoads.putIfAbsent(
          key,
          () => _loadRemoteProfile(
            ownerDid: normalizedOwner,
            did: did,
            timeout: timeout,
            loadKey: key,
          ),
        );
      }),
    );
  }

  Future<void> _loadRemoteProfile({
    required String ownerDid,
    required String did,
    required Duration timeout,
    required String loadKey,
  }) async {
    try {
      final profile = await ref
          .read(profileApplicationServiceProvider)
          .loadPublicProfile(did)
          .timeout(timeout);
      if (state.ownerDid != ownerDid) {
        return;
      }
      updateFromRemote(ownerDid: ownerDid, profile: profile);
    } catch (error) {
      debugPrint(
        '[awiki_me][profile_projection] remote_profile_refresh_failed '
        'did=$did error=${error.runtimeType}',
      );
    } finally {
      _remoteLoads.remove(loadKey);
    }
  }

  void clear() {
    state = const PeerDisplayProfileState();
  }

  void registerLocalNotes({
    required String ownerDid,
    required Map<String, String> localNotesByPersonaId,
  }) {
    if (state.ownerDid != ownerDid.trim()) {
      return;
    }
    if (localNotesByPersonaId.isEmpty) {
      return;
    }
    final next = <String, String>{...state.localNotesByPersonaId};
    for (final entry in localNotesByPersonaId.entries) {
      final personaId = entry.key.trim();
      final note = entry.value.trim();
      if (personaId.isEmpty) {
        continue;
      }
      if (note.isEmpty) {
        next.remove(personaId);
      } else {
        next[personaId] = note;
      }
    }
    state = PeerDisplayProfileState(
      ownerDid: state.ownerDid,
      profilesByPersonaId: state.profilesByPersonaId,
      unresolvedProfilesByDid: state.unresolvedProfilesByDid,
      personaIdByDid: state.personaIdByDid,
      localNotesByPersonaId: next,
    );
  }

  void _selectOwner(String ownerDid) {
    if (state.ownerDid == ownerDid) {
      return;
    }
    state = PeerDisplayProfileState(ownerDid: ownerDid);
  }

  void _registerPersonaRoutes(Map<String, String> peerPersonaIdsByDid) {
    if (peerPersonaIdsByDid.isEmpty) {
      return;
    }
    final routes = <String, String>{...state.personaIdByDid};
    for (final entry in peerPersonaIdsByDid.entries) {
      final did = entry.key.trim();
      final personaId = entry.value.trim();
      if (did.isNotEmpty && personaId.isNotEmpty) {
        routes[did] = personaId;
      }
    }
    state = PeerDisplayProfileState(
      ownerDid: state.ownerDid,
      profilesByPersonaId: state.profilesByPersonaId,
      unresolvedProfilesByDid: state.unresolvedProfilesByDid,
      personaIdByDid: routes,
      localNotesByPersonaId: state.localNotesByPersonaId,
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
      localNotesByPersonaId: state.localNotesByPersonaId,
    );
  }
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
    final projection = ref.watch(
      peerDisplayProfileProvider.select((state) {
        return (
          profile: state.forPeer(
            peerPersonaId: request.peerPersonaId,
            did: request.did,
          ),
          localNote: state.localNoteForPeer(
            peerPersonaId: request.peerPersonaId,
            did: request.did,
          ),
        );
      }),
    );
    return const PeerDisplayNameResolver().resolve(
      localNote: projection.localNote,
      nickname: projection.profile?.displayName?.trim().isNotEmpty == true
          ? projection.profile!.displayName
          : request.nickname,
      fullHandle: projection.profile?.handle?.trim().isNotEmpty == true
          ? projection.profile!.handle
          : request.fullHandle,
      senderNameSnapshot: request.senderNameSnapshot,
      did: request.did,
      unknownLabel: request.unknownLabel,
    );
  },
);
