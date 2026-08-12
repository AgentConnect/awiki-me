// [INPUT]: Two loopback App-pair clients, checkpoints, and transient SAS values.
// [OUTPUT]: Authenticated Join/functional phase exchange and secret-free SAS results.
// [POS]: Contract test for the dual-App E2E coordinator.

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/app_pair_protocol.dart';

void main() {
  test(
    'two isolated roles exchange checkpoints and compare SAS in memory',
    () async {
      final server = await AppPairCoordinatorServer.start(
        token: List<String>.filled(48, 't').join(),
      );
      addTearDown(server.close);
      final admin = AppPairCoordinatorClient(
        endpoint: server.endpoint,
        token: server.token,
      );
      final joiner = AppPairCoordinatorClient(
        endpoint: server.endpoint,
        token: server.token,
      );

      await admin.publish(
        'admin',
        'ready',
        data: const <String, Object?>{
          'did': 'did:wba:awiki.info:alice',
          'handle': 'alice.awiki.info',
          'adminDeviceId': 'admin-device',
        },
      );
      expect(await joiner.waitFor('admin', 'ready'), const <String, Object?>{
        'did': 'did:wba:awiki.info:alice',
        'handle': 'alice.awiki.info',
        'adminDeviceId': 'admin-device',
      });
      await joiner.publish(
        'joiner',
        'pending',
        data: const <String, Object?>{
          'joinSessionId': 'join-session',
          'joinedDeviceId': 'member-device',
        },
      );
      await admin.publish('admin', 'verification_started');
      await joiner.publish(
        'joiner',
        'authorized',
        data: const <String, Object?>{
          'adminDeviceId': 'admin-device',
          'joinedDeviceId': 'member-device',
        },
      );
      await admin.publish('admin', 'complete');

      final results = await Future.wait<bool>(<Future<bool>>[
        admin.submitAndCompareSas('admin', '123456'),
        joiner.submitAndCompareSas('joiner', '123456'),
      ]);
      expect(results, everyElement(isTrue));
    },
  );

  test('checkpoint payload rejects secret-bearing fields', () async {
    final server = await AppPairCoordinatorServer.start(
      token: List<String>.filled(48, 't').join(),
    );
    addTearDown(server.close);
    final client = AppPairCoordinatorClient(
      endpoint: server.endpoint,
      token: server.token,
    );

    await expectLater(
      client.publish(
        'admin',
        'ready',
        data: const <String, Object?>{
          'did': 'did:wba:awiki.info:alice',
          'handle': 'alice.awiki.info',
          'adminDeviceId': 'admin-device',
          'details': <String, Object?>{'sasValue': '123456'},
        },
      ),
      throwsA(isA<AppPairProtocolException>()),
    );
    await expectLater(
      client.publish(
        'admin',
        'verification_started',
        data: const <String, Object?>{'code': '123456'},
      ),
      throwsA(isA<AppPairProtocolException>()),
    );
    await expectLater(
      client.publish('joiner', 'unapproved'),
      throwsA(isA<AppPairProtocolException>()),
    );
  });

  test(
    'functional checkpoints accept only their exact public identifiers',
    () async {
      final server = await AppPairCoordinatorServer.start(
        token: List<String>.filled(48, 't').join(),
      );
      addTearDown(server.close);
      final client = AppPairCoordinatorClient(
        endpoint: server.endpoint,
        token: server.token,
      );

      await client.publish('joiner', 'functional_ready');
      await client.publish('joiner', 'functional_tail_only_verified');
      await client.publish(
        'admin',
        'functional_agents_created',
        data: const <String, Object?>{
          'daemonDid': 'did:wba:awiki.info:agent:daemon:e1_daemon',
          'daemonHandle': 'daemon',
          'codexDid': 'did:wba:awiki.info:agent:runtime:e1_codex',
          'codexHandle': 'codex',
          'claudeDid': 'did:wba:awiki.info:agent:runtime:e1_claude',
          'claudeHandle': 'claude',
          'archiveDid': 'did:wba:awiki.info:agent:runtime:e1_archive',
          'archiveHandle': 'archive',
        },
      );
      await client.publish('joiner', 'functional_agents_converged');
      await client.publish(
        'joiner',
        'functional_agent_prompt_sent',
        data: const <String, Object?>{
          'conversationId': 'dm:peer-scope:v1:agent',
          'messageId': 'msg-agent',
        },
      );
      await client.publish('admin', 'functional_agent_prompt_visible');
      await client.publish(
        'admin',
        'functional_peer_ready',
        data: const <String, Object?>{
          'peerDid': 'did:wba:awiki.info:e1_peer',
          'peerHandle': 'peer',
          'conversationId': 'dm:peer-scope:v1:peer',
          'historicalMessageId': 'msg-before-join',
          'historicalText': 'before-join-message',
        },
      );
      await client.publish(
        'admin',
        'functional_outbound_sent',
        data: const <String, Object?>{
          'conversationId': 'conv-1',
          'messageId': 'msg-1',
        },
      );
      await client.publish('joiner', 'functional_own_sync_visible');
      await client.publish(
        'joiner',
        'functional_joiner_outbound_sent',
        data: const <String, Object?>{'messageId': 'msg-joiner'},
      );
      await client.publish('admin', 'functional_joiner_outbound_visible');
      await client.publish(
        'admin',
        'functional_reply_sent',
        data: const <String, Object?>{'messageId': 'msg-2'},
      );
      await client.publish('joiner', 'functional_reply_visible');
      await client.publish('joiner', 'functional_agent_observer_ready');

      await expectLater(
        client.publish(
          'admin',
          'functional_outbound_sent',
          data: const <String, Object?>{
            'conversationId': 'conv-1',
            'messageId': 'msg-1',
            'content': 'not-allowed',
          },
        ),
        throwsA(isA<AppPairProtocolException>()),
      );
    },
  );

  test(
    'content-sync checkpoints accept only canonical public identifiers',
    () async {
      final server = await AppPairCoordinatorServer.start(
        token: List<String>.filled(48, 't').join(),
      );
      addTearDown(server.close);
      final client = AppPairCoordinatorClient(
        endpoint: server.endpoint,
        token: server.token,
      );

      await client.publish(
        'admin',
        'content_fixture_ready',
        data: const <String, Object?>{
          'peerDid': 'did:wba:awiki.info:peer',
          'directConversationId': 'dm:peer-scope:v1:peer',
          'groupDid': 'did:wba:awiki.info:group:g1',
          'groupConversationId': 'group:did:wba:awiki.info:group:g1',
          'preGroupMessageId': 'g0',
          'preAttachmentMessageId': 'f0',
          'preAttachmentId': 'attachment-0',
        },
      );
      await client.publish('joiner', 'content_prejoin_absent');
      await client.publish(
        'admin',
        'content_postjoin_sent',
        data: const <String, Object?>{
          'groupMessageId': 'g1',
          'attachmentMessageId': 'f1',
          'attachmentId': 'attachment-1',
        },
      );
      await client.publish('joiner', 'content_unread_baseline_ready');

      await expectLater(
        client.publish(
          'admin',
          'content_postjoin_sent',
          data: const <String, Object?>{
            'groupMessageId': 'g1',
            'attachmentMessageId': 'f1',
            'attachmentId': 'attachment-1',
            'content': 'forbidden',
          },
        ),
        throwsA(isA<AppPairProtocolException>()),
      );
    },
  );

  test('account-state checkpoints accept every exact route shape', () async {
    final server = await AppPairCoordinatorServer.start(
      token: List<String>.filled(48, 't').join(),
    );
    addTearDown(server.close);
    final client = AppPairCoordinatorClient(
      endpoint: server.endpoint,
      token: server.token,
    );
    const routes = <String, List<String>>{
      'joiner\u0000account_state_stage4_baseline_ready': <String>[],
      'admin\u0000account_state_agent_renamed': <String>[
        'agentDid',
        'displayName',
      ],
      'joiner\u0000account_state_agent_rename_converged': <String>[],
      'admin\u0000account_state_agent_unbound': <String>['agentDid'],
      'joiner\u0000account_state_agent_unbind_converged': <String>[],
      'admin\u0000account_state_archive_fixture_ready': <String>[
        'agentDid',
        'displayName',
        'handle',
      ],
      'joiner\u0000account_state_archive_fixture_converged_active': <String>[],
      'admin\u0000account_state_archive_product_delete_completed': <String>[
        'agentDid',
      ],
      'joiner\u0000account_state_archive_converged': <String>[],
      'admin\u0000account_state_agent_deleted': <String>['agentDid'],
      'joiner\u0000account_state_agent_delete_converged': <String>[],
      'admin\u0000account_state_profile_updated': <String>[
        'displayName',
        'bio',
      ],
      'joiner\u0000account_state_profile_converged': <String>[],
      'admin\u0000account_state_isolation_fixture_ready': <String>[
        'agentDid',
        'displayName',
      ],
      'joiner\u0000account_state_isolation_fixture_converged': <String>[],
      'admin\u0000account_state_isolation_mutated': <String>[
        'agentDid',
        'oldDisplayName',
        'newDisplayName',
        'profileDisplayName',
        'messageId',
        'receiptId',
      ],
      'joiner\u0000account_state_isolation_recovered': <String>[],
      'admin\u0000account_state_registry_ready': <String>[],
      'joiner\u0000account_state_registry_observer_ready': <String>[],
      'admin\u0000account_state_registry_revoked': <String>[],
      'joiner\u0000account_state_registry_fence_observed': <String>[],
      'admin\u0000account_state_post_revoke_message_committed': <String>[
        'messageId',
      ],
      'joiner\u0000account_state_revoked_device_auth_fenced': <String>[],
    };

    for (final entry in routes.entries) {
      final separator = entry.key.indexOf('\u0000');
      final role = entry.key.substring(0, separator);
      final phase = entry.key.substring(separator + 1);
      await client.publish(
        role,
        phase,
        data: <String, Object?>{
          for (final field in entry.value) field: 'value-$field',
        },
      );
    }
  });

  test('mismatched SAS returns only a negative comparison', () async {
    final server = await AppPairCoordinatorServer.start(
      token: List<String>.filled(48, 't').join(),
    );
    addTearDown(server.close);
    final admin = AppPairCoordinatorClient(
      endpoint: server.endpoint,
      token: server.token,
    );
    final joiner = AppPairCoordinatorClient(
      endpoint: server.endpoint,
      token: server.token,
    );

    final results = await Future.wait<bool>(<Future<bool>>[
      admin.submitAndCompareSas('admin', '123456'),
      joiner.submitAndCompareSas('joiner', '654321'),
    ]);
    expect(results, everyElement(isFalse));
  });

  test('CLI failure diagnostics expose only allowlisted stable codes', () {
    const secret = 'secret-bearing-service-message';
    final diagnostic = safeCliFailureDiagnostic(
      exitCode: 5,
      stdout: '',
      stderr:
          '{"ok":false,"error":{"code":"service_error",'
          '"message":"$secret","details":'
          '{"service_code":"anp.device_state_changed",'
          '"token":"$secret"}}}',
    );

    expect(
      diagnostic,
      'exit=5, code=service_error, '
      'serviceCode=anp.device_state_changed',
    );
    expect(diagnostic, isNot(contains(secret)));
  });

  test('CLI failure diagnostics reject unstructured or unsafe output', () {
    const secret = 'Bearer top-secret';

    expect(
      safeCliFailureDiagnostic(
        exitCode: 4,
        stdout: secret,
        stderr:
            '{"error":{"code":"permission denied: Bearer top-secret",'
            '"details":{"service_code":"token.top-secret/value"}}}',
      ),
      'exit=4',
    );
  });
}
