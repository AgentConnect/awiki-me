import '../../application/models/push_installation.dart';
import '../../application/ports/push_installation_port.dart';
import '../../domain/services/remote_push_client.dart';
import 'package:flutter/foundation.dart';

import '../services/authenticated_user_service_rpc_client.dart';
import '../services/awiki_onboarding_utility_client.dart';

final class UserServicePushInstallationAdapter implements PushInstallationPort {
  UserServicePushInstallationAdapter({
    required String userServiceUrl,
    AwikiOnboardingUtilityHttpClient? client,
    AuthenticatedUserServiceRpcClient? authenticatedClient,
  }) : _client =
           client ?? AwikiOnboardingUtilityHttpClient(baseUrl: userServiceUrl),
       _authenticatedClient = authenticatedClient;

  static const String endpoint = '/user-service/push/rpc';

  final AwikiOnboardingUtilityHttpClient _client;
  final AuthenticatedUserServiceRpcClient? _authenticatedClient;

  UserServicePushInstallationAdapter withAuthenticatedClient(
    AuthenticatedUserServiceRpcClient authenticatedClient,
  ) {
    return UserServicePushInstallationAdapter(
      userServiceUrl: _client.baseUrl,
      client: _client,
      authenticatedClient: authenticatedClient,
    );
  }

  @override
  Future<PushInstallation> upsert(RemotePushRegistration registration) async {
    final result = await _rpcCall(
      method: 'upsert_installation',
      params: <String, Object?>{
        'provider': registration.provider,
        'provider_device_id': registration.providerDeviceId,
        'platform': registration.platform,
        if (registration.logicalDeviceId != null)
          'logical_device_id': registration.logicalDeviceId,
        if (registration.appId != null) 'app_id': registration.appId,
      },
    );
    final installation = _parseInstallation(result, 'upsert_installation');
    _expectBoundValue(installation.provider, registration.provider, 'provider');
    _expectBoundValue(
      installation.providerDeviceId,
      registration.providerDeviceId,
      'provider_device_id',
    );
    _expectBoundValue(installation.platform, registration.platform, 'platform');
    _expectBoundValue(
      installation.logicalDeviceId,
      registration.logicalDeviceId,
      'logical_device_id',
    );
    _expectBoundValue(installation.appId, registration.appId, 'app_id');
    _expectBoundValue(installation.status, 'active', 'status');
    return installation;
  }

  @override
  Future<PushInstallation> disable(String installationId) async {
    final result = await _rpcCall(
      method: 'disable_installation',
      params: <String, Object?>{'installation_id': installationId},
    );
    final installation = _parseInstallation(result, 'disable_installation');
    _expectBoundValue(
      installation.installationId,
      installationId,
      'installation_id',
    );
    _expectBoundValue(installation.status, 'disabled', 'status');
    return installation;
  }

  Future<Map<String, Object?>> _rpcCall({
    required String method,
    required Map<String, Object?> params,
  }) async {
    final authenticatedClient = _authenticatedClient;
    if (authenticatedClient == null) {
      throw StateError('push_installation_auth_required');
    }
    try {
      return await authenticatedClient.rpcCall(
        path: endpoint,
        method: method,
        params: params,
      );
    } on AwikiOnboardingUtilityError catch (error) {
      debugPrint(
        '[awiki_me][remote-push][installation-rpc-failed] '
        'method=$method '
        'http=${error.statusCode ?? 0} '
        'rpc=${error.rpcCode ?? 0}',
      );
      rethrow;
    }
  }
}

PushInstallation _parseInstallation(
  Map<String, Object?> result,
  String operation,
) {
  final value = result['installation'];
  if (value is! Map) {
    throw FormatException('$operation.installation must be an object');
  }
  final installation = value.map<String, Object?>(
    (key, item) => MapEntry(key.toString(), item),
  );
  return PushInstallation(
    installationId: _requiredResponseString(
      installation,
      'installation_id',
      operation,
    ),
    provider: _requiredResponseString(installation, 'provider', operation),
    providerDeviceId: _requiredResponseString(
      installation,
      'provider_device_id',
      operation,
    ),
    platform: _requiredResponseString(installation, 'platform', operation),
    logicalDeviceId: _nullableResponseString(
      installation,
      'logical_device_id',
      operation,
    ),
    appId: _nullableResponseString(installation, 'app_id', operation),
    status: _requiredResponseString(installation, 'status', operation),
  );
}

String _requiredResponseString(
  Map<String, Object?> value,
  String key,
  String operation,
) {
  final item = value[key];
  if (item is! String || item.isEmpty || item.trim() != item) {
    throw FormatException(
      '$operation.installation.$key must be a non-empty string',
    );
  }
  return item;
}

String? _nullableResponseString(
  Map<String, Object?> value,
  String key,
  String operation,
) {
  if (!value.containsKey(key)) {
    throw FormatException('$operation.installation.$key is required');
  }
  final item = value[key];
  if (item == null) {
    return null;
  }
  if (item is! String || item.isEmpty || item.trim() != item) {
    throw FormatException(
      '$operation.installation.$key must be null or a non-empty string',
    );
  }
  return item;
}

void _expectBoundValue(Object? actual, Object? expected, String field) {
  if (actual != expected) {
    throw FormatException('push installation response $field mismatch');
  }
}
