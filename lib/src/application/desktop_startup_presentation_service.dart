abstract interface class DesktopStartupPresentationService {
  Future<void> presentReadyContent();
}

final class NoopDesktopStartupPresentationService
    implements DesktopStartupPresentationService {
  const NoopDesktopStartupPresentationService();

  @override
  Future<void> presentReadyContent() async {}
}
