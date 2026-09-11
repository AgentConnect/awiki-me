/// Test target comes from the explicit host config, never from a case's domain.
/// This checks transport/scope consistency; it does not grant operator access.
void validateConfiguredRemoteTarget({
  required String didDomain,
  required List<String> serviceUrls,
}) {
  final domainPattern = RegExp(
    r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$',
  );
  if (!domainPattern.hasMatch(didDomain) ||
      RegExp(r'^[0-9.]+$').hasMatch(didDomain) ||
      serviceUrls.isEmpty) {
    throw const FormatException('An explicit remote DID domain is required.');
  }
  String? origin;
  for (final value in serviceUrls) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != didDomain ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (origin != null && uri.origin != origin)) {
      throw const FormatException(
        'Remote service URLs must share the configured DID domain and HTTPS origin.',
      );
    }
    origin = uri.origin;
  }
}
