final class AppPresentationState {
  const AppPresentationState({
    required this.applicationActive,
    required this.windowVisible,
    required this.windowMiniaturized,
  });

  final bool applicationActive;
  final bool windowVisible;
  final bool windowMiniaturized;

  bool get isForeground =>
      applicationActive && windowVisible && !windowMiniaturized;
}

abstract interface class AppPresentationService {
  Future<AppPresentationState?> currentState();
}
