import 'package:awiki_me/src/application/config/awiki_environment_config.dart';

/// Shared configuration for the real device scenarios; no backend capabilities
/// or product behavior are synthesized here.
AwikiEnvironmentConfig remoteDeviceEnvironment({
  required String baseUrl,
  required String userServiceUrl,
  required String messageServiceUrl,
  required String mailServiceUrl,
  required String didDomain,
  required String anpServiceUrl,
  required String anpServiceDid,
  bool enableRootTransfer = false,
  bool enableStep4 = false,
  bool enableAppPairFunctional = false,
  bool enableMessageSyncCore = false,
  bool enableDeviceRevoke = false,
}) => AwikiEnvironmentConfig(
  baseUrl: baseUrl,
  userServiceUrl: userServiceUrl,
  messageServiceUrl: messageServiceUrl,
  mailServiceUrl: mailServiceUrl,
  didDomain: didDomain,
  anpServiceUrl: anpServiceUrl,
  anpServiceDid: anpServiceDid,
  agentImEnabled: enableAppPairFunctional,
  messageSyncV2ReadEnabled:
      enableStep4 || enableAppPairFunctional || enableMessageSyncCore,
  multiDeviceDeviceRevokeEnabled:
      enableStep4 || enableAppPairFunctional || enableDeviceRevoke,
  multiDeviceDirectE2eeEnabled: enableRootTransfer,
  multiDeviceGroupE2eeEnabled: enableStep4,
);
