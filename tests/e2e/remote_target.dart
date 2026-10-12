/// Registration uses the explicitly configured remote target and exact HTTPS origin.
void validateRegistrationFixtureTarget({
  required String didDomain,
  required String userServiceUrl,
}) {
  validateConfiguredRemoteTarget(
    didDomain: didDomain,
    serviceUrls: [userServiceUrl],
  );
  if (Uri.parse(userServiceUrl).origin != userServiceUrl) {
    throw const FormatException(
      'Registration fixture must use an HTTPS origin.',
    );
  }
}

/// Keep native Join/App-pair validation aligned with the reviewed owner targets.
/// App-pair historically also supports anpclaw.com; single-App Join does not.
/// This does not grant access to any server-side operator.
void validateMultiDeviceRemoteTarget({
  required String didDomain,
  required List<String> serviceUrls,
  required bool appPair,
}) {
  final allowed = <String>{
    'awiki.info',
    'test-fix.anpclaw.com',
    if (appPair) 'anpclaw.com',
  };
  if (!allowed.contains(didDomain)) {
    throw const FormatException('Multi-device DID domain is not audited.');
  }
  validateConfiguredRemoteTarget(
    didDomain: didDomain,
    serviceUrls: serviceUrls,
  );
  if (serviceUrls.any((value) => Uri.parse(value).port != 443)) {
    throw const FormatException('Multi-device service port is not audited.');
  }
}

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
