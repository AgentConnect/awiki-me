import 'dart:convert';

import 'package:crypto/crypto.dart';

const daemonBootstrapSchema = 'awiki.daemon.bootstrap.v1';
const daemonBootstrapSecureSchema = 'awiki.daemon.bootstrap.secure.v1';
const userSubkeyPackageSchema = 'awiki.daemon.user_subkey_package.v2';
const appMessageHandlerRole = 'app_message_handler';
const appMessageHandlerRuntime = 'hermes';
const appMessageHandlerRuntimeProvider = 'hermes';
const appMessageHandlerRuntimeProfile = 'message_agent';

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
    String? privateKeyPem,
    String? privateKeyMultibase,
    this.keyType,
    this.keyAlgorithm = 'Ed25519',
    this.privateKeyEncoding = 'pem',
    this.expiresAt,
    this.allowedScopes = defaultMessageAgentScopes,
  }) : privateKeyPem = privateKeyPem ?? privateKeyMultibase ?? '',
       privateKeyMultibase = privateKeyMultibase ?? privateKeyPem ?? '';

  final String userDid;
  final String verificationMethod;
  final String publicKeyMultibase;
  final String privateKeyPem;
  @Deprecated('Use privateKeyPem for PEM v2 packages.')
  final String privateKeyMultibase;
  final String? keyType;
  final String? keyAlgorithm;
  final String privateKeyEncoding;
  final DateTime? expiresAt;
  final List<String> allowedScopes;

  Map<String, Object?> toJson() {
    _requireNonEmpty(userDid, 'userDid');
    _validateDaemonKey(
      userDid: userDid,
      verificationMethod: verificationMethod,
    );
    _requireNonEmpty(publicKeyMultibase, 'publicKeyMultibase');
    _requireNonEmpty(privateKeyPem, 'privateKeyPem');
    if (privateKeyEncoding.trim() != 'pem') {
      throw ArgumentError.value(
        privateKeyEncoding,
        'privateKeyEncoding',
        'must be pem for $userSubkeyPackageSchema',
      );
    }
    return <String, Object?>{
      'schema': userSubkeyPackageSchema,
      'user_did': userDid.trim(),
      'verification_method': verificationMethod.trim(),
      if (_nonEmpty(keyType) != null) 'key_type': keyType!.trim(),
      if (_nonEmpty(keyAlgorithm) != null)
        'key_algorithm': keyAlgorithm!.trim(),
      'public_key_multibase': publicKeyMultibase.trim(),
      'private_key_encoding': privateKeyEncoding.trim(),
      'private_key_pem': privateKeyPem.trim(),
      if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
      'allowed_scopes': allowedScopes,
    };
  }
}

class DesiredMessageAgent {
  const DesiredMessageAgent({
    this.role = appMessageHandlerRole,
    this.runtime = appMessageHandlerRuntime,
    this.runtimeProvider = appMessageHandlerRuntimeProvider,
    this.runtimeProfile = appMessageHandlerRuntimeProfile,
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
  final String runtimeProvider;
  final String runtimeProfile;
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
      'runtime_provider': runtimeProvider,
      'runtime_profile': runtimeProfile,
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
    this.runId,
    required this.userSubkeyPackage,
    required this.desiredMessageAgent,
    this.capabilityPolicy = const AppCapabilityPolicy(),
  });

  final String bootstrapId;
  final String idempotencyKey;
  final String appInstanceId;
  final String controllerDid;
  final String? userHandle;
  final String? runId;
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
      if (_nonEmpty(runId) != null) 'run_id': runId!.trim(),
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

class DaemonSecureBootstrapEnvelope {
  const DaemonSecureBootstrapEnvelope({
    required this.recipientDaemonDid,
    required this.recipientKeyId,
    required this.senderHumanDid,
    required this.operationId,
    required this.issuedAt,
    required this.expiresAt,
    required this.nonce,
    required this.ciphertext,
    required this.aad,
    this.payloadSha256,
  });

  final String recipientDaemonDid;
  final String recipientKeyId;
  final String senderHumanDid;
  final String operationId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String nonce;
  final String ciphertext;
  final Map<String, Object?> aad;
  final String? payloadSha256;

  Map<String, Object?> toJson() {
    _requireNonEmpty(recipientDaemonDid, 'recipientDaemonDid');
    _requireNonEmpty(recipientKeyId, 'recipientKeyId');
    _requireNonEmpty(senderHumanDid, 'senderHumanDid');
    _requireNonEmpty(operationId, 'operationId');
    _requireNonEmpty(nonce, 'nonce');
    _requireNonEmpty(ciphertext, 'ciphertext');
    if (!expiresAt.toUtc().isAfter(issuedAt.toUtc())) {
      throw ArgumentError.value(
        expiresAt,
        'expiresAt',
        'must be after issuedAt',
      );
    }
    _rejectPrivateBootstrapKeys(aad);
    final hash = _nonEmpty(payloadSha256);
    if (hash != null &&
        (hash.length != 64 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hash))) {
      throw ArgumentError.value(
        payloadSha256,
        'payloadSha256',
        'must be a 64-character hex digest',
      );
    }
    return <String, Object?>{
      'schema': daemonBootstrapSecureSchema,
      'recipient_daemon_did': recipientDaemonDid.trim(),
      'recipient_key_id': recipientKeyId.trim(),
      'sender_human_did': senderHumanDid.trim(),
      'operation_id': operationId.trim(),
      'issued_at': issuedAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'nonce': nonce.trim(),
      'ciphertext': ciphertext.trim(),
      'aad': Map<String, Object?>.unmodifiable(aad),
      if (hash != null) 'payload_sha256': hash,
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

String messageAgentBootstrapAttemptId({
  required String userDid,
  required String appInstanceId,
  String? runId,
}) {
  final base = messageAgentBootstrapId(
    userDid: userDid,
    appInstanceId: appInstanceId,
  );
  final suffix = _bootstrapAttemptSuffix(runId);
  return suffix == null ? base : '${base}_$suffix';
}

String messageAgentBootstrapAttemptIdempotencyKey({
  required String userDid,
  required String appInstanceId,
  String? runId,
}) {
  final base = messageAgentBootstrapIdempotencyKey(
    userDid: userDid,
    appInstanceId: appInstanceId,
  );
  final suffix = _bootstrapAttemptSuffix(runId);
  return suffix == null ? base : '$base:attempt:$suffix';
}

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

void _rejectPrivateBootstrapKeys(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      _rejectPrivateBootstrapName(entry.key.toString());
      _rejectPrivateBootstrapKeys(entry.value);
    }
    return;
  }
  if (value is Iterable) {
    for (final item in value) {
      _rejectPrivateBootstrapKeys(item);
    }
    return;
  }
  if (value is String) {
    _rejectPrivateBootstrapName(value);
  }
}

void _rejectPrivateBootstrapName(String value) {
  final lower = value.toLowerCase();
  const forbidden = <String>[
    'private_key',
    'private-key',
    'private key',
    'bootstrap_secret',
    'wss_credential',
    'session_private',
    'key_package_private',
    'begin private key',
  ];
  for (final marker in forbidden) {
    if (lower.contains(marker)) {
      throw ArgumentError.value(value, 'aad', 'must not contain $marker');
    }
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

String? _bootstrapAttemptSuffix(String? runId) {
  final value = _nonEmpty(runId);
  if (value == null) {
    return null;
  }
  final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9_.:-]+'), '-');
  if (normalized.length <= 64) {
    return normalized;
  }
  final digest = sha256.convert(utf8.encode(normalized)).toString();
  return '${normalized.substring(0, 48)}-${digest.substring(0, 12)}';
}
