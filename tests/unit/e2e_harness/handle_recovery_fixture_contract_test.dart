import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/handle_recovery_fixture_contract.dart';

void main() {
  group('Handle Recovery fixture checkpoint', () {
    test('persists only opaque references, counts, and stage state', () async {
      final checkpoint = _localCheckpoint();
      final encoded = jsonEncode(checkpoint.toJson());

      expect(encoded, isNot(contains('did:')));
      expect(encoded, isNot(contains('/tmp/')));
      expect(encoded, isNot(contains('message body')));
      expect(encoded, isNot(contains('fixture-run-42')));
      expect(
        checkpoint.references.values,
        everyElement(matches(r'^sha256:[0-9a-f]{64}$')),
      );

      final directory = await Directory.systemTemp.createTemp(
        'awiki-recovery-fixture-contract-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/checkpoint.json');
      await checkpoint.write(file);
      final restored = HandleRecoveryFixtureCheckpoint.read(file);

      restored.requireReplayOf(checkpoint);
      expect(restored.stage, HandleRecoveryFixtureStage.checkpointReady);
      expect(restored.kind, HandleRecoveryFixtureKind.localData);
    });

    test('ready Fresh Root checkpoint requires every reusable resource', () {
      final checkpoint = HandleRecoveryFixtureCheckpoint.fromRaw(
        caseId: 'HANDLE-RECOVERY-V1-E2E-001',
        kind: HandleRecoveryFixtureKind.freshRoot,
        stage: HandleRecoveryFixtureStage.checkpointReady,
        runId: 'fresh-run',
        rawReferences: const <String, String>{
          'admin_identity': 'did:admin',
          'daemon_agent': 'did:daemon',
          'direct_peer': 'did:peer',
          'external_group_member': 'did:member',
          'transport_group': 'did:group',
          'runtime_agent': 'did:runtime',
        },
        expectedCounts: const <String, int>{
          'admin_identities': 1,
          'daemon_agents': 1,
          'direct_peers': 1,
          'external_group_members': 1,
          'transport_groups': 1,
          'runtime_agents': 1,
        },
      );

      expect(checkpoint.references, hasLength(6));
      expect(checkpoint.expectedCounts.values, everyElement(1));
    });

    test('rejects secret, full identity, path, body, and extra fields', () {
      final base = _localCheckpoint().toJson();
      final invalidValues = <String, Object?>{
        'full identity': 'did:awiki:alice',
        'path': '/tmp/private-root',
        'message body': 'message body',
        'credential': '482917',
      };
      for (final entry in invalidValues.entries) {
        final mutated = _copyJson(base);
        (mutated['references']! as Map<String, Object?>)['direct_peer'] =
            entry.value;
        expect(
          () => HandleRecoveryFixtureCheckpoint.fromJson(mutated),
          throwsFormatException,
          reason: entry.key,
        );
      }

      final prohibitedKey = _copyJson(base);
      (prohibitedKey['references']! as Map<String, Object?>)['otp_token'] =
          handleRecoveryFixtureReference('hidden');
      expect(
        () => HandleRecoveryFixtureCheckpoint.fromJson(prohibitedKey),
        throwsFormatException,
      );

      final extraTopLevel = _copyJson(base)..['localPath'] = '/tmp/root';
      expect(
        () => HandleRecoveryFixtureCheckpoint.fromJson(extraTopLevel),
        throwsFormatException,
      );
    });

    test(
      'replay accepts the same fixture and rejects resource replacement',
      () {
        final original = _localCheckpoint();
        _localCheckpoint().requireReplayOf(original);

        final changedRaw = _localRawReferences()
          ..['runtime_agent'] = 'did:runtime-replacement';
        final replacement = _localCheckpoint(rawReferences: changedRaw);
        expect(
          () => replacement.requireReplayOf(original),
          throwsA(
            isA<HandleRecoveryOracleFailure>().having(
              (error) => error.code,
              'code',
              'fixture_replay_created_or_replaced_resource',
            ),
          ),
        );
      },
    );
  });

  group('Handle Recovery shared oracles', () {
    test('exact-one counts raw canonical and semantic matches separately', () {
      final items = <_Item>[
        const _Item(id: 'm-1', semantic: 'run-a'),
        const _Item(id: 'm-2', semantic: 'run-b'),
      ];
      expect(
        requireHandleRecoveryExactOne<_Item>(
          rawItems: items,
          canonicalMatch: (item) => item.id == 'm-1',
          semanticMatch: (item) => item.semantic == 'run-a',
        ),
        same(items.first),
      );
      expect(
        () => requireHandleRecoveryExactOne<_Item>(
          rawItems: <_Item>[items.first, items.first],
          canonicalMatch: (item) => item.id == 'm-1',
          semanticMatch: (item) => item.semantic == 'run-a',
        ),
        _oracleFailure('canonical_exact_one_failed'),
      );
      expect(
        () => requireHandleRecoveryExactOne<_Item>(
          rawItems: items,
          canonicalMatch: (item) => item.id == 'm-1',
          semanticMatch: (item) => item.semantic == 'run-b',
        ),
        _oracleFailure('canonical_semantic_reference_mismatch'),
      );
    });

    test('generation, read, account-state, and stale checks fail closed', () {
      requireHandleRecoveryGenerationAdvance(previous: '41', current: '42');
      expect(
        () => requireHandleRecoveryGenerationAdvance(
          previous: '41',
          current: '43',
        ),
        _oracleFailure('identity_generation_not_advanced_once'),
      );

      requireHandleRecoveryReadWatermark(
        previousThreadSequence: '7',
        currentThreadSequence: '9',
        expectedThreadSequence: '9',
      );
      expect(
        () => requireHandleRecoveryReadWatermark(
          previousThreadSequence: '9',
          currentThreadSequence: '8',
        ),
        _oracleFailure('read_watermark_regressed'),
      );

      requireHandleRecoveryAccountStateVersions(
        previous: const <String, String>{
          'profile': '3',
          'agent_inventory': '8',
          'agent_status': '5',
          'registry': '11',
        },
        current: const <String, String>{
          'profile': '3',
          'agent_inventory': '9',
          'agent_status': '5',
          'registry': '12',
        },
        advancedDomains: const <String>{'agent_inventory', 'registry'},
      );
      expect(
        () => requireHandleRecoveryAccountStateVersions(
          previous: const <String, String>{'profile': '3'},
          current: const <String, String>{'profile': '2'},
          advancedDomains: const <String>{},
        ),
        _oracleFailure('account_state_version_regressed'),
      );

      requireHandleRecoveryStaleGenerationRejected(
        staleGeneration: '41',
        currentGeneration: '42',
        accepted: false,
      );
      expect(
        () => requireHandleRecoveryStaleGenerationRejected(
          staleGeneration: '41',
          currentGeneration: '42',
          accepted: true,
        ),
        _oracleFailure('stale_generation_was_accepted'),
      );
    });
  });

  test(
    'fixture failures retain the owning case and exact failed stage',
    () async {
      final observations = <String>[];
      final progress = HandleRecoveryFixtureProgress();
      await expectLater(
        () => runHandleRecoveryFixtureStage<void>(
          caseId: 'HANDLE-RECOVERY-LOCAL-DIRECT-CONTINUITY-E2E-001',
          progress: progress,
          action: () async {
            progress.advance(HandleRecoveryFixtureStage.identityReady);
            progress.advance(HandleRecoveryFixtureStage.directReady);
            throw StateError('remote detail is not persisted');
          },
          recordFailure:
              ({required caseId, required stage, required code}) async {
                observations.add('$caseId|$stage|$code');
              },
        ),
        throwsStateError,
      );
      expect(observations, <String>[
        'HANDLE-RECOVERY-LOCAL-DIRECT-CONTINUITY-E2E-001|direct_ready|'
            'recovery_fixture_direct_ready_failed',
      ]);
    },
  );

  test('fixture stage tracking cannot move backwards', () {
    final progress = HandleRecoveryFixtureProgress(
      initial: HandleRecoveryFixtureStage.groupReady,
    );
    expect(
      () => progress.advance(HandleRecoveryFixtureStage.directReady),
      _oracleFailure('fixture_stage_regressed'),
    );
  });
}

HandleRecoveryFixtureCheckpoint _localCheckpoint({
  Map<String, String>? rawReferences,
}) {
  return HandleRecoveryFixtureCheckpoint.fromRaw(
    caseId: 'HANDLE-RECOVERY-SETTINGS-CONTINUITY-E2E-001',
    kind: HandleRecoveryFixtureKind.localData,
    stage: HandleRecoveryFixtureStage.checkpointReady,
    runId: 'fixture-run-42',
    rawReferences: rawReferences ?? _localRawReferences(),
    expectedCounts: const <String, int>{
      'admin_identities': 1,
      'daemon_agents': 1,
      'direct_peers': 1,
      'external_group_members': 1,
      'transport_groups': 1,
      'runtime_agents': 1,
      'direct_messages': 2,
      'group_messages': 2,
      'group_members': 2,
      'agent_messages': 2,
      'agent_inventory_items': 2,
      'conversations': 3,
    },
  );
}

Map<String, String> _localRawReferences() => <String, String>{
  'admin_identity': 'did:awiki:admin',
  'daemon_agent': 'did:awiki:daemon',
  'direct_peer': 'did:awiki:peer',
  'external_group_member': 'did:awiki:peer',
  'transport_group': 'did:awiki:group',
  'runtime_agent': 'did:awiki:runtime',
  'direct_conversation': 'direct-conversation',
  'direct_outgoing_message': 'direct-outgoing-message',
  'direct_incoming_message': 'direct-incoming-message',
  'direct_read_message': 'direct-incoming-message',
  'group_conversation': 'group-conversation',
  'group_outgoing_message': 'group-outgoing-message',
  'group_incoming_message': 'group-incoming-message',
  'group_read_message': 'group-incoming-message',
  'agent_conversation': 'agent-conversation',
  'agent_prompt_message': 'agent-prompt-message',
  'agent_reply_message': 'agent-reply-message',
};

Map<String, Object?> _copyJson(Map<String, Object?> value) {
  return (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>();
}

Matcher _oracleFailure(String code) => throwsA(
  isA<HandleRecoveryOracleFailure>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

class _Item {
  const _Item({required this.id, required this.semantic});

  final String id;
  final String semantic;
}
