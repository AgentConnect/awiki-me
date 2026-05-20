class BridgeCapabilities {
  const BridgeCapabilities({
    required this.profileMarkdown,
    required this.localDeleteOnly,
    required this.systemPushStub,
    required this.e2ee,
  });

  final bool profileMarkdown;
  final bool localDeleteOnly;
  final bool systemPushStub;
  final E2eeCapability e2ee;
}

class E2eeCapability {
  const E2eeCapability({
    required this.supported,
    required this.pluginRequired,
    required this.enabledByDefault,
  });

  final bool supported;
  final bool pluginRequired;
  final bool enabledByDefault;
}
