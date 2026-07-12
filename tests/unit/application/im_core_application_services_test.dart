import 'dart:async';

import 'package:awiki_me/src/application/directory_application_service.dart';
import 'package:awiki_me/src/application/group_application_service.dart';
import 'package:awiki_me/src/application/ports/directory_core_port.dart';
import 'package:awiki_me/src/application/ports/group_core_port.dart';
import 'package:awiki_me/src/application/ports/profile_core_port.dart';
import 'package:awiki_me/src/application/ports/realtime_core_port.dart';
import 'package:awiki_me/src/application/ports/relationship_core_port.dart';
import 'package:awiki_me/src/application/profile_application_service.dart';
import 'package:awiki_me/src/application/realtime_application_service.dart';
import 'package:awiki_me/src/application/relationship_application_service.dart';
import 'package:awiki_me/src/data/im_core/pending_im_core_group_mutation_adapter.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/group_identity.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/peer_display_profile.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Handle group identity rejects empty values instead of downgrading', () {
    expect(() => GroupIdentitySelection.handle('   '), throwsArgumentError);
    expect(() => GroupIdentitySelection.handle('alice'), throwsArgumentError);
    const didOnly = GroupIdentitySelection.didOnly();
    expect(didOnly.mode, GroupIdentityMode.didOnly);
    expect(didOnly.handle, isNull);
  });

  test(
    'group Handle is qualified only from a matching did:wba provider domain',
    () {
      expect(
        groupHandleForDid(
          handle: ' Alice ',
          did: 'did:wba:AWIKI.INFO:user:alice:e1_key',
        ),
        'alice.awiki.info',
      );
      expect(
        groupHandleForDid(
          handle: 'Alice.Other.example',
          did: 'did:wba:awiki.info:user:alice:e1_key',
        ),
        'alice.other.example',
      );
      expect(
        groupHandleForDid(handle: 'alice', did: 'did:web:example.com:alice'),
        isNull,
      );
    },
  );

  test(
    'profile and directory services trim inputs and delegate to ports',
    () async {
      final profiles = _FakeProfiles();
      final directory = _FakeDirectory();
      final profileService = ImCoreProfileApplicationService(
        profiles: profiles,
      );
      final directoryService = ImCoreDirectoryApplicationService(
        directory: directory,
      );

      await profileService.loadPublicProfile(' did:alice ');
      await profileService.updateProfile(const ProfilePatch(nickName: 'Alice'));
      await directoryService.lookupHandle(' Alice.AWiki ');
      await directoryService.resolvePeer(' did:bob ');
      await directoryService.loadCachedDisplayProfiles(<String>['did:bob']);

      expect(profiles.loadedPublic, ['did:alice']);
      expect(profiles.patches.single.nickName, 'Alice');
      expect(directory.lookups, ['alice.awiki']);
      expect(directory.resolutions, ['did:bob']);
      expect(directory.cachedProfileRequests, [
        <String>['did:bob'],
      ]);
    },
  );

  test(
    'group service delegates supported methods and member mutations',
    () async {
      final groups = _FakeGroups();
      final service = ImCoreGroupApplicationService(groups: groups);

      final created = await service.createGroup(
        name: 'Group',
        slug: 'group',
        description: 'desc',
        goal: 'goal',
        rules: 'rules',
        identity: GroupIdentitySelection.handle('alice.example.com'),
      );
      await service.joinGroup(
        'did:group',
        identity: GroupIdentitySelection.handle('alice.example.com'),
      );
      final recovery = await service.resumeRebindRecovery(limit: 25);
      await service.listGroups(limit: 10);
      await service.addMember(
        groupDid: 'did:group',
        memberRef: 'alice.awiki.ai',
        role: 'admin',
      );
      await service.removeMember(groupDid: 'did:group', memberRef: 'did:alice');

      expect(created.groupId, 'did:group');
      expect(groups.createdNames, ['Group']);
      expect(groups.identities, [
        'handle/alice.example.com',
        'handle/alice.example.com',
      ]);
      expect(groups.recoveryLimit, 25);
      expect(recovery.pending, 1);
      expect(groups.listLimit, 10);
      expect(groups.addedMembers, ['did:group/alice.awiki.ai/admin']);
      expect(groups.removedMembers, ['did:group/did:alice']);

      const pending = PendingImCoreGroupMutationAdapter();
      expect(
        () => pending.addMember(groupDid: 'did:group', memberRef: 'did:bob'),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );

  test('relationship service trims inputs and delegates to port', () async {
    final relationships = _FakeRelationships();
    final service = ImCoreRelationshipApplicationService(
      relationships: relationships,
    );

    await service.follow(' did:bob ');
    await service.unfollow(' did:carol ');
    await service.status(' did:dave ');
    final followers = await service.listFollowers(limit: 2, cursor: '4');
    final following = await service.listFollowing(limit: 3);

    expect(relationships.followed, ['did:bob']);
    expect(relationships.unfollowed, ['did:carol']);
    expect(relationships.statusPeers, ['did:dave']);
    expect(relationships.followerRequests, ['2/4']);
    expect(relationships.followingRequests, ['3/null']);
    expect(followers.items.single.relationship, 'follower');
    expect(following.items.single.relationship, 'following');
  });

  test('realtime service exposes port streams and lifecycle', () async {
    final realtime = _FakeRealtime();
    final service = ImCoreRealtimeApplicationService(realtime: realtime);
    final statuses = <RealtimeConnectionStatus>[];
    final subscription = service.connectionStates.listen(statuses.add);
    addTearDown(subscription.cancel);

    await service.start();
    realtime.emitStatus(RealtimeConnectionStatus.connected);
    await service.stop();
    await pumpEventQueue();

    expect(service.isRunning, isFalse);
    expect(statuses, contains(RealtimeConnectionStatus.connected));
    expect(realtime.startCount, 1);
    expect(realtime.stopCount, 1);
  });
}

class _FakeProfiles implements ProfileCorePort {
  final List<String> loadedPublic = <String>[];
  final List<ProfilePatch> patches = <ProfilePatch>[];

  @override
  Future<UserProfile> loadMyProfile() async => _profile('did:me');

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) async {
    loadedPublic.add(didOrHandle);
    return _profile(didOrHandle);
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) async {
    patches.add(patch);
    return _profile('did:me');
  }
}

class _FakeDirectory implements DirectoryCorePort {
  final List<String> lookups = <String>[];
  final List<String> resolutions = <String>[];
  final List<List<String>> cachedProfileRequests = <List<String>>[];

  @override
  Future<List<PeerDisplayProfile>> loadCachedDisplayProfiles(
    Iterable<String> dids,
  ) async {
    cachedProfileRequests.add(dids.toList());
    return const <PeerDisplayProfile>[];
  }

  @override
  Future<DirectoryPeerResolution> lookupHandle(String handle) async {
    lookups.add(handle);
    return DirectoryPeerResolution(input: handle, did: 'did:$handle');
  }

  @override
  Future<DirectoryPeerResolution> resolvePeer(String peer) async {
    resolutions.add(peer);
    return DirectoryPeerResolution(input: peer, did: peer);
  }
}

class _FakeGroups implements GroupCorePort {
  final List<String> createdNames = <String>[];
  final List<String> addedMembers = <String>[];
  final List<String> removedMembers = <String>[];
  int? listLimit;
  int? recoveryLimit;
  final List<String> identities = <String>[];

  @override
  Future<GroupSummary> createGroup({
    required String name,
    required String slug,
    required String description,
    required String goal,
    required String rules,
    String? messagePrompt,
    GroupIdentitySelection identity = const GroupIdentitySelection.didOnly(),
  }) async {
    createdNames.add(name);
    identities.add('${identity.mode.name}/${identity.handle ?? ''}');
    return _group();
  }

  @override
  Future<GroupSummary> addMember({
    required String groupDid,
    required String memberRef,
    String role = 'member',
  }) async {
    addedMembers.add('$groupDid/$memberRef/$role');
    return _group();
  }

  @override
  Future<GroupSummary> getGroup(String groupDid) async => _group();

  @override
  Future<GroupSummary> joinGroup(
    String groupDid, {
    GroupIdentitySelection identity = const GroupIdentitySelection.didOnly(),
  }) async {
    identities.add('${identity.mode.name}/${identity.handle ?? ''}');
    return _group();
  }

  @override
  Future<GroupRebindRecoverySummary> resumeRebindRecovery({
    int limit = 100,
  }) async {
    recoveryLimit = limit;
    return const GroupRebindRecoverySummary(
      processed: 1,
      completed: 0,
      pending: 1,
      blocked: 0,
    );
  }

  @override
  Future<void> leaveGroup(String groupDid) async {}

  @override
  Future<List<GroupMemberSummary>> listMembers(
    String groupDid, {
    int limit = 100,
  }) async => const <GroupMemberSummary>[];

  @override
  Future<List<ChatMessage>> listMessages(
    String groupDid, {
    int limit = 100,
    String? cursor,
  }) async => const <ChatMessage>[];

  @override
  Future<List<GroupSummary>> listGroups({int limit = 100}) async {
    listLimit = limit;
    return <GroupSummary>[_group()];
  }

  @override
  Future<GroupSummary> removeMember({
    required String groupDid,
    required String memberRef,
  }) async {
    removedMembers.add('$groupDid/$memberRef');
    return _group();
  }
}

class _FakeRelationships implements RelationshipCorePort {
  final List<String> followed = <String>[];
  final List<String> unfollowed = <String>[];
  final List<String> statusPeers = <String>[];
  final List<String> followerRequests = <String>[];
  final List<String> followingRequests = <String>[];

  @override
  Future<void> follow(String peer) async {
    followed.add(peer);
  }

  @override
  Future<CoreRelationshipPage> listFollowers({
    int limit = 100,
    String? cursor,
  }) async {
    followerRequests.add('$limit/$cursor');
    return const CoreRelationshipPage(
      items: <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:follower',
          displayName: 'Follower',
          relationship: 'follower',
        ),
      ],
      hasMore: false,
    );
  }

  @override
  Future<CoreRelationshipPage> listFollowing({
    int limit = 100,
    String? cursor,
  }) async {
    followingRequests.add('$limit/$cursor');
    return const CoreRelationshipPage(
      items: <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:following',
          displayName: 'Following',
          relationship: 'following',
        ),
      ],
      hasMore: false,
    );
  }

  @override
  Future<RelationshipSummary> status(String peer) async {
    statusPeers.add(peer);
    return RelationshipSummary(
      did: peer,
      displayName: peer,
      relationship: 'none',
    );
  }

  @override
  Future<void> unfollow(String peer) async {
    unfollowed.add(peer);
  }
}

class _FakeRealtime implements RealtimeCorePort {
  final StreamController<RealtimeConnectionStatus> _statuses =
      StreamController<RealtimeConnectionStatus>.broadcast();
  final StreamController<RealtimeUpdate> _updates =
      StreamController<RealtimeUpdate>.broadcast();
  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<RealtimeConnectionStatus> get connectionStates => _statuses.stream;

  @override
  bool get isRunning => startCount > stopCount;

  @override
  Stream<RealtimeUpdate> get updates => _updates.stream;

  @override
  Future<void> start() async {
    startCount += 1;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  void emitStatus(RealtimeConnectionStatus status) {
    _statuses.add(status);
  }
}

UserProfile _profile(String did) {
  return UserProfile(
    did: did,
    nickName: did,
    bio: '',
    tags: const <String>[],
    profileMarkdown: '',
  );
}

GroupSummary _group() {
  return const GroupSummary(
    groupId: 'did:group',
    name: 'Group',
    description: '',
    memberCount: 1,
    lastMessageAt: null,
  );
}
