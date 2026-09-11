enum ScreenshotFailureKind {
  permissionRequired('screenshot_screen_recording_permission_required'),
  permissionCheckFailed('screenshot_permission_check_failed'),
  captureFailed('screenshot_capture_failed');

  const ScreenshotFailureKind(this.code);
  final String code;
}

/// Local application metadata only. No account, tenant, capture or TCC data.
class ScreenshotAppDiagnostics {
  const ScreenshotAppDiagnostics({
    required this.applicationName,
    required this.bundleIdentifier,
    required this.applicationPath,
    required this.version,
  });

  final String applicationName;
  final String bundleIdentifier;
  final String applicationPath;
  final String version;
}

class ScreenshotFailure extends StateError {
  ScreenshotFailure(this.kind, {this.diagnostics}) : super(kind.code);

  final ScreenshotFailureKind kind;
  final ScreenshotAppDiagnostics? diagnostics;
}
