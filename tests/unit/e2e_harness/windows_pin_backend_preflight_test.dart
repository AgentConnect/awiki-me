import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/check_windows_pin_backend.dart';

void main() {
  test('available response remains subject to Core signature verification', () {
    final data = {
      'config_hash': 'unverified-configuration-projection',
      'config_jws': 'not-verified-by-this-availability-check',
    };
    checkPinBackendResponse(200, utf8.encode(jsonEncode(data)));
    checkPinBackendResponse(200, utf8.encode(jsonEncode({'data': data})));
  });

  test('expired configuration prevents starting an expensive E2E run', () {
    expect(
      () => checkPinBackendResponse(
        503,
        utf8.encode('{"error":{"code":"configuration_expired"}}'),
      ),
      throwsA(
        isA<PinBackendUnavailable>()
            .having((e) => e.code, 'code', 'configuration_expired')
            .having((e) => e.status, 'status', 503),
      ),
    );
  });

  test('unknown backend errors never become diagnostic text', () {
    expect(
      () => checkPinBackendResponse(
        500,
        utf8.encode('{"error":{"code":"private-value"}}'),
      ),
      throwsA(
        isA<PinBackendUnavailable>().having(
          (e) => e.code,
          'code',
          'configuration_unavailable',
        ),
      ),
    );
  });

  test('malformed and incomplete success bodies are rejected', () {
    for (final body in ['<html>', '{}', 'null', '{"config_jws":""}']) {
      expect(
        () => checkPinBackendResponse(200, utf8.encode(body)),
        throwsA(isA<PinBackendUnavailable>()),
      );
    }
  });

  test('oversized responses are rejected before JSON interpretation', () {
    expect(
      () =>
          checkPinBackendResponse(200, List.filled(maxPinConfigBytes + 1, 32)),
      throwsA(
        isA<PinBackendUnavailable>().having(
          (e) => e.code,
          'code',
          'response_too_large',
        ),
      ),
    );
  });
}
