class GroupDisplayName {
  const GroupDisplayName._();

  static String fallback(String? groupId) {
    final value = groupId?.trim() ?? '';
    return value.isEmpty ? 'Group' : 'Group $value';
  }

  static String? firstFriendly(Iterable<Object?> values, {String? groupId}) {
    final normalizedGroupId = groupId?.trim() ?? '';
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty) {
        continue;
      }
      if (isIdLike(text, normalizedGroupId)) {
        continue;
      }
      return text;
    }
    return null;
  }

  static bool isIdLike(String? name, String? groupId) {
    final normalizedName = name?.trim() ?? '';
    final normalizedGroupId = groupId?.trim() ?? '';
    if (normalizedName.isEmpty) {
      return true;
    }
    if (normalizedName.startsWith('did:')) {
      return true;
    }
    if (normalizedGroupId.isEmpty) {
      return false;
    }
    return normalizedName == normalizedGroupId ||
        normalizedName == 'Group $normalizedGroupId';
  }
}
