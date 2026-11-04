// Test-only metadata seam. The normal entrypoint installs no overrides.
import 'package:flutter/foundation.dart';

class E2eBuildMetadata {
  E2eBuildMetadata({required this.enabled});
  final bool enabled;
  bool _legacyHosted = false;
  void useLegacyHostedRelease() {
    if (!enabled) throw StateError('Test build metadata is disabled.');
    _legacyHosted = true;
  }

  String releaseLine(String compiledValue) =>
      enabled && _legacyHosted ? '1015' : compiledValue;
}

final e2eBuildMetadata = E2eBuildMetadata(
  enabled: !kReleaseMode && const bool.fromEnvironment('AWIKI_E2E'),
);
