class ProfilePatch {
  const ProfilePatch({
    this.nickName,
    this.bio,
    this.tags,
    this.profileMarkdown,
  });

  final String? nickName;
  final String? bio;
  final List<String>? tags;
  final String? profileMarkdown;
}

