// ignore_for_file: invalid_use_of_visible_for_testing_member
// Real loopback TLS; never touches an OS certificate store or account data.
import 'dart:io';

import 'package:awiki_me/src/core/app_error_classifier.dart';
import 'package:awiki_me/src/core/app_transport_failure.dart';
import 'package:awiki_me/src/data/services/app_http_client_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in ['valid', 'unknown-ca', 'expired', 'wrong-host']) {
    test('real TLS $scenario with supplemented process-local trust', () async {
      const fixtures = 'tests/e2e/fixtures/tls';
      final serverContext = SecurityContext()
        ..useCertificateChain(
          '$fixtures/${scenario == 'unknown-ca' ? 'valid' : scenario}.pem',
        )
        ..usePrivateKey('$fixtures/server.key');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      var requests = 0;
      server.listen(
        (request) {
          requests++;
          request.response.write('verified');
          request.response.close();
        },
        onError: (Object _) {
          /* Expected rejected handshakes. */
        },
      );
      addTearDown(() => server.close(force: true));

      // Represents a system/private root. Adding the public bundle must retain it.
      final roots = SecurityContext();
      if (scenario != 'unknown-ca') {
        roots.setTrustedCertificates('$fixtures/ca.pem');
      }
      final client = WindowsTrustHttpClient.forTesting(
        buildClient: () async {
          final context = await createWindowsTrustContext(context: roots);
          // Widget-test bindings normally replace HttpClient with a fake 400 client.
          return IOClient(
            HttpOverrides.runWithHttpOverrides(
              () => HttpClient(context: context),
              _RealHttpOverrides(),
            ),
          );
        },
      );
      addTearDown(client.close);
      final response = client.post(
        Uri.parse('https://127.0.0.1:${server.port}/'),
        body: 'once',
      );
      if (scenario == 'valid') {
        expect((await response).body, 'verified');
        expect(requests, 1);
      } else {
        await expectLater(
          response,
          throwsA(
            isA<AppStructuredError>().having(
              (e) => e.code,
              'code',
              tlsHandshakeFailureCode,
            ),
          ),
        );
        expect(requests, 0);
      }
    });
  }
}
