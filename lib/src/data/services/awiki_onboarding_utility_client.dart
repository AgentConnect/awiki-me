import 'dart:convert';

import 'package:http/http.dart' as http;

class AwikiOnboardingUtilityError implements Exception {
  const AwikiOnboardingUtilityError({
    this.statusCode,
    this.rpcCode,
    required this.message,
    this.data,
  });

  final int? statusCode;
  final int? rpcCode;
  final String message;
  final Object? data;

  @override
  String toString() {
    if (rpcCode != null) {
      return 'AwikiOnboardingUtilityError rpc $rpcCode: $message';
    }
    if (statusCode != null) {
      return 'AwikiOnboardingUtilityError http $statusCode: $message';
    }
    return 'AwikiOnboardingUtilityError: $message';
  }
}

class AwikiOnboardingUtilityHttpClient {
  AwikiOnboardingUtilityHttpClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _httpClient;
  final Duration timeout;

  Future<Map<String, Object?>> rpcCall({
    required String path,
    required String method,
    required Map<String, Object?> params,
    String? bearerToken,
    String requestId = 'req-1',
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = bearerToken?.trim();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await _httpClient
        .post(
          Uri.parse(baseUrl).resolve(path),
          headers: headers,
          body: jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'method': method,
            'params': params,
            'id': requestId,
          }),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AwikiOnboardingUtilityError(
        statusCode: response.statusCode,
        message: response.body,
      );
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map) {
      throw const AwikiOnboardingUtilityError(
        message: 'RPC response must be an object.',
      );
    }
    final decoded = payload.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
    final error = decoded['error'];
    if (error != null) {
      if (error is Map) {
        final errorMap = error.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
        throw AwikiOnboardingUtilityError(
          rpcCode: int.tryParse(errorMap['code']?.toString() ?? ''),
          message: errorMap['message']?.toString() ?? error.toString(),
          data: errorMap['data'],
        );
      }
      throw AwikiOnboardingUtilityError(message: error.toString());
    }

    final result = decoded['result'];
    if (result is Map) {
      return result.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    if (result is List) {
      return <String, Object?>{'items': result};
    }
    return <String, Object?>{'value': result};
  }
}

class AwikiOnboardingUtilityClient {
  AwikiOnboardingUtilityClient({
    required AwikiOnboardingUtilityHttpClient serviceClient,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _serviceClient = serviceClient,
       _httpClient = httpClient ?? http.Client();

  static const String handleRpcEndpoint = '/user-service/handle/rpc';
  static const String profileRpcEndpoint = '/user-service/did/profile/rpc';
  static const String emailSendEndpoint = '/user-service/auth/email-send';
  static const String emailStatusEndpoint = '/user-service/auth/email-status';

  final AwikiOnboardingUtilityHttpClient _serviceClient;
  final http.Client _httpClient;
  final Duration timeout;

  Future<void> sendOtp({required String phone}) async {
    await _serviceClient.rpcCall(
      path: handleRpcEndpoint,
      method: 'send_otp',
      params: <String, Object?>{'phone': phone},
    );
  }

  Future<Map<String, Object?>> getPublicProfile({required String didOrHandle}) {
    return _serviceClient.rpcCall(
      path: profileRpcEndpoint,
      method: 'get_public_profile',
      params: didOrHandle.startsWith('did:')
          ? <String, Object?>{'did': didOrHandle}
          : <String, Object?>{'handle': didOrHandle},
    );
  }

  Future<Map<String, Object?>> lookupHandle({required String handle}) {
    return _serviceClient.rpcCall(
      path: handleRpcEndpoint,
      method: 'lookup',
      params: <String, Object?>{'handle': handle},
    );
  }

  Future<Map<String, Object?>> validateHandle({
    required String handle,
    String? domain,
  }) {
    return _serviceClient.rpcCall(
      path: handleRpcEndpoint,
      method: 'validate',
      params: <String, Object?>{
        'handle': handle,
        if (domain != null && domain.trim().isNotEmpty)
          'domain': domain.trim().toLowerCase(),
      },
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
      throw AwikiOnboardingUtilityError(
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
      throw AwikiOnboardingUtilityError(
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
