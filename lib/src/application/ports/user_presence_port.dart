abstract interface class UserPresencePort {
  Future<bool> confirm({required String reason});
}
