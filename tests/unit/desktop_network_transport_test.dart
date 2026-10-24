// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/data/services/app_http_client_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'desktop adapter forwards per-request auth and streams without buffering',
    () async {
      final chunks = StreamController<List<int>>();
      final started = <String>[];
      var initialized = 0;
      var closed = false;
      final client = DesktopRuntimeHttpClient.forTesting(
        initialize: () async {
          initialized++;
        },
        transmit:
            ({
              required method,
              required url,
              required headers,
              required body,
              followRedirects = true,
              abortTrigger,
            }) async {
              started.add(headers['authorization']!);
              expect(method, 'POST');
              expect(body, [1, 2]);
              expect(followRedirects, isFalse);
              return core.AwikiNetworkResponse(
                statusCode: 202,
                headers: {'content-type': 'application/octet-stream'},
                body: const Stream.empty(),
                close: () async {},
              );
            },
      );
      for (final owner in ['owner-a', 'owner-b']) {
        final request =
            http.Request('POST', Uri.parse('https://example.test/rpc'))
              ..headers['authorization'] = owner
              ..bodyBytes = [1, 2]
              ..followRedirects = false;
        expect((await client.send(request)).statusCode, 202);
      }
      expect(started, ['owner-a', 'owner-b']);
      expect(initialized, 2);
      client.close();
      final streaming = DesktopRuntimeHttpClient.forTesting(
        initialize: () async {},
        transmit:
            ({
              required method,
              required url,
              required headers,
              required body,
              followRedirects = true,
              abortTrigger,
            }) async => core.AwikiNetworkResponse(
              statusCode: 200,
              headers: {},
              body: const Stream.empty(),
              close: () async {},
            ),
      );
      streaming.close();
      await expectLater(
        streaming.send(http.Request('GET', Uri.parse('https://example.test'))),
        throwsA(isA<http.ClientException>()),
      );
      final streamClient = DesktopRuntimeHttpClient.forTesting(
        initialize: () async {},
        transmit:
            ({
              required method,
              required url,
              required headers,
              required body,
              followRedirects = true,
              abortTrigger,
            }) async => core.AwikiNetworkResponse(
              statusCode: 200,
              headers: {},
              body: chunks.stream,
              close: () async {
                closed = true;
              },
            ),
      );
      final response = await streamClient.send(
        http.Request('GET', Uri.parse('https://example.test')),
      );
      final values = response.stream.toBytes();
      chunks.add([3]);
      chunks.add([4]);
      await chunks.close();
      expect(await values, [3, 4]);
      expect(closed, isTrue);
      streamClient.close();
    },
  );

  test(
    'closing a pending request maps native cancellation to http abort',
    () async {
      final entered = Completer<void>();
      final client = DesktopRuntimeHttpClient.forTesting(
        initialize: () async {},
        transmit:
            ({
              required method,
              required url,
              required headers,
              required body,
              followRedirects = true,
              abortTrigger,
            }) async {
              entered.complete();
              await abortTrigger;
              throw StateError('native cancelled');
            },
      );
      final pending = client.send(
        http.Request('POST', Uri.parse('https://example.test')),
      );
      await entered.future;
      final assertion = expectLater(
        pending,
        throwsA(isA<http.RequestAbortedException>()),
      );
      client.close();
      await assertion;
    },
  );
}
