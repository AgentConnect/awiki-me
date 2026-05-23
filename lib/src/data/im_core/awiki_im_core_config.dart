import 'package:awiki_im_core/awiki_im_core.dart' as core;

class AwikiImCoreEnvironmentConfig {
  const AwikiImCoreEnvironmentConfig({
    required this.serviceBaseUrl,
    required this.didDomain,
    this.userServiceEndpoint,
    this.messageServiceEndpoint,
    this.anpServiceEndpoint,
    this.anpServiceDid,
    this.transportPolicy = core.MessageTransportPolicy.auto,
  });

  factory AwikiImCoreEnvironmentConfig.fromEnvironment() {
    return AwikiImCoreEnvironmentConfig(
      serviceBaseUrl: _optionalFromEnvironment(
        'AWIKI_SERVICE_BASE_URL',
        defaultValue: 'https://awiki.ai',
      )!,
      userServiceEndpoint: _optionalFromEnvironment(
        'AWIKI_USER_SERVICE_URL',
        defaultValue: 'https://awiki.ai',
      ),
      messageServiceEndpoint: _optionalFromEnvironment(
        'AWIKI_MESSAGE_SERVICE_URL',
        defaultValue: 'https://awiki.ai',
      ),
      didDomain: _optionalFromEnvironment(
        'AWIKI_DID_DOMAIN',
        defaultValue: 'awiki.ai',
      )!,
      anpServiceEndpoint: _optionalFromEnvironment('AWIKI_ANP_SERVICE_URL'),
      anpServiceDid: _optionalFromEnvironment('AWIKI_ANP_SERVICE_DID'),
    );
  }

  final String serviceBaseUrl;
  final String didDomain;
  final String? userServiceEndpoint;
  final String? messageServiceEndpoint;
  final String? anpServiceEndpoint;
  final String? anpServiceDid;
  final core.MessageTransportPolicy transportPolicy;

  core.AwikiImCoreConfig toCoreConfig() {
    return core.AwikiImCoreConfig(
      serviceBaseUrl: serviceBaseUrl,
      didDomain: didDomain,
      userServiceEndpoint: userServiceEndpoint,
      messageServiceEndpoint: messageServiceEndpoint,
      anpServiceEndpoint: anpServiceEndpoint,
      anpServiceDid: anpServiceDid,
      transportPolicy: transportPolicy,
    );
  }
}

String? _optionalFromEnvironment(String name, {String? defaultValue}) {
  final value = switch (name) {
    'AWIKI_SERVICE_BASE_URL' => const String.fromEnvironment(
      'AWIKI_SERVICE_BASE_URL',
      defaultValue: 'https://awiki.ai',
    ),
    'AWIKI_USER_SERVICE_URL' => const String.fromEnvironment(
      'AWIKI_USER_SERVICE_URL',
      defaultValue: 'https://awiki.ai',
    ),
    'AWIKI_MESSAGE_SERVICE_URL' => const String.fromEnvironment(
      'AWIKI_MESSAGE_SERVICE_URL',
      defaultValue: 'https://awiki.ai',
    ),
    'AWIKI_DID_DOMAIN' => const String.fromEnvironment(
      'AWIKI_DID_DOMAIN',
      defaultValue: 'awiki.ai',
    ),
    'AWIKI_ANP_SERVICE_URL' => const String.fromEnvironment(
      'AWIKI_ANP_SERVICE_URL',
    ),
    'AWIKI_ANP_SERVICE_DID' => const String.fromEnvironment(
      'AWIKI_ANP_SERVICE_DID',
    ),
    _ => defaultValue ?? '',
  };
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
