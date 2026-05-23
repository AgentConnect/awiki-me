class AppAuthState {
  const AppAuthState({
    required this.authenticated,
    this.subject,
    this.expiresAt,
    this.needsRefresh = false,
    this.warnings = const <String>[],
  });

  final bool authenticated;
  final String? subject;
  final DateTime? expiresAt;
  final bool needsRefresh;
  final List<String> warnings;
}
