import 'dart:convert';

import 'package:http/http.dart' as http;

const String awikiClientVersionHeaderName = 'X-AWiki-Client-Version';

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
    this.clientVersionHeader,
  }) : _httpClient = httpClient ?? http.Client(),
       _baseUri = Uri.parse(baseUrl);

  final String baseUrl;
  final http.Client _httpClient;
  final Uri _baseUri;
  final Duration timeout;
  final String? clientVersionHeader;

  Future<Map<String, Object?>> rpcCall({
    required String path,
    required String method,
    required Map<String, Object?> params,
    String? bearerToken,
    String requestId = 'req-1',
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    _appendClientVersionHeader(headers, Uri.parse(baseUrl).resolve(path));
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

  Future<http.Response> get(Uri uri) {
    final headers = <String, String>{};
    _appendClientVersionHeader(headers, uri);
    return _httpClient.get(uri, headers: headers).timeout(timeout);
  }

  Future<http.Response> postJson(
    Uri uri, {
    required Map<String, Object?> body,
  }) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    _appendClientVersionHeader(headers, uri);
    return _httpClient
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(timeout);
  }

  void _appendClientVersionHeader(Map<String, String> headers, Uri uri) {
    final value = clientVersionHeader?.trim();
    if (value != null && value.isNotEmpty && _sameOrigin(_baseUri, uri)) {
      headers[awikiClientVersionHeaderName] = value;
    }
  }
}

bool _sameOrigin(Uri left, Uri right) =>
    left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
    left.host.toLowerCase() == right.host.toLowerCase() &&
    left.port == right.port;

class AwikiOnboardingUtilityClient {
  AwikiOnboardingUtilityClient({
    required AwikiOnboardingUtilityHttpClient serviceClient,
    this.timeout = const Duration(seconds: 20),
  }) : _serviceClient = serviceClient;

  static const String handleRpcEndpoint = '/user-service/v1/handle/rpc';
  static const String profileRpcEndpoint = '/user-service/v1/did/profile/rpc';
  static const String serverInfoEndpoint = '/user-service/v1/server-info';
  static const String emailSendEndpoint = '/user-service/v1/auth/email-send';
  static const String emailStatusEndpoint = '/user-service/v1/auth/email-status';
  static const String registrationOtpPurpose = 'awiki.identity.register.v1';

  final AwikiOnboardingUtilityHttpClient _serviceClient;
  final Duration timeout;

  Future<Map<String, Object?>> loadServerInfo() async {
    final response = await _serviceClient.get(
      Uri.parse(_serviceClient.baseUrl).resolve(serverInfoEndpoint),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AwikiOnboardingUtilityError(
        statusCode: response.statusCode,
        message: response.body,
      );
    }
    final payload = jsonDecode(response.body);
    if (payload is! Map) {
      throw const AwikiOnboardingUtilityError(
        message: 'Server-info response must be an object.',
      );
    }
    return payload.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  Future<void> sendOtp({required String phone}) async {
    await _serviceClient.rpcCall(
      path: handleRpcEndpoint,
      method: 'send_otp',
      params: <String, Object?>{'phone': phone},
    );
  }

  Future<void> sendRegistrationOtp({
    required String phone,
    required String purpose,
    required String handle,
    required String domain,
    required String fullHandle,
  }) async {
    await _serviceClient.rpcCall(
      path: handleRpcEndpoint,
      method: 'send_otp',
      params: <String, Object?>{
        'phone': phone,
        'purpose': purpose,
        'handle': handle,
        'domain': domain,
        'full_handle': fullHandle,
      },
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
    required String handle,
  }) async {
    final normalizedHandle = handle.trim().toLowerCase();
    final response = await _serviceClient.postJson(
      Uri.parse(baseUrl).resolve(emailSendEndpoint),
      body: <String, Object?>{
        'email': email.trim().toLowerCase(),
        'handle': normalizedHandle,
      },
    );
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
    required String handle,
  }) async {
    final normalizedHandle = handle.trim().toLowerCase();
    final response = await _serviceClient.get(
      Uri.parse(baseUrl)
          .resolve(emailStatusEndpoint)
          .replace(
            queryParameters: <String, String>{
              'email': email.trim().toLowerCase(),
              'handle': normalizedHandle,
            },
          ),
    );
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
