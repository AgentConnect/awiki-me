import '../../domain/entities/chat_mention.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/session_identity.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/services/peer_display_name_resolver.dart';
import '../profile/peer_display_profile_provider.dart';

/// Resolves mention text from stable identity facts without changing the
/// message payload or using display values for routing.
class ChatMentionPresentationResolver {
  ChatMentionPresentationResolver({
    required this.session,
    required this.currentProfile,
    required this.peerProfiles,
    Iterable<GroupMemberSummary> groupMembers = const <GroupMemberSummary>[],
  }) : _groupMembersByDid = <String, GroupMemberSummary>{
         for (final member in groupMembers)
           if (member.did.trim().isNotEmpty) member.did.trim(): member,
       };

  final SessionIdentity? session;
  final UserProfile? currentProfile;
  final PeerDisplayProfileState peerProfiles;
  final Map<String, GroupMemberSummary> _groupMembersByDid;

  String? surfaceForTarget(ChatMentionTargetDraft target) {
    if (target.kind == ChatMentionTargetKind.groupSelector) {
      return null;
    }
    final name = displayNameForTarget(target);
    if (name == null) {
      return null;
    }
    return '@${_withoutLeadingAt(name)}';
  }

  String? displayNameForTarget(ChatMentionTargetDraft target) {
    final did = target.did?.trim() ?? '';
    if (did.isEmpty) {
      return null;
    }
    if (_isCurrentIdentity(did)) {
      return _resolveCurrentIdentity(target, did);
    }
    final member = _groupMembersByDid[did];
    return _resolvePeer(
      did: did,
      peerPersonaId: member?.peerPersonaId,
      nickname: _firstNonEmpty(<String?>[
        member?.displayName,
        target.displayName,
      ]),
      fullHandle: _firstNonEmpty(<String?>[member?.handle, target.handle]),
    );
  }

  GroupMemberSummary projectGroupMember(GroupMemberSummary member) {
    final did = member.did.trim();
    final profile = peerProfiles.forPeer(
      peerPersonaId: member.peerPersonaId,
      did: did,
    );
    final displayName = _isCurrentIdentity(did)
        ? _resolveCurrentIdentity(
            ChatMentionTargetDraft.unknownMember(
              did: did,
              handle: member.handle,
              displayName: member.displayName,
            ),
            did,
          )
        : _resolvePeer(
            did: did,
            peerPersonaId: member.peerPersonaId,
            nickname: member.displayName,
            fullHandle: member.handle,
          );
    return GroupMemberSummary(
      userId: member.userId,
      did: member.did,
      handle: _firstNonEmpty(<String?>[profile?.handle, member.handle]) ?? '',
      role: member.role,
      membershipId: member.membershipId,
      peerPersonaId: member.peerPersonaId,
      credentialDid: member.credentialDid,
      profileUrl: member.profileUrl,
      displayName: displayName,
      avatarUri: _firstNonEmpty(<String?>[
        profile?.avatarUri,
        member.avatarUri,
      ]),
      subjectType: member.subjectType,
      membershipStatus: member.membershipStatus,
    );
  }

  bool _isCurrentIdentity(String did) {
    final currentDid = session?.did.trim() ?? '';
    final profileDid = currentProfile?.did.trim() ?? '';
    return (currentDid.isNotEmpty && currentDid == did) ||
        (profileDid.isNotEmpty && profileDid == did);
  }

  String _resolveCurrentIdentity(ChatMentionTargetDraft target, String did) {
    return const PeerDisplayNameResolver().resolve(
      nickname: _firstNonEmpty(<String?>[
        currentProfile?.displayName,
        session?.displayName,
        target.displayName,
      ]),
      fullHandle: _firstNonEmpty(<String?>[
        currentProfile?.fullHandle,
        currentProfile?.handle,
        session?.handle,
        target.handle,
      ]),
      did: did,
      compactQualifiedHandle: true,
    );
  }

  String _resolvePeer({
    required String did,
    required String? peerPersonaId,
    required String? nickname,
    required String? fullHandle,
  }) {
    return resolvePeerDisplayName(
      peerProfiles,
      PeerDisplayNameRequest(
        peerPersonaId: peerPersonaId,
        did: did,
        nickname: nickname,
        fullHandle: fullHandle,
      ),
    );
  }
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final normalized = value?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }
  }
  return null;
}

String _withoutLeadingAt(String value) {
  var normalized = value.trim();
  while (normalized.startsWith('@')) {
    normalized = normalized.substring(1).trimLeft();
  }
  return normalized;
}
