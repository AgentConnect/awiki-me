import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/config/awiki_environment_config.dart';

class AwikiImCoreEnvironmentConfig {
  const AwikiImCoreEnvironmentConfig({
    required this.serviceBaseUrl,
    required this.didDomain,
    this.stateNamespace = 'default',
    this.userServiceEndpoint,
    this.messageServiceEndpoint,
    this.mailServiceEndpoint,
    this.anpServiceEndpoint,
    this.anpServiceDid,
    this.transportPolicy = core.MessageTransportPolicy.auto,
  });

  factory AwikiImCoreEnvironmentConfig.fromEnvironment() {
    final environment = AwikiEnvironmentConfig.fromEnvironment();
    final config = AwikiImCoreEnvironmentConfig.fromAwikiEnvironment(
      environment,
    );
    final serviceBaseUrl =
        _optionalFromEnvironment('AWIKI_SERVICE_BASE_URL') ??
        config.serviceBaseUrl;
    return AwikiImCoreEnvironmentConfig(
      serviceBaseUrl: serviceBaseUrl,
      userServiceEndpoint:
          _optionalFromEnvironment('AWIKI_USER_SERVICE_URL') ??
          config.userServiceEndpoint,
      messageServiceEndpoint:
          _optionalFromEnvironment('AWIKI_MESSAGE_SERVICE_URL') ??
          config.messageServiceEndpoint,
      mailServiceEndpoint:
          _optionalFromEnvironment('AWIKI_MAIL_SERVICE_URL') ??
          config.mailServiceEndpoint,
      didDomain:
          _optionalFromEnvironment('AWIKI_DID_DOMAIN') ?? config.didDomain,
      stateNamespace:
          _optionalFromEnvironment('AWIKI_STATE_NAMESPACE') ??
          config.stateNamespace,
      anpServiceEndpoint:
          _optionalFromEnvironment('AWIKI_ANP_SERVICE_URL') ??
          config.anpServiceEndpoint,
      anpServiceDid:
          _optionalFromEnvironment('AWIKI_ANP_SERVICE_DID') ??
          config.anpServiceDid,
    );
  }

  factory AwikiImCoreEnvironmentConfig.fromAwikiEnvironment(
    AwikiEnvironmentConfig environment,
  ) {
    return AwikiImCoreEnvironmentConfig(
      serviceBaseUrl: environment.baseUrl,
      userServiceEndpoint: environment.userServiceUrl,
      messageServiceEndpoint: environment.messageServiceUrl,
      mailServiceEndpoint: environment.mailServiceUrl,
      didDomain: environment.didDomain,
      stateNamespace: environment.stateNamespace,
      anpServiceEndpoint: environment.anpServiceUrl,
      anpServiceDid: environment.anpServiceDid,
    );
  }

  final String serviceBaseUrl;
  final String didDomain;
  final String stateNamespace;
  final String? userServiceEndpoint;
  final String? messageServiceEndpoint;
  final String? mailServiceEndpoint;
  final String? anpServiceEndpoint;
  final String? anpServiceDid;
  final core.MessageTransportPolicy transportPolicy;

  core.AwikiImCoreConfig toCoreConfig() {
    return core.AwikiImCoreConfig(
      serviceBaseUrl: serviceBaseUrl,
      didDomain: didDomain,
      userServiceEndpoint: userServiceEndpoint,
      messageServiceEndpoint: messageServiceEndpoint,
      mailServiceEndpoint: mailServiceEndpoint,
      anpServiceEndpoint: anpServiceEndpoint,
      anpServiceDid: anpServiceDid,
      transportPolicy: transportPolicy,
    );
  }
}

String? _optionalFromEnvironment(String name, {String? defaultValue}) {
  final value = switch (name) {
    'AWIKI_BASE_URL' => const String.fromEnvironment('AWIKI_BASE_URL'),
    'AWIKI_SERVICE_BASE_URL' => const String.fromEnvironment(
      'AWIKI_SERVICE_BASE_URL',
    ),
    'AWIKI_USER_SERVICE_URL' => const String.fromEnvironment(
      'AWIKI_USER_SERVICE_URL',
    ),
    'AWIKI_MESSAGE_SERVICE_URL' => const String.fromEnvironment(
      'AWIKI_MESSAGE_SERVICE_URL',
    ),
    'AWIKI_MAIL_SERVICE_URL' => const String.fromEnvironment(
      'AWIKI_MAIL_SERVICE_URL',
    ),
    'AWIKI_DID_DOMAIN' => const String.fromEnvironment('AWIKI_DID_DOMAIN'),
    'AWIKI_STATE_NAMESPACE' => const String.fromEnvironment(
      'AWIKI_STATE_NAMESPACE',
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
