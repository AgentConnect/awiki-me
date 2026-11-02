import 'dart:convert';
import 'dart:io';

const maxPinConfigBytes = 512 * 1024;

/// This availability check does not replace Core's pinned-key JWS verification.
void checkPinBackendResponse(int status, List<int> bytes) {
  if (bytes.length > maxPinConfigBytes) {
    throw const PinBackendUnavailable('response_too_large');
  }
  Object? body;
  try {
    body = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const PinBackendUnavailable('invalid_response');
  }
  if (status != HttpStatus.ok) {
    final error = body is Map ? body['error'] : null;
    final code = error is Map ? error['code'] : null;
    throw PinBackendUnavailable(
      code == 'configuration_expired'
          ? 'configuration_expired'
          : 'configuration_unavailable',
      status: status,
    );
  }
  final data = body is Map ? (body['data'] ?? body) : null;
  if (data is! Map ||
      data['config_hash'] is! String ||
      (data['config_hash'] as String).isEmpty ||
      data['config_jws'] is! String ||
      (data['config_jws'] as String).isEmpty) {
    throw const PinBackendUnavailable('invalid_response');
  }
}

class PinBackendUnavailable implements Exception {
  const PinBackendUnavailable(this.code, {this.status});

  final String code;
  final int? status;
}

Future<void> main() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    await (() async {
      final request = await client.getUrl(
        Uri.parse('https://awiki.info/user-service/v1/key-recovery/config'),
      );
      request.followRedirects = false;
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > maxPinConfigBytes) {
          throw const PinBackendUnavailable('response_too_large');
        }
        bytes.addAll(chunk);
      }
      checkPinBackendResponse(response.statusCode, bytes);
    })().timeout(const Duration(seconds: 20));
    stdout.writeln('Realm configuration availability preflight passed.');
  } on PinBackendUnavailable catch (error) {
    stderr.writeln(
      'Realm configuration preflight failed: ${error.code}'
      '${error.status == null ? '' : ' (HTTP ${error.status})'}. '
      'Repair through the service owner before starting PIN/full E2E.',
    );
    exitCode = 2;
  } catch (_) {
    // Never echo response bodies, exception messages or remote URLs.
    stderr.writeln(
      'Realm configuration preflight failed: transport_unavailable.',
    );
    exitCode = 2;
  } finally {
    client.close(force: true);
  }
}
