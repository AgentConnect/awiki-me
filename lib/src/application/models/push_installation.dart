final class PushInstallation {
  const PushInstallation({
    required this.installationId,
    required this.provider,
    required this.providerDeviceId,
    required this.platform,
    required this.status,
    required this.clientProduct,
    required this.clientVersion,
    required this.capabilities,
    this.logicalDeviceId,
    this.appId,
  });

  final String installationId;
  final String provider;
  final String providerDeviceId;
  final String platform;
  final String status;
  final String clientProduct;
  final String clientVersion;
  final List<String> capabilities;
  final String? logicalDeviceId;
  final String? appId;
}
