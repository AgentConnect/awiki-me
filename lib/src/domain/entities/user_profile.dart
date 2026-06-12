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
    this.fullHandle,
    this.region,
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
  final String? fullHandle;
  final String? region;

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
    String? fullHandle,
    String? region,
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
      fullHandle: fullHandle ?? this.fullHandle,
      region: region ?? this.region,
    );
  }
}
