abstract interface class ActiveSessionStore {
  Future<String?> readActiveIdentityId();

  Future<void> writeActiveIdentityId(String identityId);

  Future<void> clearActiveIdentityId();
}
