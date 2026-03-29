class UserProfile {
  const UserProfile({
    required this.did,
    required this.nickName,
    required this.bio,
    required this.tags,
    required this.profileMarkdown,
    this.handle,
    this.region,
  });

  final String did;
  final String nickName;
  final String bio;
  final List<String> tags;
  final String profileMarkdown;
  final String? handle;
  final String? region;

  UserProfile copyWith({
    String? nickName,
    String? bio,
    List<String>? tags,
    String? profileMarkdown,
    String? region,
  }) {
    return UserProfile(
      did: did,
      nickName: nickName ?? this.nickName,
      bio: bio ?? this.bio,
      tags: tags ?? this.tags,
      profileMarkdown: profileMarkdown ?? this.profileMarkdown,
      handle: handle,
      region: region ?? this.region,
    );
  }
}

