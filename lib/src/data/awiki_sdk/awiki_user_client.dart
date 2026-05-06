import 'dart:convert';

import 'package:http/http.dart' as http;

import 'awiki_service_client.dart';
import 'awiki_service_error.dart';

class AwikiUserClient {
  AwikiUserClient({
    required AwikiServiceClient serviceClient,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _serviceClient = serviceClient,
       _httpClient = httpClient ?? http.Client();

  static const String didAuthRpcEndpoint = '/user-service/did-auth/rpc';
  static const String handleRpcEndpoint = '/user-service/handle/rpc';
  static const String profileRpcEndpoint = '/user-service/did/profile/rpc';
  static const String relationshipsRpcEndpoint =
      '/user-service/did/relationships/rpc';
  static const String emailSendEndpoint = '/user-service/auth/email-send';
  static const String emailStatusEndpoint = '/user-service/auth/email-status';

  final AwikiServiceClient _serviceClient;
  final http.Client _httpClient;
  final Duration timeout;

  Future<void> sendOtp({required String phone}) async {
    await _serviceClient.rpcCall(
      path: handleRpcEndpoint,
      method: 'send_otp',
      params: <String, Object?>{'phone': phone},
    );
  }

  Future<Map<String, Object?>> register({
    required Map<String, Object?> params,
  }) {
    return _serviceClient.rpcCall(
      path: didAuthRpcEndpoint,
      method: 'register',
      params: params,
    );
  }

  Future<Map<String, Object?>> recoverHandle({
    required Map<String, Object?> params,
  }) {
    return _serviceClient.rpcCall(
      path: didAuthRpcEndpoint,
      method: 'recover_handle',
      params: params,
    );
  }

  Future<Map<String, Object?>> verifyDidAuth({
    required String authorization,
    required String domain,
  }) {
    return _serviceClient.rpcCall(
      path: didAuthRpcEndpoint,
      method: 'verify',
      params: <String, Object?>{
        'authorization': authorization,
        'domain': domain,
      },
    );
  }

  Future<Map<String, Object?>> getMe({required String bearerToken}) {
    return _serviceClient.rpcCall(
      path: profileRpcEndpoint,
      method: 'get_me',
      params: const <String, Object?>{},
      bearerToken: bearerToken,
    );
  }

  Future<Map<String, Object?>> getPublicProfile({
    required String didOrHandle,
    String? bearerToken,
  }) {
    return _serviceClient.rpcCall(
      path: profileRpcEndpoint,
      method: 'get_public_profile',
      params: didOrHandle.startsWith('did:')
          ? <String, Object?>{'did': didOrHandle}
          : <String, Object?>{'handle': didOrHandle},
      bearerToken: bearerToken,
    );
  }

  Future<Map<String, Object?>> updateMe({
    required Map<String, Object?> patch,
    required String bearerToken,
  }) {
    return _serviceClient.rpcCall(
      path: profileRpcEndpoint,
      method: 'update_me',
      params: patch,
      bearerToken: bearerToken,
    );
  }

  Future<Map<String, Object?>> relationshipRpc({
    required String method,
    required Map<String, Object?> params,
    required String bearerToken,
  }) {
    return _serviceClient.rpcCall(
      path: relationshipsRpcEndpoint,
      method: method,
      params: params,
      bearerToken: bearerToken,
    );
  }

  Future<void> sendEmailVerification({
    required String baseUrl,
    required String email,
  }) async {
    final response = await _httpClient
        .post(
          Uri.parse(baseUrl).resolve(emailSendEndpoint),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'email': email.trim().toLowerCase(),
          }),
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AwikiServiceError(
        statusCode: response.statusCode,
        message: response.body,
      );
    }
  }

  Future<bool> checkEmailVerified({
    required String baseUrl,
    required String email,
  }) async {
    final response = await _httpClient
        .get(
          Uri.parse(baseUrl)
              .resolve(emailStatusEndpoint)
              .replace(
                queryParameters: <String, String>{
                  'email': email.trim().toLowerCase(),
                },
              ),
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AwikiServiceError(
        statusCode: response.statusCode,
        message: response.body,
      );
    }
    final payload = jsonDecode(response.body);
    if (payload is Map) {
      return payload['verified'] == true;
    }
    return false;
  }
}
