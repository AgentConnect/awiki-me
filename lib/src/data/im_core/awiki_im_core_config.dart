import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/config/awiki_environment_config.dart';

class AwikiImCoreEnvironmentConfig {
  const AwikiImCoreEnvironmentConfig({
    required this.serviceBaseUrl,
    required this.didDomain,
    this.userServiceEndpoint,
    this.messageServiceEndpoint,
    this.mailServiceEndpoint,
    this.anpServiceEndpoint,
    this.anpServiceDid,
    this.transportPolicy = core.MessageTransportPolicy.auto,
  });

  factory AwikiImCoreEnvironmentConfig.fromEnvironment() {
    final environment = AwikiEnvironmentConfig.fromEnvironment();
    return AwikiImCoreEnvironmentConfig.fromAwikiEnvironment(environment);
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
      anpServiceEndpoint: environment.anpServiceUrl,
      anpServiceDid: environment.anpServiceDid,
    );
  }

  final String serviceBaseUrl;
  final String didDomain;
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
