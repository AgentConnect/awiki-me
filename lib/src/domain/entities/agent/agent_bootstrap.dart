import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart';

import 'message_agent_runtime_provider.dart';

const daemonBootstrapSchema = 'awiki.daemon.bootstrap.v1';
const daemonBootstrapSecureSchema = 'awiki.daemon.bootstrap.secure.v1';
const userSubkeyPackageSchema = 'awiki.daemon.user_subkey_package.v2';
const appMessageHandlerRole = 'app_message_handler';
const appMessageHandlerRuntime = messageAgentProviderHermesRuntime;
const appMessageHandlerRuntimeProvider = messageAgentProviderHermesId;
const appMessageHandlerRuntimeProfile =
    messageAgentProviderHermesRuntimeProfile;
const daemonBootstrapDefaultTtl = Duration(minutes: 5);
const daemonBootstrapKeyDerivationLabel = 'AWIKI daemon bootstrap secure v1';

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
    this.displayName = messageAgentProviderHermesRuntimeDisplayName,
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
    required this.senderEphemeralPublicKey,
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
  final String senderEphemeralPublicKey;
  final String ciphertext;
  final Map<String, Object?> aad;
  final String? payloadSha256;

  Map<String, Object?> toJson() {
    _requireNonEmpty(recipientDaemonDid, 'recipientDaemonDid');
    _requireNonEmpty(recipientKeyId, 'recipientKeyId');
    _requireNonEmpty(senderHumanDid, 'senderHumanDid');
    _requireNonEmpty(operationId, 'operationId');
    _requireNonEmpty(nonce, 'nonce');
    _requireNonEmpty(senderEphemeralPublicKey, 'senderEphemeralPublicKey');
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
      'sender_ephemeral_public_key': senderEphemeralPublicKey.trim(),
      'ciphertext': ciphertext.trim(),
      'aad': Map<String, Object?>.unmodifiable(aad),
      if (hash != null) 'payload_sha256': hash,
    };
  }
}

class DaemonBootstrapPublicKey {
  const DaemonBootstrapPublicKey({
    required this.keyId,
    required this.publicKeyB64u,
    this.publicKeyMultibase,
    this.algorithm = 'x25519',
  });

  final String keyId;
  final String publicKeyB64u;
  final String? publicKeyMultibase;
  final String algorithm;

  factory DaemonBootstrapPublicKey.fromDiagnostics({
    required String daemonDid,
    required Map<String, Object?> diagnostics,
  }) {
    final keyId =
        _nonEmpty(diagnostics['bootstrap_key_id']?.toString()) ??
        '$daemonDid#key-3';
    final publicKeyB64u = _nonEmpty(
      diagnostics['bootstrap_public_key_b64u']?.toString(),
    );
    if (publicKeyB64u == null) {
      throw StateError('Daemon bootstrap public key is not available.');
    }
    final algorithm =
        _nonEmpty(diagnostics['bootstrap_key_algorithm']?.toString()) ??
        'x25519';
    return DaemonBootstrapPublicKey(
      keyId: keyId,
      publicKeyB64u: publicKeyB64u,
      publicKeyMultibase: _nonEmpty(
        diagnostics['bootstrap_public_key_multibase']?.toString(),
      ),
      algorithm: algorithm,
    ).._validateForDaemon(daemonDid);
  }

  List<int> publicKeyBytes({String? expectedDaemonDid}) {
    _validateForDaemon(expectedDaemonDid);
    final bytes = base64Url.decode(base64Url.normalize(publicKeyB64u.trim()));
    if (bytes.length != 32) {
      throw ArgumentError.value(
        publicKeyB64u,
        'publicKeyB64u',
        'must decode to 32 bytes',
      );
    }
    return bytes;
  }

  void _validateForDaemon([String? expectedDaemonDid]) {
    _requireNonEmpty(keyId, 'keyId');
    _requireNonEmpty(publicKeyB64u, 'publicKeyB64u');
    if (algorithm.trim().toLowerCase() != 'x25519') {
      throw ArgumentError.value(algorithm, 'algorithm', 'must be x25519');
    }
    final daemonDid = _nonEmpty(expectedDaemonDid);
    if (daemonDid != null && keyId.trim() != '$daemonDid#key-3') {
      throw ArgumentError.value(keyId, 'keyId', 'must equal $daemonDid#key-3');
    }
  }
}

class DaemonSecureBootstrapEncryptor {
  DaemonSecureBootstrapEncryptor({
    DateTime Function()? now,
    List<int> Function(int length)? randomBytes,
    X25519? x25519,
    Chacha20? chacha20,
  }) : _now = now ?? DateTime.now,
       _randomBytes = randomBytes ?? _secureRandomBytes,
       _x25519 = x25519 ?? X25519(),
       _chacha20 = chacha20 ?? Chacha20.poly1305Aead();

  final DateTime Function() _now;
  final List<int> Function(int length) _randomBytes;
  final X25519 _x25519;
  final Chacha20 _chacha20;

  Future<Map<String, Object?>> encrypt({
    required DaemonBootstrapEnvelope internalEnvelope,
    required String recipientDaemonDid,
    required DaemonBootstrapPublicKey recipientKey,
    Duration ttl = daemonBootstrapDefaultTtl,
  }) async {
    if (ttl <= Duration.zero) {
      throw ArgumentError.value(ttl, 'ttl', 'must be positive');
    }
    final issuedAt = _now().toUtc();
    final expiresAt = issuedAt.add(ttl);
    final payload = internalEnvelope.toJson();
    final plaintext = utf8.encode(jsonEncode(payload));
    final payloadSha256 = sha256.convert(plaintext).toString();
    final nonceBytes = _randomBytes(12);
    if (nonceBytes.length != 12) {
      throw StateError('secure bootstrap nonce must be 12 bytes');
    }
    final recipientPublicKey = SimplePublicKey(
      recipientKey.publicKeyBytes(expectedDaemonDid: recipientDaemonDid),
      type: KeyPairType.x25519,
    );
    final ephemeralKeyPair = await _x25519.newKeyPairFromSeed(_randomBytes(32));
    final ephemeralPublicKey = await ephemeralKeyPair.extractPublicKey();
    final senderEphemeralPublicKey = _base64UrlNoPad(ephemeralPublicKey.bytes);
    final nonce = _base64UrlNoPad(nonceBytes);
    final envelope = DaemonSecureBootstrapEnvelope(
      recipientDaemonDid: recipientDaemonDid,
      recipientKeyId: recipientKey.keyId,
      senderHumanDid: internalEnvelope.controllerDid,
      operationId: internalEnvelope.idempotencyKey,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      nonce: nonce,
      senderEphemeralPublicKey: senderEphemeralPublicKey,
      ciphertext: '',
      aad: <String, Object?>{
        'human_did': internalEnvelope.controllerDid,
        'daemon_agent_did': recipientDaemonDid,
        'binding_id': messageAgentEnsureOnceKey(
          userDid: internalEnvelope.userSubkeyPackage.userDid,
          appInstanceId: internalEnvelope.appInstanceId,
        ),
        'runtime_provider': appMessageHandlerRuntimeProvider,
        'runtime_profile': appMessageHandlerRuntimeProfile,
      },
      payloadSha256: payloadSha256,
    );
    final shared = await _x25519.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: recipientPublicKey,
    );
    final keyBytes = _deriveSecureBootstrapKey(
      sharedSecret: await shared.extractBytes(),
      envelope: envelope,
    );
    final secretBox = await _chacha20.encrypt(
      plaintext,
      secretKey: SecretKeyData(keyBytes),
      nonce: nonceBytes,
      aad: utf8.encode(_canonicalJson(_secureBootstrapAadValue(envelope))),
    );
    final ciphertextAndTag = <int>[
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ];
    return DaemonSecureBootstrapEnvelope(
      recipientDaemonDid: envelope.recipientDaemonDid,
      recipientKeyId: envelope.recipientKeyId,
      senderHumanDid: envelope.senderHumanDid,
      operationId: envelope.operationId,
      issuedAt: envelope.issuedAt,
      expiresAt: envelope.expiresAt,
      nonce: envelope.nonce,
      senderEphemeralPublicKey: envelope.senderEphemeralPublicKey,
      ciphertext: _base64UrlNoPad(ciphertextAndTag),
      aad: envelope.aad,
      payloadSha256: envelope.payloadSha256,
    ).toJson();
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

List<int> _deriveSecureBootstrapKey({
  required List<int> sharedSecret,
  required DaemonSecureBootstrapEnvelope envelope,
}) {
  final digest = sha256.convert(<int>[
    ...utf8.encode(daemonBootstrapKeyDerivationLabel),
    ...sharedSecret,
    ...utf8.encode(envelope.recipientDaemonDid),
    ...utf8.encode(envelope.recipientKeyId),
    ...utf8.encode(envelope.senderHumanDid),
    ...utf8.encode(envelope.operationId),
    ...utf8.encode(envelope.nonce),
  ]);
  return digest.bytes;
}

Map<String, Object?> _secureBootstrapAadValue(
  DaemonSecureBootstrapEnvelope envelope,
) {
  return <String, Object?>{
    'schema': daemonBootstrapSecureSchema,
    'recipient_daemon_did': envelope.recipientDaemonDid.trim(),
    'recipient_key_id': envelope.recipientKeyId.trim(),
    'sender_human_did': envelope.senderHumanDid.trim(),
    'operation_id': envelope.operationId.trim(),
    'issued_at': envelope.issuedAt.toUtc().toIso8601String(),
    'expires_at': envelope.expiresAt.toUtc().toIso8601String(),
    'nonce': envelope.nonce.trim(),
    'sender_ephemeral_public_key': envelope.senderEphemeralPublicKey.trim(),
    'aad': envelope.aad,
    if (_nonEmpty(envelope.payloadSha256) != null)
      'payload_sha256': envelope.payloadSha256!.trim().toLowerCase(),
  };
}

String _canonicalJson(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return jsonEncode(value);
  }
  if (value is Map) {
    final entries =
        value.entries
            .map((entry) => MapEntry(entry.key.toString(), entry.value))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return '{${entries.map((entry) => '${jsonEncode(entry.key)}:${_canonicalJson(entry.value)}').join(',')}}';
  }
  if (value is Iterable) {
    return '[${value.map(_canonicalJson).join(',')}]';
  }
  return jsonEncode(value.toString());
}

String _base64UrlNoPad(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

List<int> _secureRandomBytes(int length) {
  if (length <= 0) {
    throw ArgumentError.value(length, 'length', 'must be positive');
  }
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}
