final class PushInstallation {
  const PushInstallation({
    required this.installationId,
    required this.provider,
    required this.providerDeviceId,
    required this.platform,
    required this.status,
    this.logicalDeviceId,
    this.appId,
  });

  final String installationId;
  final String provider;
  final String providerDeviceId;
  final String platform;
  final String status;
  final String? logicalDeviceId;
  final String? appId;
}
