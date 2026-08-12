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
          'runtime_handle': 'runtime.example',
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

      expect(checkpoint.references, hasLength(7));
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

  group('Handle Recovery crash-cut handoff', () {
    test('contains only opaque transition refs, counts, and checkpoint', () {
      final handoff = _crashCutHandoff();
      final encoded = jsonEncode(handoff.toJson());

      for (final raw in <String>[
        'fixture-run-42',
        'did:awiki:old',
        'did:awiki:new',
        'owner-identity',
        'account-user',
        'operation-42',
        'recovery.example',
      ]) {
        expect(encoded, isNot(contains(raw)));
      }
      expect(encoded, isNot(contains('/tmp/')));
      expect(encoded, isNot(contains('message body')));
      handoff.requireRunId('fixture-run-42');
      handoff.requireTransitionReference('current_identity', 'did:awiki:new');

      final restored = HandleRecoveryCrashCutHandoff.fromJson(
        _copyJson(handoff.toJson()),
      );
      expect(restored.fixtureCheckpoint, isNotNull);
      restored.fixtureCheckpoint!.requireReplayOf(_localCheckpoint());
    });

    test('rejects raw identities, missing fields, and run drift', () {
      final base = _copyJson(_crashCutHandoff().toJson());
      final rawIdentity = _copyJson(base);
      (rawIdentity['transitionReferences']!
              as Map<String, Object?>)['current_identity'] =
          'did:awiki:new';
      expect(
        () => HandleRecoveryCrashCutHandoff.fromJson(rawIdentity),
        throwsFormatException,
      );

      final missing = _copyJson(base);
      (missing['transitionReferences']! as Map<String, Object?>).remove(
        'operation',
      );
      expect(
        () => HandleRecoveryCrashCutHandoff.fromJson(missing),
        throwsFormatException,
      );

      final restored = HandleRecoveryCrashCutHandoff.fromJson(base);
      expect(
        () => restored.requireRunId('another-run'),
        _oracleFailure('handoff_run_reference_mismatch'),
      );
    });

    test('base crash-cut case round trips without a business fixture', () {
      final withFixture = _crashCutHandoff();
      final handoff = HandleRecoveryCrashCutHandoff.fromRaw(
        runId: 'fixture-run-42',
        rawTransitionReferences: const <String, String>{
          'owner_identity': 'owner-identity',
          'account': 'account-user',
          'handle': 'recovery.example',
          'previous_identity': 'did:awiki:old',
          'current_identity': 'did:awiki:new',
          'operation': 'operation-42',
          'previous_generation': '41',
          'current_generation': '42',
        },
        expectedCounts: withFixture.expectedCounts,
      );

      final restored = HandleRecoveryCrashCutHandoff.fromJson(
        _copyJson(handoff.toJson()),
      );
      expect(restored.fixtureCheckpoint, isNull);
      restored.requireRunId('fixture-run-42');
    });

    test('App crash-cut writer cannot fall back to legacy raw fields', () {
      final source = File(
        'tests/e2e/flutter/app/handle_recovery_ui_test.dart',
      ).readAsStringSync();
      expect(source, contains('HandleRecoveryCrashCutHandoff.fromRaw('));
      expect(source, isNot(contains('toHandoffFields')));
      for (final legacyField in <String>[
        "'oldDid': oldSession.did",
        "'newDid': reset.currentDid",
        "'ownerIdentityId': oldBinding.ownerIdentityId",
        "'accountId': oldBinding.accountId",
        "'operationId': operationId",
        "'peerDid': peerDid",
        "'directConversationId': directConversationId",
        "'groupDid': groupDid",
        "'daemonDid': daemonDid",
        "'runtimeDid': runtimeDid",
      ]) {
        expect(source, isNot(contains(legacyField)), reason: legacyField);
      }
    });
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

    test(
      'opaque reference resolution rejects missing and duplicate values',
      () {
        final expected = handleRecoveryFixtureReference('m-1');
        final items = <_Item>[
          const _Item(id: 'm-1', semantic: 'run-a'),
          const _Item(id: 'm-2', semantic: 'run-b'),
        ];
        expect(
          requireHandleRecoveryReferenceExactOne<_Item>(
            rawItems: items,
            expectedReference: expected,
            rawReference: (item) => item.id,
            semanticMatch: (item) => item.semantic == 'run-a',
          ),
          same(items.first),
        );
        expect(
          () => requireHandleRecoveryReferenceExactOne<_Item>(
            rawItems: const <_Item>[
              _Item(id: 'm-1', semantic: 'run-a'),
              _Item(id: 'm-1', semantic: 'run-a'),
            ],
            expectedReference: expected,
            rawReference: (item) => item.id,
          ),
          _oracleFailure('fixture_reference_duplicated'),
        );
        expect(
          () => requireHandleRecoveryReferenceExactOne<_Item>(
            rawItems: items,
            expectedReference: handleRecoveryFixtureReference('missing'),
            rawReference: (item) => item.id,
          ),
          _oracleFailure('fixture_reference_not_found'),
        );
      },
    );

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

  test('shared fixture boundaries record only enabled exact stages', () async {
    final observations = <String>[];
    Future<void> recordFailure({
      required String caseId,
      required String stage,
      required String code,
    }) async {
      observations.add('$caseId|$stage|$code');
    }

    await expectLater(
      () => runHandleRecoveryFixtureBoundary<void>(
        record: true,
        caseId: 'HANDLE-RECOVERY-FRESH-AGENT-INVENTORY-E2E-001',
        stage: 'registration_otp',
        action: () => throw StateError('remote detail is not persisted'),
        recordFailure: recordFailure,
      ),
      throwsStateError,
    );
    await expectLater(
      () => runHandleRecoveryFixtureBoundary<void>(
        record: false,
        caseId: 'HANDLE-RECOVERY-V1-E2E-001',
        stage: 'registration_otp',
        action: () => throw StateError('base case remains independently owned'),
        recordFailure: recordFailure,
      ),
      throwsStateError,
    );
    expect(observations, <String>[
      'HANDLE-RECOVERY-FRESH-AGENT-INVENTORY-E2E-001|registration_otp|'
          'recovery_fixture_registration_otp_failed',
    ]);
    await expectLater(
      () => runHandleRecoveryFixtureBoundary<void>(
        record: true,
        caseId: 'HANDLE-RECOVERY-FRESH-AGENT-INVENTORY-E2E-001',
        stage: 'Registration OTP',
        action: () async {},
        recordFailure: recordFailure,
      ),
      throwsFormatException,
    );
  });

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
  'runtime_handle': 'runtime.example',
  'direct_conversation': 'direct-conversation',
  'peer_direct_conversation': 'peer-direct-conversation',
  'direct_outgoing_message': 'direct-outgoing-message',
  'direct_outgoing_semantic': 'direct outgoing message body',
  'direct_incoming_message': 'direct-incoming-message',
  'direct_incoming_semantic': 'direct incoming message body',
  'direct_read_message': 'direct-incoming-message',
  'group_conversation': 'group-conversation',
  'group_outgoing_message': 'group-outgoing-message',
  'group_outgoing_semantic': 'group outgoing message body',
  'group_incoming_message': 'group-incoming-message',
  'group_incoming_semantic': 'group incoming message body',
  'group_read_message': 'group-incoming-message',
  'agent_conversation': 'agent-conversation',
  'agent_prompt_message': 'agent-prompt-message',
  'agent_prompt_semantic': 'agent prompt message body',
  'agent_reply_message': 'agent-reply-message',
  'agent_reply_semantic': 'agent reply message body',
  'conversation_inventory': '["agent","direct","group"]',
  'agent_inventory': '["daemon","runtime"]',
};

HandleRecoveryCrashCutHandoff _crashCutHandoff() {
  return HandleRecoveryCrashCutHandoff.fromRaw(
    runId: 'fixture-run-42',
    rawTransitionReferences: const <String, String>{
      'owner_identity': 'owner-identity',
      'account': 'account-user',
      'handle': 'recovery.example',
      'previous_identity': 'did:awiki:old',
      'current_identity': 'did:awiki:new',
      'operation': 'operation-42',
      'previous_generation': '41',
      'current_generation': '42',
    },
    expectedCounts: const <String, int>{
      'local_identities': 1,
      'pre_reset_registry_devices': 1,
    },
    fixtureCheckpoint: _localCheckpoint(),
  );
}

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
