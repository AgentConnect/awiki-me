import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'flutter/support/hosted_gateway_fixture.dart';

void main() {
  test('fixed fixture target and private source file are required', () async {
    final root = await Directory.systemTemp.createTemp(
      'hosted-fixture-contract-',
    );
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/private.json');
    final state = {
      'domain': hostedDomain,
      'provider': 'email',
      'contact': 'gw-mcp-e2e-${'a' * 32}@example.test',
      'handle': 'gw-mcp-e2e-${'a' * 16}',
      'identity': {
        'handle': 'gw-mcp-e2e-${'a' * 16}.$hostedDomain',
        'did': 'did:wba:$hostedDomain:user:synthetic',
      },
    };
    await file.writeAsString(jsonEncode(state));
    await Process.run('chmod', ['600', file.path]);
    final fixture = await HostedGatewayFixture.load(file.path);
    fixture.close();
    await file.writeAsString(jsonEncode({...state, 'domain': 'awiki.info'}));
    await expectLater(HostedGatewayFixture.load(file.path), throwsStateError);
    await file.writeAsString(jsonEncode(state));
    await Process.run('chmod', ['644', file.path]);
    await expectLater(HostedGatewayFixture.load(file.path), throwsStateError);
  });

  test(
    'phone registration requires private reserved fixture and exact target',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hosted-phone-contract-',
      );
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/private.json');
      final state = {
        'domain': hostedDomain,
        'provider': 'phone',
        'contact': '+15550012345',
        'handle': 'gw-mcp-e2e-${'a' * 16}',
        'code': '123456',
      };
      await file.writeAsString(jsonEncode(state));
      await Process.run('chmod', ['600', file.path]);
      final fixture = await HostedGatewayFixture.loadPhoneRegistration(
        file.path,
      );
      expect(fixture.gateway.provider, 'phone');
      expect(fixture.code, state['code']);
      fixture.gateway.close();
      for (final change in [
        {'domain': 'awiki.info'},
        {'provider': 'email'},
        {'contact': '+8613800000000'},
        {'handle': 'ordinary-user'},
        {'code': '123'},
      ]) {
        await file.writeAsString(jsonEncode({...state, ...change}));
        await expectLater(
          HostedGatewayFixture.loadPhoneRegistration(file.path),
          throwsStateError,
        );
      }
      await file.writeAsString(jsonEncode(state));
      await Process.run('chmod', ['644', file.path]);
      await expectLater(
        HostedGatewayFixture.loadPhoneRegistration(file.path),
        throwsStateError,
      );
      await Process.run('chmod', ['600', file.path]);
      final link = Link('${root.path}/linked.json');
      await link.create(file.path);
      await expectLater(
        HostedGatewayFixture.loadPhoneRegistration(link.path),
        throwsStateError,
      );
    },
  );

  test(
    'expected denial remains explicit and unexpected success fails',
    () async {
      var status = 403;
      final fixture = HostedGatewayFixture(
        'synthetic',
        'synthetic',
        '',
        client: MockClient(
          (request) async => http.Response(
            request.url.path == '/connect/state'
                ? '{"csrf":"synthetic"}'
                : '{"error":"root_key_not_hosted","retryable":false}',
            request.url.path == '/connect/state' ? 200 : status,
          ),
        ),
      );
      addTearDown(fixture.close);
      final result = await fixture.post(
        'device-requests',
        {},
        expectedStatus: 403,
      );
      expect(result['error'], 'root_key_not_hosted');
      status = 200;
      await expectLater(
        fixture.post('device-requests', {}, expectedStatus: 403),
        throwsStateError,
      );
    },
  );

  test(
    'browser redirects and foreign paths never carry a cookie elsewhere',
    () async {
      var requests = 0;
      final fixture = HostedGatewayFixture(
        'synthetic',
        'synthetic',
        'synthetic',
        client: MockClient((request) async {
          requests++;
          expect(request.url.origin, hostedOrigin);
          expect(request.followRedirects, isFalse);
          return http.Response(
            'private-response',
            302,
            headers: {'location': 'https://other.test'},
          );
        }),
      );
      addTearDown(fixture.close);
      await expectLater(fixture.request('/connect'), throwsStateError);
      await expectLater(fixture.request('//other.test'), throwsStateError);
      expect(requests, 1);
    },
  );

  test(
    'secure cookie and unique operation IDs stay within owning fixture',
    () async {
      var calls = 0;
      final fixture = HostedGatewayFixture(
        'synthetic',
        'synthetic',
        'synthetic',
        client: MockClient((request) async {
          calls++;
          if (calls == 1) {
            return http.Response(
              '',
              200,
              headers: {
                'set-cookie':
                    'awiki_browser=synthetic; Secure; HttpOnly; SameSite=Lax',
              },
            );
          }
          expect(request.headers['cookie'], 'awiki_browser=synthetic');
          return http.Response('{}', 200);
        }),
      );
      addTearDown(fixture.close);
      await fixture.request('/connect');
      await fixture.request('/connect/state');
      final operations = List.generate(20, (_) => fixture.operationId());
      expect(operations.toSet().length, 20);
      for (final value in operations) {
        expect(
          RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
          ).hasMatch(value),
          isTrue,
        );
      }
    },
  );
}
