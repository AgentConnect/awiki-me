import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/directory_application_service.dart';
import 'package:awiki_me/src/application/ports/directory_core_port.dart';
import 'package:awiki_me/src/application/ports/relationship_core_port.dart';
import 'package:awiki_me/src/application/profile_application_service.dart';
import 'package:awiki_me/src/application/relationship_application_service.dart';
import 'package:awiki_me/src/domain/entities/peer_display_profile.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/profile/peer_display_profile_provider.dart';
import 'package:awiki_me/src/presentation/profile/peer_profile_provider.dart';
import 'package:awiki_me/src/presentation/profile/profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _peerDid = 'did:test:peer';
const _ownerDid = 'did:test:owner';

void main() {
  test('同一 DID 重登后详情旧 load 不能写入新 epoch', () async {
    final profiles = _BlockingProfileService();
    final relationships = _RelationshipService();
    final container = _container(
      profiles: profiles,
      relationships: relationships,
    );
    addTearDown(container.dispose);
    final sessions = container.read(sessionProvider.notifier);
    container.read(peerProfileProvider(_peerDid).notifier);

    await profiles.started.future;
    sessions.clear();
    container.read(peerDisplayProfileProvider.notifier).clear();
    sessions.setSession(_session(ownerDid: _ownerDid, credentialName: 'owner'));

    profiles.complete(displayName: 'Peer stale');
    await _pumpUntil(() => profiles.completed);

    final state = container.read(peerProfileProvider(_peerDid));
    expect(state.profile, isNull);
    expect(state.isLoading, isTrue);
    expect(relationships.statusCalls, 0);
    expect(container.read(peerDisplayProfileProvider).forDid(_peerDid), isNull);
  });

  test('A 到 B 后旧 unfollow 不能修改新详情 provider', () async {
    final profiles = _ImmediateProfileService();
    final relationships = _RelationshipService(blockUnfollow: true);
    final container = _container(
      profiles: profiles,
      relationships: relationships,
    );
    addTearDown(container.dispose);
    final sessions = container.read(sessionProvider.notifier);
    final oldController = container.read(
      peerProfileProvider(_peerDid).notifier,
    );
    await _pumpUntil(
      () => !container.read(peerProfileProvider(_peerDid)).isLoading,
    );
    expect(
      container.read(peerProfileProvider(_peerDid)).relationship,
      'following',
    );

    final staleAction = oldController.unfollow();
    await relationships.unfollowStarted.future;

    sessions.clear();
    container.read(peerDisplayProfileProvider.notifier).clear();
    container.invalidate(peerProfileProvider);
    sessions.setSession(
      _session(ownerDid: 'did:test:owner-b', credentialName: 'owner-b'),
    );
    final currentController = container.read(
      peerProfileProvider(_peerDid).notifier,
    );
    expect(identical(currentController, oldController), isFalse);
    await _pumpUntil(
      () => !container.read(peerProfileProvider(_peerDid)).isLoading,
    );

    relationships.completeUnfollow();
    await staleAction;

    final currentState = container.read(peerProfileProvider(_peerDid));
    expect(currentState.profile?.displayName, 'Peer current');
    expect(currentState.relationship, 'following');
    expect(currentState.isActionBusy, isFalse);
    expect(
      container.read(peerDisplayProfileProvider).ownerDid,
      'did:test:owner-b',
    );
  });
}

ProviderContainer _container({
  required ProfileApplicationService profiles,
  required RelationshipApplicationService relationships,
}) {
  return ProviderContainer(
    overrides: <Override>[
      profileApplicationServiceProvider.overrideWithValue(profiles),
      relationshipApplicationServiceProvider.overrideWithValue(relationships),
      directoryApplicationServiceProvider.overrideWithValue(
        _EmptyDirectoryService(),
      ),
      homepageMarkdownLoaderProvider.overrideWithValue((_) async => null),
      sessionProvider.overrideWith((ref) {
        return SessionController()
          ..setSession(_session(ownerDid: _ownerDid, credentialName: 'owner'));
      }),
    ],
  );
}

SessionIdentity _session({
  required String ownerDid,
  required String credentialName,
}) {
  return SessionIdentity(
    did: ownerDid,
    credentialName: credentialName,
    displayName: credentialName,
  );
}

Future<void> _pumpUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for provider state.');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

class _BlockingProfileService implements ProfileApplicationService {
  final Completer<void> started = Completer<void>();
  final Completer<UserProfile> _result = Completer<UserProfile>();
  bool completed = false;

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) {
    started.complete();
    return _result.future.whenComplete(() => completed = true);
  }

  void complete({required String displayName}) {
    _result.complete(_profile(displayName));
  }

  @override
  Future<UserProfile> loadMyProfile() {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) {
    throw UnimplementedError();
  }
}

class _ImmediateProfileService implements ProfileApplicationService {
  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) async {
    return _profile('Peer current');
  }

  @override
  Future<UserProfile> loadMyProfile() {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) {
    throw UnimplementedError();
  }
}

class _RelationshipService implements RelationshipApplicationService {
  _RelationshipService({this.blockUnfollow = false});

  final bool blockUnfollow;
  final Completer<void> unfollowStarted = Completer<void>();
  final Completer<void> _unfollowResult = Completer<void>();
  int statusCalls = 0;

  @override
  Future<RelationshipSummary> status(String peer) async {
    statusCalls += 1;
    return const RelationshipSummary(
      did: _peerDid,
      displayName: 'Peer',
      relationship: 'following',
    );
  }

  @override
  Future<void> unfollow(String peer) {
    if (!unfollowStarted.isCompleted) {
      unfollowStarted.complete();
    }
    return blockUnfollow ? _unfollowResult.future : Future<void>.value();
  }

  void completeUnfollow() {
    if (!_unfollowResult.isCompleted) {
      _unfollowResult.complete();
    }
  }

  @override
  Future<void> follow(String peer) async {}

  @override
  Future<CoreRelationshipPage> listFollowers({
    int limit = 100,
    String? cursor,
  }) async {
    return const CoreRelationshipPage(
      items: <RelationshipSummary>[],
      hasMore: false,
    );
  }

  @override
  Future<CoreRelationshipPage> listFollowing({
    int limit = 100,
    String? cursor,
  }) async {
    return const CoreRelationshipPage(
      items: <RelationshipSummary>[],
      hasMore: false,
    );
  }
}

class _EmptyDirectoryService implements DirectoryApplicationService {
  @override
  Future<List<PeerDisplayProfile>> loadCachedDisplayProfiles(
    Iterable<String> dids,
  ) async {
    return const <PeerDisplayProfile>[];
  }

  @override
  Future<DirectoryPeerResolution> lookupHandle(String handle) {
    throw UnimplementedError();
  }

  @override
  Future<DirectoryPeerResolution> resolvePeer(String peer) {
    throw UnimplementedError();
  }
}

UserProfile _profile(String displayName) {
  return UserProfile(
    did: _peerDid,
    displayName: displayName,
    bio: '',
    tags: const <String>[],
    profileMarkdown: '',
  );
}
