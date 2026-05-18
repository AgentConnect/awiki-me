import 'common.dart';
import 'error_models.dart';

class ImClientConfig {
  const ImClientConfig({
    this.messageServiceBaseUrl,
    this.runtimeMode = ImRuntimeMode.fake,
    required this.workspaceId,
    this.storePath,
    this.logLevel = ImLogLevel.info,
    this.requestTimeout = const Duration(seconds: 30),
    this.realtimeConnectTimeout = const Duration(seconds: 10),
    this.enableLocalCache = true,
    this.enableOutbox = true,
  });

  final Uri? messageServiceBaseUrl;
  final ImRuntimeMode runtimeMode;
  final String workspaceId;
  final String? storePath;
  final ImLogLevel logLevel;
  final Duration requestTimeout;
  final Duration realtimeConnectTimeout;
  final bool enableLocalCache;
  final bool enableOutbox;
}

enum ImLogLevel { debug, info, warning, error, none }

class ImSessionContext {
  const ImSessionContext({
    required this.credentialName,
    required this.did,
    this.handle,
    this.displayName,
    this.jwtToken,
    this.didDocument = const <String, Object?>{},
    this.keyMaterialRef,
    this.importedPrivateKey,
    this.signerDelegateRef,
  });

  final String credentialName;
  final String did;
  final String? handle;
  final String? displayName;
  final String? jwtToken;
  final Map<String, Object?> didDocument;
  final ImKeyMaterialRef? keyMaterialRef;
  final ImImportedPrivateKey? importedPrivateKey;
  final ImSignerDelegateRef? signerDelegateRef;
}

class ImKeyMaterialRef {
  const ImKeyMaterialRef({required this.refId});

  final String refId;
}

class ImImportedPrivateKey {
  const ImImportedPrivateKey({
    required this.keyId,
    required this.privateKeyPem,
  });

  final String keyId;
  final String privateKeyPem;
}

class ImSignerDelegateRef {
  const ImSignerDelegateRef({required this.delegateId});

  final String delegateId;
}

class ImAuthUpdate {
  const ImAuthUpdate({
    this.jwtToken,
    this.responseHeaders = const <String, String>{},
    this.expiresAt,
  });

  final String? jwtToken;
  final Map<String, String> responseHeaders;
  final DateTime? expiresAt;
}

class ImEngineStatusDto {
  const ImEngineStatusDto({
    required this.initialized,
    required this.hasSession,
    required this.runtimeMode,
    required this.connectionState,
    this.storePath,
    this.schemaVersion,
    this.lastError,
    this.metadata = const <String, Object?>{},
  });

  final bool initialized;
  final bool hasSession;
  final ImRuntimeMode runtimeMode;
  final ImConnectionState connectionState;
  final String? storePath;
  final int? schemaVersion;
  final ImErrorDto? lastError;
  final Map<String, Object?> metadata;
}

class ImCapabilitiesDto {
  const ImCapabilitiesDto({
    required this.runtimeMode,
    required this.localCache,
    required this.outbox,
    required this.realtime,
    required this.attachments,
    required this.advancedAttachments,
    required this.directSecure,
    required this.groupE2ee,
    required this.migration,
    this.metadata = const <String, Object?>{},
  });

  final ImRuntimeMode runtimeMode;
  final bool localCache;
  final bool outbox;
  final bool realtime;
  final bool attachments;
  final bool advancedAttachments;
  final bool directSecure;
  final bool groupE2ee;
  final bool migration;
  final Map<String, Object?> metadata;
}

class ImConnectionStateDto {
  const ImConnectionStateDto({
    required this.state,
    required this.runtimeMode,
    required this.changedAt,
    this.lastErrorCode,
    this.lastErrorMessage,
  });

  final ImConnectionState state;
  final ImRuntimeMode runtimeMode;
  final DateTime changedAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
}
