import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/app_pair_protocol.dart';
import '../../e2e/runner.dart';
import '../../e2e/test_catalog.dart';

void main() {
  test('Web selection is one App pair with a CLI peer on configured HTTPS', () {
    final selected = DesktopE2eOptions.parse([
      '--case',
      'did-method-web',
    ]).e2eCase;
    expect(selected, DesktopE2eCase.didMethodWeb);
    expect(selected.usesRemoteAppPairScenario, isTrue);
    expect(selected.requiresCliPeer, isTrue);
    expect(selected.caseIds, ['DID-WEB-APP-E2E-001']);
    final manifest = DesktopE2eSuiteManifest.load(Directory.current);
    final suite = manifest.definitionFor(selected);
    suite.validateCodeCaseIds(selected.caseIds);
    suite.validateRemoteTargetValues(
      didDomain: 'web.test',
      serviceUrls: ['https://web.test'],
    );
    expect(
      () => suite.validateRemoteTargetValues(
        didDomain: 'web.test',
        serviceUrls: ['https://another.test'],
      ),
      throwsA(isA<Exception>()),
    );
    final catalog = AppTestCatalog.load(Directory.current);
    expect(
      catalog
          .caseById[selected.caseIds.single]!
          .assertionContract!
          .assertionIds,
      contains('DID-WEB-APP-E2E-001:same_pending_join_reopened_without_otp'),
    );
    expect(
      manifest.fullSuites().where((s) => s.name == selected.caseName),
      hasLength(1),
    );
  });

  test(
    'Web checkpoints retain exact cleanup references and reject secrets',
    () async {
      final server = await AppPairCoordinatorServer.start(token: 'w' * 48);
      addTearDown(server.close);
      final client = AppPairCoordinatorClient(
        endpoint: server.endpoint,
        token: server.token,
      );
      await client.publish(
        'admin',
        'web_registration_intent',
        data: {'handle': 'web-test'},
      );
      await client.publish(
        'admin',
        'web_peer_registration_intent',
        data: {'handle': 'wba-peer'},
      );
      await client.publish(
        'admin',
        'cleanup_scope',
        data: {'accountId': 'web-account'},
      );
      await client.publish(
        'admin',
        'web_peer_ready',
        data: {
          'peerDid': 'did:wba:web.test:user:peer',
          'conversationId': 'dm:peer-scope:v1:test',
        },
      );
      await client.publish('joiner', 'web_member_readonly');
      await client.publish(
        'admin',
        'web_incoming',
        data: {'messageId': 'inbound-id'},
      );
      await client.publish(
        'joiner',
        'web_reply',
        data: {'messageId': 'reply-id'},
      );
      await client.publish('admin', 'web_revoked');
      await client.publish('joiner', 'web_auth_fenced');
      expect(server.webCleanupLedger['accountIds'], ['web-account']);
      expect(server.webCleanupLedger['web_registration_intent'], {
        'handle': 'web-test',
      });
      expect(server.webCleanupLedger['web_reply'], {'messageId': 'reply-id'});
      await expectLater(
        client.publish(
          'admin',
          'web_registration_intent',
          data: {'handle': 'another-handle'},
        ),
        throwsA(isA<AppPairProtocolException>()),
      );
      await expectLater(
        client.publish(
          'admin',
          'web_registration_intent',
          data: {'handle': 'web-test', 'token': 'forbidden-test-value'},
        ),
        throwsA(isA<AppPairProtocolException>()),
      );
      await expectLater(
        client.publish(
          'joiner',
          'web_peer_ready',
          data: {
            'peerDid': 'did:web:web.test:peer',
            'conversationId': 'dm:test',
          },
        ),
        throwsA(isA<AppPairProtocolException>()),
      );
    },
  );
}
