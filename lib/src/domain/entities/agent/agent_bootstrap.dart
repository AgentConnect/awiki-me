import 'dart:convert';

import 'package:crypto/crypto.dart';

const daemonBootstrapSchema = 'awiki.daemon.bootstrap.v1';
const userSubkeyPackageSchema = 'awiki.daemon.user_subkey_package.v1';
const appMessageHandlerRole = 'app_message_handler';
const appMessageHandlerRuntime = 'hermes';

const defaultMessageAgentActions = <String>[
  'message.summarize_plain',
  'message.create_draft',
  'contact.read',
  'contact.update_display_name',
  'contact.update_note',
];

const defaultMessageAgentScopes = <String>[
  'message.inbox.read.plain',
  'message.history.read.plain',
  'message.send.plain',
  'message.summarize_plain',
  'contact.read',
  'contact.update_display_name',
  'contact.update_note',
  'agent.manage',
  'app.action.request',
];

class UserSubkeyPackage {
  const UserSubkeyPackage({
    required this.userDid,
    required this.verificationMethod,
    required this.publicKeyMultibase,
    required this.privateKeyMultibase,
    this.keyType,
    this.expiresAt,
    this.allowedScopes = defaultMessageAgentScopes,
  });

  final String userDid;
  final String verificationMethod;
  final String publicKeyMultibase;
  final String privateKeyMultibase;
  final String? keyType;
  final DateTime? expiresAt;
  final List<String> allowedScopes;

  Map<String, Object?> toJson() {
    _requireNonEmpty(userDid, 'userDid');
    _validateDaemonKey(
      userDid: userDid,
      verificationMethod: verificationMethod,
    );
    _requireNonEmpty(publicKeyMultibase, 'publicKeyMultibase');
    _requireNonEmpty(privateKeyMultibase, 'privateKeyMultibase');
    return <String, Object?>{
      'schema': userSubkeyPackageSchema,
      'user_did': userDid.trim(),
      'verification_method': verificationMethod.trim(),
      if (_nonEmpty(keyType) != null) 'key_type': keyType!.trim(),
      'public_key_multibase': publicKeyMultibase.trim(),
      'private_key_multibase': privateKeyMultibase.trim(),
      if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
      'allowed_scopes': allowedScopes,
    };
  }
}

class DesiredMessageAgent {
  const DesiredMessageAgent({
    this.role = appMessageHandlerRole,
    this.runtime = appMessageHandlerRuntime,
    this.displayName = 'Hermes Message Agent',
    required this.ensureOnceKey,
    this.runtimeRegistrationToken,
    this.autoCreate = true,
    this.plainMessageVisible = true,
    this.e2eeVisible = false,
    this.allowedActions = defaultMessageAgentActions,
  });

  final String role;
  final String runtime;
  final String displayName;
  final String ensureOnceKey;
  final String? runtimeRegistrationToken;
  final bool autoCreate;
  final bool plainMessageVisible;
  final bool e2eeVisible;
  final List<String> allowedActions;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'role': role,
      'runtime': runtime,
      'display_name': displayName,
      'ensure_once_key': ensureOnceKey,
      if (_nonEmpty(runtimeRegistrationToken) != null)
        'runtime_registration_token': runtimeRegistrationToken!.trim(),
      'auto_create': autoCreate,
      'plain_message_visible': plainMessageVisible,
      'e2ee_visible': e2eeVisible,
      'allowed_actions': allowedActions,
    };
  }
}

class AppCapabilityPolicy {
  const AppCapabilityPolicy({
    this.capabilities = defaultMessageAgentActions,
    this.requireConfirmationForWriteActions = true,
  });

  final List<String> capabilities;
  final bool requireConfirmationForWriteActions;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'awiki.app.capabilities.v1',
      'capabilities': capabilities,
      'require_confirmation_for_write_actions':
          requireConfirmationForWriteActions,
    };
  }
}

class DaemonBootstrapEnvelope {
  const DaemonBootstrapEnvelope({
    required this.bootstrapId,
    required this.idempotencyKey,
    required this.appInstanceId,
    required this.controllerDid,
    this.userHandle,
    required this.userSubkeyPackage,
    required this.desiredMessageAgent,
    this.capabilityPolicy = const AppCapabilityPolicy(),
  });

  final String bootstrapId;
  final String idempotencyKey;
  final String appInstanceId;
  final String controllerDid;
  final String? userHandle;
  final UserSubkeyPackage userSubkeyPackage;
  final DesiredMessageAgent desiredMessageAgent;
  final AppCapabilityPolicy capabilityPolicy;

  Map<String, Object?> toJson() {
    if (_nonEmpty(bootstrapId) == null) {
      throw ArgumentError.value(
        bootstrapId,
        'bootstrapId',
        'must not be empty',
      );
    }
    if (_nonEmpty(idempotencyKey) == null) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'must not be empty',
      );
    }
    if (_nonEmpty(appInstanceId) == null) {
      throw ArgumentError.value(
        appInstanceId,
        'appInstanceId',
        'must not be empty',
      );
    }
    if (_nonEmpty(controllerDid) == null) {
      throw ArgumentError.value(
        controllerDid,
        'controllerDid',
        'must not be empty',
      );
    }
    return <String, Object?>{
      'schema': daemonBootstrapSchema,
      'bootstrap_id': bootstrapId,
      'idempotency_key': idempotencyKey,
      'app_instance_id': appInstanceId,
      'controller_did': controllerDid,
      if (_nonEmpty(userHandle) != null) 'user_handle': userHandle!.trim(),
      'user_subkey_package': userSubkeyPackage.toJson(),
      'capability_policy': capabilityPolicy.toJson(),
      'desired_message_agent': desiredMessageAgent.toJson(),
      'sync_policy': <String, Object?>{
        'e2ee_default': 'not_supported_in_mvp',
        'plain_default': 'agent_visible',
        'require_confirmation_for_external_send': true,
      },
    };
  }
}

String messageAgentBootstrapId({
  required String userDid,
  required String appInstanceId,
}) => 'boot_${_stableBootstrapSuffix(userDid, appInstanceId)}';

String messageAgentBootstrapIdempotencyKey({
  required String userDid,
  required String appInstanceId,
}) => 'message-agent-bootstrap:$userDid:$appInstanceId';

String messageAgentEnsureOnceKey({
  required String userDid,
  required String appInstanceId,
}) => 'app-message-agent:$userDid:$appInstanceId';

String defaultDaemonVerificationMethod(String userDid) =>
    '$userDid#daemon-key-1';

void _validateDaemonKey({
  required String userDid,
  required String verificationMethod,
}) {
  final expected = defaultDaemonVerificationMethod(userDid.trim());
  if (verificationMethod.trim() != expected) {
    throw ArgumentError.value(
      verificationMethod,
      'verificationMethod',
      'must equal $expected',
    );
  }
}

void _requireNonEmpty(String value, String name) {
  if (_nonEmpty(value) == null) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}

String _stableBootstrapSuffix(String userDid, String appInstanceId) {
  final digest = sha256.convert(utf8.encode('$userDid:$appInstanceId'));
  return digest.toString().substring(0, 24);
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
