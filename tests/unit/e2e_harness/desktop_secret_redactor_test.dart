import 'package:flutter_test/flutter_test.dart';
import '../../e2e/runner/redaction.dart';

void main() {
  test('masks dynamic loopback VM auth before known secrets split the path', () {
    final redactor = DesktopSecretRedactor(['42']);
    final output = redactor.redact(
      'The Dart VM service is listening on http://127.0.0.1:60690/syntheticVmAuth42=/',
    );
    expect(
      output,
      'The Dart VM service is listening on http://127.0.0.1:60690/<redacted-local-auth>/',
    );
    expect(output, isNot(contains('syntheticVmAuth')));
  });
  test('masks websocket auth without padding', () {
    final output = DesktopSecretRedactor(
      [],
    ).redact('connect ws://localhost:54321/syntheticUnpaddedAuth/ws');
    expect(output, 'connect ws://localhost:54321/<redacted-local-auth>/ws');
  });
  test('masks IPv6 auth and an unpadded VM banner', () {
    final output = DesktopSecretRedactor([]).redact(
      'http://[::1]:12345/syntheticIpv6Auth= and Dart VM service is listening on http://localhost:12346/syntheticBannerAuth/',
    );
    expect(
      output,
      'http://[::1]:12345/<redacted-local-auth> and Dart VM service is listening on http://localhost:12346/<redacted-local-auth>/',
    );
  });
  test('preserves ordinary routes and public target URLs', () {
    const value =
        'http://127.0.0.1:12345/callback ws://localhost:23456/events https://awiki.info/user-service/server-info';
    expect(DesktopSecretRedactor([]).redact(value), value);
  });
}
