import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../domain/entities/peer_display_profile.dart';
import '../../domain/entities/user_profile.dart';
import '../shared/formatters/display_formatters.dart';

class PeerDisplayProfileState {
  const PeerDisplayProfileState({
    this.ownerDid,
    this.profiles = const <String, PeerDisplayProfile>{},
  });

  final String? ownerDid;
  final Map<String, PeerDisplayProfile> profiles;

  PeerDisplayProfile? forDid(String? did) {
    final key = did?.trim() ?? '';
    return key.isEmpty ? null : profiles[key];
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
  }) async {
    final normalizedOwner = ownerDid.trim();
    if (normalizedOwner.isEmpty) {
      clear();
      return;
    }
    _selectOwner(normalizedOwner);
    final missing = dids
        .map((did) => did.trim())
        .where((did) => did.isNotEmpty && !state.profiles.containsKey(did))
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
    _merge(profiles);
  }

  void updateFromRemote({
    required String ownerDid,
    required UserProfile profile,
    String? requestedDid,
  }) {
    final normalizedOwner = ownerDid.trim();
    final did = profile.did.trim();
    if (normalizedOwner.isEmpty || did.isEmpty) {
      return;
    }
    _selectOwner(normalizedOwner);
    final rawDisplayName = profile.displayName.trim();
    final compactDid = DidDisplayFormatter.compactDid(did);
    final nickname =
        rawDisplayName.isNotEmpty &&
            rawDisplayName != did &&
            rawDisplayName != compactDid
        ? rawDisplayName
        : null;
    final projection = PeerDisplayProfile(
      did: did,
      displayName: nickname,
      handle: profile.fullHandle ?? profile.handle,
      avatarUri: profile.avatarUri,
    );
    final lookupDid = requestedDid?.trim() ?? '';
    _merge(<PeerDisplayProfile>[
      projection,
      if (lookupDid.isNotEmpty && lookupDid != did)
        PeerDisplayProfile(
          did: lookupDid,
          displayName: projection.displayName,
          handle: projection.handle,
          avatarUri: projection.avatarUri,
        ),
    ]);
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
        .where((did) => !state.profiles.containsKey(did))
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
      updateFromRemote(ownerDid: ownerDid, profile: profile, requestedDid: did);
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

  void _selectOwner(String ownerDid) {
    if (state.ownerDid == ownerDid) {
      return;
    }
    state = PeerDisplayProfileState(ownerDid: ownerDid);
  }

  void _merge(Iterable<PeerDisplayProfile> profiles) {
    final next = <String, PeerDisplayProfile>{...state.profiles};
    for (final profile in profiles) {
      final did = profile.did.trim();
      if (did.isNotEmpty) {
        next[did] = profile;
      }
    }
    state = PeerDisplayProfileState(ownerDid: state.ownerDid, profiles: next);
  }
}

final peerDisplayProfileProvider =
    StateNotifierProvider<
      PeerDisplayProfileController,
      PeerDisplayProfileState
    >((ref) => PeerDisplayProfileController(ref));

String peerDisplayName(
  PeerDisplayProfileState state, {
  required String? did,
  required String fallback,
}) {
  final profile = state.forDid(did);
  final nickname = profile?.displayName?.trim() ?? '';
  if (nickname.isNotEmpty && !nickname.startsWith('did:')) {
    return nickname;
  }
  final handle = _cleanHandle(profile?.handle);
  return handle.isNotEmpty ? handle : fallback;
}

String? peerAvatarUri(PeerDisplayProfileState state, String? did) {
  final value = state.forDid(did)?.avatarUri?.trim() ?? '';
  return value.isEmpty ? null : value;
}

String _cleanHandle(String? source) {
  var value = source?.trim() ?? '';
  while (value.startsWith('@')) {
    value = value.substring(1).trimLeft();
  }
  return value;
}
