abstract interface class DesktopWindowPlacementService {
  Future<void> resetPlacement();
}

final class NoopDesktopWindowPlacementService
    implements DesktopWindowPlacementService {
  const NoopDesktopWindowPlacementService();

  @override
  Future<void> resetPlacement() async {}
}
