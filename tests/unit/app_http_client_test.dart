// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:io';

import 'package:awiki_me/src/core/app_error_classifier.dart';
import 'package:awiki_me/src/core/app_transport_failure.dart';
import 'package:awiki_me/src/data/services/app_http_client_io.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:awiki_me/src/l10n/app_message.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Client extends MockClient {
  _Client(super.handler);
  int closes = 0;
  @override
  void close() => closes++;
}

class _BrokenBundle extends CachingAssetBundle {
  _BrokenBundle({this.missing = false});
  final bool missing;
  @override
  Future<ByteData> load(String key) async {
    if (missing) throw StateError('asset missing');
    return ByteData.sublistView(Uint8List.fromList([1, 2, 3]));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final url = Uri.parse('https://example.com/private?otp=secret');

  test('packaged bundle passes digest and certificate parser', () async {
    await createWindowsTrustContext(context: SecurityContext());
  });

  for (final missing in [false, true]) {
    test('bad bundle fails closed before send (missing=$missing)', () async {
      var sends = 0;
      final client = WindowsTrustHttpClient.forTesting(
        buildClient: () async {
          await createWindowsTrustContext(
            bundle: _BrokenBundle(missing: missing),
          );
          return MockClient((_) async {
            sends++;
            return http.Response('', 200);
          });
        },
      );
      addTearDown(client.close);
      await expectLater(
        client.post(url, body: 'sensitive'),
        throwsA(
          isA<AppStructuredError>().having(
            (e) => e.code,
            'code',
            trustBundleFailureCode,
          ),
        ),
      );
      expect(sends, 0);
    });
  }

  test(
    'concurrent first requests initialize once and each POST sends once',
    () async {
      final ready = Completer<http.Client>();
      var builds = 0;
      var sends = 0;
      final underlying = _Client((_) async {
        sends++;
        return http.Response('ok', 200);
      });
      final client = WindowsTrustHttpClient.forTesting(
        buildClient: () {
          builds++;
          return ready.future;
        },
      );
      final one = client.post(url, body: 'one');
      final two = client.post(url, body: 'two');
      ready.complete(underlying);
      await Future.wait([one, two]);
      expect(builds, 1);
      expect(sends, 2);
      client.close();
      client.close();
      expect(underlying.closes, 1);
      await expectLater(client.get(url), throwsA(isA<http.ClientException>()));
    },
  );

  test(
    'close during initialization closes eventual client without sending',
    () async {
      final ready = Completer<http.Client>();
      var sends = 0;
      final underlying = _Client((_) async {
        sends++;
        return http.Response('', 200);
      });
      final client = WindowsTrustHttpClient.forTesting(
        buildClient: () => ready.future,
      );
      final pending = client.post(url);
      final assertion = expectLater(
        pending,
        throwsA(isA<http.ClientException>()),
      );
      client.close();
      ready.complete(underlying);
      await assertion;
      expect(sends, 0);
      expect(underlying.closes, 1);
    },
  );

  test('TLS failure is typed, redacted and never replays a POST', () async {
    var sends = 0;
    final client = WindowsTrustHttpClient.forTesting(
      buildClient: () async => MockClient((_) async {
        sends++;
        throw const HandshakeException('secret payload and path');
      }),
      appVersion: () async => '0.1.34+44',
    );
    addTearDown(client.close);
    final utility = AwikiOnboardingUtilityHttpClient(
      baseUrl: 'https://example.com',
      httpClient: client,
    );
    try {
      await utility.rpcCall(
        path: '/private?otp=secret',
        method: 'send_otp',
        params: {'phone': 'sensitive'},
        bearerToken: 'token',
      );
      fail('Expected TLS failure');
    } on AppStructuredError catch (error) {
      expect(error.code, tlsHandshakeFailureCode);
      expect(
        appTransportDiagnostic(error),
        'code=$tlsHandshakeFailureCode\nhost=example.com\napp=0.1.34+44\nca_bundle=$windowsCaBundleVersion',
      );
      expect(AppMessage.fromError(error).id, 'secureConnectionFailed');
    }
    expect(sends, 1);
    utility.close(); // Injected client remains usable/owned by caller.
    await expectLater(client.get(url), throwsA(isA<AppStructuredError>()));
    expect(sends, 2);
  });

  test('network failures retain their original category', () async {
    final client = WindowsTrustHttpClient.forTesting(
      buildClient: () async => MockClient((_) async {
        throw const SocketException('connection refused');
      }),
    );
    addTearDown(client.close);
    await expectLater(client.get(url), throwsA(isA<SocketException>()));
  });
}
