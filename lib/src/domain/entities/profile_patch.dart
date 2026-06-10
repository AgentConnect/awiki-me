class ProfilePatch {
  const ProfilePatch({
    this.displayName,
    String? nickName,
    this.bio,
    this.tags,
    this.profileMarkdown,
    this.avatarUri,
  }) : _legacyNickName = nickName;

  final String? displayName;
  final String? _legacyNickName;
  final String? bio;
  final List<String>? tags;
  final String? profileMarkdown;
  final String? avatarUri;

  String? get nickName => displayName ?? _legacyNickName;

  String? get effectiveDisplayName => nickName;
}
