import 'dart:convert';

import 'package:http/http.dart' as http;

import 'awiki_service_error.dart';

class AwikiServiceClient {
  AwikiServiceClient({
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
    final response = await _httpClient
        .post(
          Uri.parse(baseUrl).resolve(path),
          headers: <String, String>{
            'Content-Type': 'application/json',
            if (bearerToken != null && bearerToken.isNotEmpty)
              'Authorization': 'Bearer $bearerToken',
          },
          body: jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'method': method,
            'params': params,
            'id': requestId,
          }),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AwikiServiceError(
        statusCode: response.statusCode,
        message: response.body,
      );
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map) {
      throw const AwikiServiceError(message: 'RPC response must be an object.');
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
        throw AwikiServiceError(
          rpcCode: int.tryParse(errorMap['code']?.toString() ?? ''),
          message: errorMap['message']?.toString() ?? error.toString(),
          data: errorMap['data'],
        );
      }
      throw AwikiServiceError(message: error.toString());
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
