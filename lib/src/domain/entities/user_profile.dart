import 'identity_type.dart';

class UserProfile {
  const UserProfile({
    required this.did,
    String? displayName,
    String? nickName,
    required this.bio,
    required this.tags,
    required this.profileMarkdown,
    this.handle,
    this.avatarUri,
    this.profileUri,
    this.subjectType,
    this.agentKind,
    this.agentCapabilities = const <String>{},
    this.fullHandle,
    this.region,
    this.profileVersion,
  }) : displayName = displayName ?? nickName ?? '';

  final String did;
  final String displayName;
  final String bio;
  final List<String> tags;
  final String profileMarkdown;
  final String? handle;
  final String? avatarUri;
  final String? profileUri;
  final String? subjectType;
  final IdentityAgentKind? agentKind;
  final Set<String> agentCapabilities;
  final String? fullHandle;
  final String? region;
  final String? profileVersion;

  IdentityType get identityType {
    final resolved = IdentityType.fromWire(
      subjectType: subjectType,
      isAgent: agentKind != null,
      agentKind: agentKind?.name,
    );
    // Public human profiles predate subject_type. Agent metadata is explicit,
    // so an unclassified profile remains a user for backwards-compatible UI.
    return resolved.subjectKind == IdentitySubjectKind.unknown
        ? const IdentityType.user()
        : resolved;
  }

  String get nickName => displayName;

  UserProfile copyWith({
    String? displayName,
    String? nickName,
    String? bio,
    List<String>? tags,
    String? profileMarkdown,
    String? handle,
    String? avatarUri,
    String? profileUri,
    String? subjectType,
    IdentityAgentKind? agentKind,
    Set<String>? agentCapabilities,
    String? fullHandle,
    String? region,
    String? profileVersion,
  }) {
    return UserProfile(
      did: did,
      displayName: displayName ?? nickName ?? this.displayName,
      bio: bio ?? this.bio,
      tags: tags ?? this.tags,
      profileMarkdown: profileMarkdown ?? this.profileMarkdown,
      handle: handle ?? this.handle,
      avatarUri: avatarUri ?? this.avatarUri,
      profileUri: profileUri ?? this.profileUri,
      subjectType: subjectType ?? this.subjectType,
      agentKind: agentKind ?? this.agentKind,
      agentCapabilities: agentCapabilities ?? this.agentCapabilities,
      fullHandle: fullHandle ?? this.fullHandle,
      region: region ?? this.region,
      profileVersion: profileVersion ?? this.profileVersion,
    );
  }
}
