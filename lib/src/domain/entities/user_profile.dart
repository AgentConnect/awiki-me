class UserProfile {
  const UserProfile({
    required this.did,
    required this.nickName,
    required this.bio,
    required this.tags,
    required this.profileMarkdown,
    this.handle,
    this.fullHandle,
    this.region,
  });

  final String did;
  final String nickName;
  final String bio;
  final List<String> tags;
  final String profileMarkdown;
  final String? handle;
  final String? fullHandle;
  final String? region;

  UserProfile copyWith({
    String? nickName,
    String? bio,
    List<String>? tags,
    String? profileMarkdown,
    String? fullHandle,
    String? region,
  }) {
    return UserProfile(
      did: did,
      nickName: nickName ?? this.nickName,
      bio: bio ?? this.bio,
      tags: tags ?? this.tags,
      profileMarkdown: profileMarkdown ?? this.profileMarkdown,
      handle: handle,
      fullHandle: fullHandle ?? this.fullHandle,
      region: region ?? this.region,
    );
  }
}
