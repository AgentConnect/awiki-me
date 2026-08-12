import 'dart:io';

import 'package:awiki_me/src/application/account_state_sync_service.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/ports/account_state_sync_port.dart';
import 'package:awiki_me/src/application/ports/legacy_registry_epoch_adoption_port.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const registryEpoch = ProductDeviceRegistryEpoch(
    currentDid: 'did:wba:awiki.info:users:alice-old',
    bindingGeneration: '7',
  );

  late Directory databaseDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDir = await Directory.systemTemp.createTemp(
      'awiki_product_store_sqlite_test_',
    );
    await databaseFactory.setDatabasesPath(databaseDir.path);
  });

  tearDown(() async {
    if (await databaseDir.exists()) {
      await databaseDir.delete(recursive: true);
    }
  });

  test('persists overlays drafts and preferences by owner', () async {
    final store = _store(databaseDir);
    final now = DateTime.utc(2026, 6, 15, 1, 2, 3);

    await store.upsertConversationOverlay(
      ProductConversationOverlay(
        ownerDid: 'did:alice',
        threadId: 'direct:bob',
        conversationId: 'direct:bob',
        pinned: true,
        muted: true,
        customTitle: 'Bob',
        avatarSeed: 'seed-bob',
        updatedAt: now,
      ),
    );
    await store.upsertConversationOverlay(
      ProductConversationOverlay(
        ownerDid: 'did:bob',
        threadId: 'direct:bob',
        conversationId: 'direct:bob',
        hidden: true,
        customTitle: 'Bob private',
        updatedAt: now,
      ),
    );
    await store.setConversationHidden(
      ownerDid: 'did:alice',
      conversationKey: 'direct:bob',
      hidden: true,
      updatedAt: now.add(const Duration(minutes: 1)),
    );
    await store.saveDraft(
      MessageDraft(
        ownerDid: 'did:alice',
        threadId: 'direct:bob',
        draftText: 'hello bob',
        updatedAt: now,
      ),
    );
    await store.saveUiPreference(
      LocalUiPreference(
        ownerDid: 'did:alice',
        key: 'conversation.sort',
        valueJson: '{"mode":"recent"}',
        updatedAt: now,
      ),
    );

    final overlay = await store.loadConversationOverlay(
      ownerDid: 'did:alice',
      threadId: 'direct:bob',
    );
    final allAliceOverlays = await store.loadConversationOverlays(
      ownerDid: 'did:alice',
    );
    final filteredAliceOverlays = await store.loadConversationOverlays(
      ownerDid: 'did:alice',
      threadIds: const <String>['direct:bob', 'direct:missing'],
    );
    final draft = await store.loadDraft(
      ownerDid: 'did:alice',
      threadId: 'direct:bob',
    );
    final preference = await store.loadUiPreference(
      ownerDid: 'did:alice',
      key: 'conversation.sort',
    );

    expect(overlay?.pinned, isTrue);
    expect(overlay?.muted, isTrue);
    expect(overlay?.hidden, isTrue);
    expect(overlay?.customTitle, 'Bob');
    expect(overlay?.avatarSeed, 'seed-bob');
    expect(allAliceOverlays.keys, contains('direct:bob'));
    expect(filteredAliceOverlays.keys, contains('direct:bob'));
    expect(filteredAliceOverlays.keys, isNot(contains('direct:missing')));
    expect(draft?.draftText, 'hello bob');
    expect(preference?.valueJson, '{"mode":"recent"}');

    final bobOverlay = await store.loadConversationOverlay(
      ownerDid: 'did:bob',
      threadId: 'direct:bob',
    );
    expect(bobOverlay?.customTitle, 'Bob private');
    expect(bobOverlay?.pinned, isFalse);

    await store.deleteConversationOverlay(
      ownerDid: 'did:alice',
      threadId: 'direct:bob',
    );
    await store.deleteDraft(ownerDid: 'did:alice', threadId: 'direct:bob');
    await store.deleteUiPreference(
      ownerDid: 'did:alice',
      key: 'conversation.sort',
    );

    expect(
      await store.loadConversationOverlay(
        ownerDid: 'did:alice',
        threadId: 'direct:bob',
      ),
      isNull,
    );
    expect(
      await store.loadDraft(ownerDid: 'did:alice', threadId: 'direct:bob'),
      isNull,
    );
    expect(
      await store.loadUiPreference(
        ownerDid: 'did:alice',
        key: 'conversation.sort',
      ),
      isNull,
    );
    expect(
      await store.loadConversationOverlay(
        ownerDid: 'did:bob',
        threadId: 'direct:bob',
      ),
      isNotNull,
    );
    await store.close();
  });

  test(
    'deleteOwnerData purges one recovered owner and preserves another',
    () async {
      final store = _store(databaseDir);
      final now = DateTime.utc(2026, 8, 11);
      const aliceBinding = ProductAccountBinding(
        ownerIdentityId: 'owner-alice',
        accountId: 'account-alice',
      );
      const bobBinding = ProductAccountBinding(
        ownerIdentityId: 'owner-bob',
        accountId: 'account-bob',
      );
      const recovery = ProductDeviceRegistryEpochResetAuthorization(
        reference: ProductDeviceRegistryEpochResetReference(
          accountUserId: 'account-alice',
          ownerIdentityId: 'owner-alice',
          previousDid: 'did:wba:awiki.info:users:alice-old',
          currentDid: 'did:wba:awiki.info:users:alice-new',
          bindingGeneration: '2',
        ),
        handle: 'alice.awiki.info',
        sourceKind: ProductIdentityTransitionSourceKind.initiator,
        sourceId: 'recovery-alice',
      );

      await store.upsertConversationOverlay(
        ProductConversationOverlay(
          ownerDid: recovery.reference.previousDid,
          threadId: 'alice-old-thread',
          conversationId: 'alice-old-thread',
          updatedAt: now,
        ),
      );
      await store.upsertConversationOverlay(
        ProductConversationOverlay(
          ownerDid: 'did:wba:awiki.info:users:bob',
          threadId: 'bob-thread',
          conversationId: 'bob-thread',
          updatedAt: now,
        ),
      );
      await store.replaceAgentInventorySnapshot(
        ProductAgentInventorySnapshot(
          binding: aliceBinding,
          domainVersion: '1',
          refreshedAt: now,
          agents: const <ProductAgentInventoryItem>[
            ProductAgentInventoryItem(
              agentDid: 'did:agent:alice',
              activeState: 'active',
              payloadJson: '{"name":"Alice agent"}',
            ),
          ],
        ),
      );
      await store.replaceAgentInventorySnapshot(
        ProductAgentInventorySnapshot(
          binding: bobBinding,
          domainVersion: '1',
          refreshedAt: now,
          agents: const <ProductAgentInventoryItem>[
            ProductAgentInventoryItem(
              agentDid: 'did:agent:bob',
              activeState: 'active',
              payloadJson: '{"name":"Bob agent"}',
            ),
          ],
        ),
      );
      await store.applyDeviceRegistryEpochReset(recovery);

      await store.deleteOwnerData(
        ownerIdentityId: aliceBinding.ownerIdentityId,
        currentDid: recovery.reference.currentDid,
      );

      expect(
        await store.loadConversationOverlay(
          ownerDid: recovery.reference.previousDid,
          threadId: 'alice-old-thread',
        ),
        isNull,
      );
      expect(
        await store.loadAgentInventorySnapshot(binding: aliceBinding),
        isNull,
      );
      expect(
        await store.loadConversationOverlay(
          ownerDid: 'did:wba:awiki.info:users:bob',
          threadId: 'bob-thread',
        ),
        isNotNull,
      );
      expect(
        (await store.loadAgentInventorySnapshot(
          binding: bobBinding,
        ))?.agents.single.agentDid,
        'did:agent:bob',
      );
      await store.close();
    },
  );

  test(
    'retains the legacy Handle Recovery locator table as inert schema',
    () async {
      final store = _store(databaseDir);
      await store.warmUp();

      final database = await databaseFactory.openDatabase(
        _databasePath(databaseDir),
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final columnNames = (await database.rawQuery(
        'PRAGMA table_info(handle_recovery_locator)',
      )).map((column) => column['name']).toSet();
      final rows = await database.query('handle_recovery_locator');
      await database.close();
      expect(columnNames, <Object?>{
        'local_identity_id',
        'operation_id',
        'full_handle',
        'recovery_id',
      });
      expect(rows, isEmpty);
      await store.close();
    },
  );

  test('stores agent states by owner sorted by latest update', () async {
    final store = _store(databaseDir);
    final oldTime = DateTime.utc(2026, 6, 15, 1);
    final newTime = oldTime.add(const Duration(minutes: 5));

    await store.saveAgentState(
      LocalAgentState(
        ownerDid: 'did:alice',
        agentDid: 'did:agent-old',
        valueJson: '{"state":"old"}',
        updatedAt: oldTime,
      ),
    );
    await store.saveAgentState(
      LocalAgentState(
        ownerDid: 'did:alice',
        agentDid: 'did:agent-new',
        valueJson: '{"state":"new"}',
        updatedAt: newTime,
      ),
    );
    await store.saveAgentState(
      LocalAgentState(
        ownerDid: 'did:bob',
        agentDid: 'did:agent-new',
        valueJson: '{"state":"bob"}',
        updatedAt: newTime.add(const Duration(minutes: 1)),
      ),
    );
    await store.saveAgentState(
      LocalAgentState(
        ownerDid: 'did:alice',
        agentDid: 'did:agent-old',
        valueJson: '{"state":"replaced"}',
        updatedAt: newTime.add(const Duration(minutes: 2)),
      ),
    );

    final aliceStates = await store.loadAgentStates(ownerDid: 'did:alice');
    expect(aliceStates.map((state) => state.agentDid), <String>[
      'did:agent-old',
      'did:agent-new',
    ]);
    expect(aliceStates.first.valueJson, '{"state":"replaced"}');

    final bobStates = await store.loadAgentStates(ownerDid: 'did:bob');
    expect(bobStates, hasLength(1));
    expect(bobStates.single.valueJson, '{"state":"bob"}');

    await store.deleteAgentState(
      ownerDid: 'did:alice',
      agentDid: 'did:agent-old',
    );

    final remaining = await store.loadAgentStates(ownerDid: 'did:alice');
    expect(remaining.map((state) => state.agentDid), <String>['did:agent-new']);
  });

  test(
    'upgrades version 1 product store with local agent states table',
    () async {
      final path = _databasePath(databaseDir);
      final version1 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => _createVersion1Schema(db),
        ),
      );
      await version1.insert('conversation_overlays', <String, Object?>{
        'owner_did': 'did:alice',
        'thread_id': 'direct:bob',
        'pinned': 1,
        'muted': 0,
        'hidden': 1,
        'custom_title': 'Bob legacy',
        'avatar_seed': 'seed-legacy',
        'updated_at': DateTime.utc(2026, 6, 14).toIso8601String(),
      });
      await version1.close();

      final store = _store(databaseDir);
      await store.saveAgentState(
        LocalAgentState(
          ownerDid: 'did:alice',
          agentDid: 'did:agent',
          valueJson: '{"state":"ready"}',
          updatedAt: DateTime.utc(2026, 6, 15),
        ),
      );

      final states = await store.loadAgentStates(ownerDid: 'did:alice');
      final overlay = await store.loadConversationOverlayByConversationId(
        ownerDid: 'did:alice',
        conversationId: 'direct:bob',
      );
      expect(states, hasLength(1));
      expect(states.single.agentDid, 'did:agent');
      expect(states.single.valueJson, '{"state":"ready"}');
      expect(overlay?.customTitle, 'Bob legacy');
      expect(overlay?.hidden, isTrue);
      expect(overlay?.conversationId, 'direct:bob');
    },
  );

  test(
    'upgrades version 2 overlays and uses conversation id keyed rows',
    () async {
      final path = _databasePath(databaseDir);
      final version2 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) => _createVersion2Schema(db),
        ),
      );
      await version2.insert('conversation_overlays', <String, Object?>{
        'owner_did': 'did:alice',
        'thread_id': 'direct-did:did:bob',
        'pinned': 1,
        'muted': 1,
        'hidden': 1,
        'custom_title': 'Bob legacy',
        'avatar_seed': 'seed-legacy',
        'updated_at': DateTime.utc(2026, 7, 5, 8).toIso8601String(),
      });
      await version2.insert('conversation_overlays', <String, Object?>{
        'owner_did': 'did:bob',
        'thread_id': 'direct-did:did:bob',
        'pinned': 0,
        'muted': 0,
        'hidden': 0,
        'custom_title': 'Bob private',
        'updated_at': DateTime.utc(2026, 7, 5, 8).toIso8601String(),
      });
      await version2.close();

      final store = _store(databaseDir);
      final legacy = await store.loadConversationOverlayByConversationId(
        ownerDid: 'did:alice',
        conversationId: 'direct-did:did:bob',
      );
      final bobOwner = await store.loadConversationOverlayByConversationId(
        ownerDid: 'did:bob',
        conversationId: 'direct-did:did:bob',
      );

      expect(legacy?.customTitle, 'Bob legacy');
      expect(legacy?.pinned, isTrue);
      expect(legacy?.muted, isTrue);
      expect(legacy?.hidden, isTrue);
      expect(legacy?.conversationId, 'direct-did:did:bob');
      expect(bobOwner?.customTitle, 'Bob private');

      final backup = await databaseFactory.openDatabase(
        _schemaUpgradeBackupPath(databaseDir),
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final backupVersion = (await backup.rawQuery(
        'PRAGMA user_version',
      )).single.values.single;
      final backupColumns = await backup.rawQuery(
        'PRAGMA table_info(conversation_overlays)',
      );
      final backupIntegrity = await backup.rawQuery('PRAGMA integrity_check');
      await backup.close();
      expect(backupVersion, 2);
      expect(
        backupColumns.any((column) => column['name'] == 'conversation_id'),
        isFalse,
      );
      expect(backupIntegrity.single.values.single, 'ok');

      await store.upsertConversationOverlay(
        ProductConversationOverlay(
          ownerDid: 'did:alice',
          threadId: 'direct-handle:bob.awiki.test',
          conversationId: 'dm:peer-scope:v1:bob',
          hidden: true,
          customTitle: 'stale alias',
          updatedAt: DateTime.utc(2026, 7, 5, 10),
        ),
      );
      await store.upsertConversationOverlayByConversationId(
        ProductConversationOverlay(
          ownerDid: 'did:alice',
          threadId: 'legacy-thread',
          conversationId: 'dm:peer-scope:v1:bob',
          pinned: true,
          customTitle: 'Bob canonical',
          avatarSeed: 'seed-canonical',
          updatedAt: DateTime.utc(2026, 7, 5, 9),
        ),
      );

      final canonical = await store.loadConversationOverlayByConversationId(
        ownerDid: 'did:alice',
        conversationId: 'dm:peer-scope:v1:bob',
      );
      final batch = await store.loadConversationOverlaysByConversationId(
        ownerDid: 'did:alice',
        conversationIds: const <String>[
          'dm:peer-scope:v1:bob',
          'direct-did:did:bob',
        ],
      );

      expect(canonical?.threadId, 'dm:peer-scope:v1:bob');
      expect(canonical?.customTitle, 'Bob canonical');
      expect(canonical?.hidden, isFalse);
      expect(batch['dm:peer-scope:v1:bob']?.customTitle, 'Bob canonical');
      expect(batch['direct-did:did:bob']?.customTitle, 'Bob legacy');

      await store.setConversationHiddenByConversationId(
        ownerDid: 'did:alice',
        conversationId: 'dm:peer-scope:v1:bob',
        hidden: true,
        updatedAt: DateTime.utc(2026, 7, 5, 11),
      );
      final hidden = await store.loadConversationOverlayByConversationId(
        ownerDid: 'did:alice',
        conversationId: 'dm:peer-scope:v1:bob',
      );
      expect(hidden?.hidden, isTrue);
      expect(hidden?.pinned, isTrue);
      expect(hidden?.customTitle, 'Bob canonical');
    },
  );

  test('fresh product store creates the complete version 6 schema', () async {
    final store = _store(databaseDir);
    await store.warmUp();
    await store.close();

    final database = await databaseFactory.openDatabase(
      _databasePath(databaseDir),
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    final version = Sqflite.firstIntValue(
      await database.rawQuery('PRAGMA user_version'),
    );
    final tableRows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = tableRows
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .toSet();
    await database.close();

    expect(version, 6);
    expect(
      tableNames,
      containsAll(<String>[
        'account_domain_sync_state',
        'account_agent_inventory_snapshot',
        'account_agent_status_snapshot',
        'account_profile_snapshot',
        'account_device_registry_snapshot',
        'account_device_registry_epoch',
        'account_device_registry_epoch_reset_receipt',
        'account_device_registry_epoch_adoption_receipt',
        'handle_recovery_locator',
      ]),
    );
  });

  test(
    'upgrades version 5 with the exact secret-free Recovery locator table',
    () async {
      final path = _databasePath(databaseDir);
      final version5 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (database, _) async {
            await database.execute(
              'CREATE TABLE legacy_marker (value TEXT NOT NULL)',
            );
            await database.insert('legacy_marker', <String, Object?>{
              'value': 'preserved',
            });
          },
        ),
      );
      await version5.close();

      final store = _store(databaseDir);
      await store.warmUp();
      await store.close();

      final upgraded = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(
        Sqflite.firstIntValue(await upgraded.rawQuery('PRAGMA user_version')),
        6,
      );
      final locatorColumns = (await upgraded.rawQuery(
        'PRAGMA table_info(handle_recovery_locator)',
      )).map((column) => column['name']).toSet();
      expect(locatorColumns, <Object?>{
        'local_identity_id',
        'operation_id',
        'full_handle',
        'recovery_id',
      });
      expect(await upgraded.query('legacy_marker'), <Map<String, Object?>>[
        <String, Object?>{'value': 'preserved'},
      ]);
      await upgraded.close();

      final backup = await databaseFactory.openDatabase(
        _schemaUpgradeBackupPath(databaseDir),
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(
        Sqflite.firstIntValue(await backup.rawQuery('PRAGMA user_version')),
        5,
      );
      expect(
        await backup.rawQuery(
          'SELECT name FROM sqlite_master '
          "WHERE type = 'table' AND name = 'handle_recovery_locator'",
        ),
        isEmpty,
      );
      expect(await backup.query('legacy_marker'), <Map<String, Object?>>[
        <String, Object?>{'value': 'preserved'},
      ]);
      await backup.close();
    },
  );

  test(
    'upgrades a real version 3 store additively and keeps a verified backup',
    () async {
      final path = _databasePath(databaseDir);
      final version3 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) => _createVersion3Schema(db),
        ),
      );
      await version3.insert('local_agent_states', <String, Object?>{
        'owner_did': 'did:wba:awiki.ai:alice:e1_old',
        'agent_did': 'did:wba:awiki.ai:agents:e1_legacy',
        'value_json': '{"active_state":"inactive","name":"Legacy"}',
        'updated_at': DateTime.utc(2026, 7, 27).toIso8601String(),
      });
      await version3.close();

      final store = _store(databaseDir);
      await store.warmUp();
      final legacy = await store.loadAgentStates(
        ownerDid: 'did:wba:awiki.ai:alice:e1_old',
      );
      await store.close();

      expect(legacy, hasLength(1));
      expect(legacy.single.agentDid, contains('legacy'));

      final upgraded = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(
        Sqflite.firstIntValue(await upgraded.rawQuery('PRAGMA user_version')),
        6,
      );
      expect(
        await upgraded.rawQuery(
          'SELECT name FROM sqlite_master '
          "WHERE type = 'table' AND name = 'account_domain_sync_state'",
        ),
        hasLength(1),
      );
      await upgraded.close();

      final backup = await databaseFactory.openDatabase(
        _schemaUpgradeBackupPath(databaseDir),
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(
        Sqflite.firstIntValue(await backup.rawQuery('PRAGMA user_version')),
        3,
      );
      expect(
        await backup.rawQuery(
          'SELECT name FROM sqlite_master '
          "WHERE type = 'table' AND name = 'account_domain_sync_state'",
        ),
        isEmpty,
      );
      expect(
        (await backup.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
      expect(await backup.query('local_agent_states'), hasLength(1));
      await backup.close();
    },
  );

  test(
    'v4 Registry adopts exact ordinary Core authority without resetting domains',
    () async {
      const binding = ProductAccountBinding(
        ownerIdentityId: 'owner-legacy-epoch',
        accountId: 'account-legacy-epoch',
      );
      const authority = LegacyRegistryEpochAdoptionAuthority(
        ownerIdentityId: 'owner-legacy-epoch',
        accountUserId: 'account-legacy-epoch',
        currentDid: 'did:wba:example.test:alice-old',
        bindingGeneration: '7',
        protocolDeviceId: 'old-device',
        deviceAuthGeneration: '4',
        provenanceId: 'sha256:legacy-checkpoint-proof',
      );
      final path = _databasePath(databaseDir);
      final version4 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, _) => _createVersion4Schema(db),
        ),
      );
      await _insertVersion4AccountState(version4, binding);
      await version4.close();

      var store = _store(databaseDir);
      final adoption = _LegacyAdoptionPort(authority);
      final remote = _LegacyUpgradeRemote();
      final service = AccountStateSyncService(
        remote: remote,
        local: store,
        legacyRegistryEpochAdoption: adoption,
      );
      final result = await service.reconcile(
        binding: binding,
        expectedCurrentDid: authority.currentDid,
        expectedIdentityGeneration: authority.bindingGeneration,
        expectedIdentitySelector: 'identity-alice-old',
        expectedProtocolDeviceId: authority.protocolDeviceId,
        expectedDeviceAuthGeneration: authority.deviceAuthGeneration,
        sessionGeneration: 7,
        isSessionCurrent: (_, generation) => generation == 7,
      );

      expect(result.failures, isEmpty);
      expect(adoption.calls, 1);
      expect(remote.manifestCalls, 2);
      expect(remote.registryCalls, 1);
      final registry = await store.loadDeviceRegistrySnapshot(binding: binding);
      expect(registry?.epoch.currentDid, authority.currentDid);
      expect(registry?.epoch.bindingGeneration, '7');
      expect(registry?.domainVersion, '10');
      expect(registry?.devices.single.protocolDeviceId, 'old-device');
      expect(
        (await store.loadProfileSnapshot(binding: binding))?.domainVersion,
        '12',
      );
      expect(
        (await store.loadAgentInventorySnapshot(
          binding: binding,
        ))?.domainVersion,
        '15',
      );
      final firstReceipt = await store.loadLegacyRegistryEpochAdoptionReceipt(
        binding: binding,
      );
      expect(firstReceipt?.authority.provenanceId, authority.provenanceId);
      await store.close();

      store = _store(databaseDir);
      final replayed = await store.adoptLegacyDeviceRegistryEpoch(authority);
      expect(replayed.adoptedAt, firstReceipt?.adoptedAt);
      expect(
        (await store.loadDeviceRegistrySnapshot(
          binding: binding,
        ))?.domainVersion,
        '10',
      );
      final restartRemote = _LegacyUpgradeRemote();
      await AccountStateSyncService(
        remote: restartRemote,
        local: store,
        legacyRegistryEpochAdoption: adoption,
      ).reconcile(
        binding: binding,
        expectedCurrentDid: authority.currentDid,
        expectedIdentityGeneration: authority.bindingGeneration,
        expectedIdentitySelector: 'identity-alice-old',
        expectedProtocolDeviceId: authority.protocolDeviceId,
        expectedDeviceAuthGeneration: authority.deviceAuthGeneration,
        sessionGeneration: 8,
        isSessionCurrent: (_, generation) => generation == 8,
      );
      expect(adoption.calls, 1);

      final recoveryRemote = _LegacyUpgradeRemote(
        currentDid: 'did:wba:example.test:alice-new',
        identityGeneration: '8',
        registryVersion: '1',
      );
      await expectLater(
        AccountStateSyncService(
          remote: recoveryRemote,
          local: store,
          legacyRegistryEpochAdoption: _LegacyAdoptionPort(null),
        ).reconcile(
          binding: binding,
          expectedCurrentDid: 'did:wba:example.test:alice-new',
          expectedIdentityGeneration: '8',
          expectedIdentitySelector: 'identity-alice-new',
          expectedProtocolDeviceId: 'new-device',
          expectedDeviceAuthGeneration: '1',
          sessionGeneration: 9,
          isSessionCurrent: (_, generation) => generation == 9,
        ),
        throwsA(
          isA<AccountStateSyncProtocolException>().having(
            (error) => error.code,
            'code',
            'account_state_registry_epoch_mismatch',
          ),
        ),
      );
      expect(recoveryRemote.manifestCalls, 0);
      expect(
        (await store.loadProfileSnapshot(binding: binding))?.domainVersion,
        '12',
      );
      expect(
        (await store.loadAgentInventorySnapshot(
          binding: binding,
        ))?.domainVersion,
        '15',
      );
      await store.close();
    },
  );

  test(
    'v4 Registry without exact Core authority fails before remote unchanged',
    () async {
      const binding = ProductAccountBinding(
        ownerIdentityId: 'owner-legacy-epoch',
        accountId: 'account-legacy-epoch',
      );
      const oldAuthority = LegacyRegistryEpochAdoptionAuthority(
        ownerIdentityId: 'owner-legacy-epoch',
        accountUserId: 'account-legacy-epoch',
        currentDid: 'did:wba:example.test:alice-old',
        bindingGeneration: '7',
        protocolDeviceId: 'old-device',
        deviceAuthGeneration: '4',
        provenanceId: 'sha256:legacy-checkpoint-proof',
      );
      final version4 = await databaseFactory.openDatabase(
        _databasePath(databaseDir),
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, _) => _createVersion4Schema(db),
        ),
      );
      await _insertVersion4AccountState(version4, binding);
      await version4.close();
      final store = _store(databaseDir);

      for (final scenario
          in <
            ({
              LegacyRegistryEpochAdoptionAuthority? authority,
              String did,
              String generation,
              String deviceId,
              String deviceGeneration,
            })
          >[
            (
              authority: null,
              did: oldAuthority.currentDid,
              generation: oldAuthority.bindingGeneration,
              deviceId: oldAuthority.protocolDeviceId,
              deviceGeneration: oldAuthority.deviceAuthGeneration,
            ),
            (
              authority: oldAuthority,
              did: 'did:wba:example.test:alice-new',
              generation: '8',
              deviceId: 'new-device',
              deviceGeneration: '1',
            ),
          ]) {
        final remote = _LegacyUpgradeRemote(
          currentDid: scenario.did,
          identityGeneration: scenario.generation,
          registryVersion: scenario.generation == '8' ? '1' : '10',
        );
        await expectLater(
          AccountStateSyncService(
            remote: remote,
            local: store,
            legacyRegistryEpochAdoption: _LegacyAdoptionPort(
              scenario.authority,
            ),
          ).reconcile(
            binding: binding,
            expectedCurrentDid: scenario.did,
            expectedIdentityGeneration: scenario.generation,
            expectedIdentitySelector: 'identity-alice',
            expectedProtocolDeviceId: scenario.deviceId,
            expectedDeviceAuthGeneration: scenario.deviceGeneration,
            sessionGeneration: 7,
            isSessionCurrent: (_, generation) => generation == 7,
          ),
          throwsA(
            isA<AccountStateSyncProtocolException>().having(
              (error) => error.code,
              'code',
              'account_state_registry_epoch_adoption_mismatch',
            ),
          ),
        );
        expect(remote.manifestCalls, 0);
      }

      expect(await store.loadDeviceRegistryEpoch(binding: binding), isNull);
      expect(
        await store.loadLegacyRegistryEpochAdoptionReceipt(binding: binding),
        isNull,
      );
      expect(
        (await store.loadProfileSnapshot(binding: binding))?.domainVersion,
        '12',
      );
      expect(
        (await store.loadAgentInventorySnapshot(
          binding: binding,
        ))?.domainVersion,
        '15',
      );
      await store.close();
      final raw = await databaseFactory.openDatabase(
        _databasePath(databaseDir),
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(
        (await raw.query(
          'account_device_registry_snapshot',
        )).single['registry_version'],
        '9',
      );
      await raw.close();
    },
  );

  test(
    'atomically replaces versioned domains and isolates topology from status',
    () async {
      final store = _store(databaseDir);
      const binding = ProductAccountBinding(
        ownerIdentityId: 'owner-identity-1',
        accountId: 'account-1',
      );
      final refreshedAt = DateTime.utc(2026, 7, 28, 8);
      const hugeVersion = '900719925474099312345678901234567890';

      await store.replaceAgentInventorySnapshot(
        ProductAgentInventorySnapshot(
          binding: binding,
          domainVersion: hugeVersion,
          payloadHash: 'inventory-hash',
          refreshedAt: refreshedAt,
          agents: const <ProductAgentInventoryItem>[
            ProductAgentInventoryItem(
              agentDid: 'did:agent:inactive',
              activeState: 'inactive',
              payloadJson: '{"name":"Inactive"}',
            ),
          ],
        ),
      );
      await store.replaceAgentStatusSnapshot(
        ProductAgentStatusSnapshot(
          binding: binding,
          domainVersion: '7',
          refreshedAt: refreshedAt,
          statuses: const <ProductAgentStatusItem>[
            ProductAgentStatusItem(
              agentDid: 'did:agent:inactive',
              payloadJson: '{"runtime":"online"}',
            ),
          ],
        ),
      );

      final inventoryBefore = await store.loadAgentInventorySnapshot(
        binding: binding,
      );
      final statusBefore = await store.loadAgentStatusSnapshot(
        binding: binding,
      );
      expect(inventoryBefore?.domainVersion, hugeVersion);
      expect(inventoryBefore?.agents.single.activeState, 'inactive');
      expect(statusBefore?.statuses, hasLength(1));

      await store.replaceAgentInventorySnapshot(
        ProductAgentInventorySnapshot(
          binding: binding,
          domainVersion: '900719925474099312345678901234567891',
          refreshedAt: refreshedAt.add(const Duration(minutes: 1)),
          agents: const <ProductAgentInventoryItem>[],
        ),
      );
      final emptyInventory = await store.loadAgentInventorySnapshot(
        binding: binding,
      );
      final retainedStatus = await store.loadAgentStatusSnapshot(
        binding: binding,
      );
      expect(emptyInventory?.agents, isEmpty);
      expect(
        emptyInventory?.domainVersion,
        '900719925474099312345678901234567891',
      );
      expect(retainedStatus?.statuses.single.agentDid, 'did:agent:inactive');

      await store.replaceAgentStatusSnapshot(
        ProductAgentStatusSnapshot(
          binding: binding,
          domainVersion: '8',
          refreshedAt: refreshedAt.add(const Duration(minutes: 2)),
          statuses: const <ProductAgentStatusItem>[],
        ),
      );
      expect(
        (await store.loadAgentInventorySnapshot(binding: binding))?.agents,
        isEmpty,
      );
      expect(
        (await store.loadAgentStatusSnapshot(binding: binding))?.domainVersion,
        '8',
      );

      await store.replaceProfileSnapshot(
        ProductProfileSnapshot(
          binding: binding,
          domainVersion: '12',
          refreshedAt: refreshedAt,
          payloadJson: '{"display_name":"Alice"}',
        ),
      );
      await store.replaceProfileSnapshot(
        ProductProfileSnapshot(
          binding: binding,
          domainVersion: '13',
          refreshedAt: refreshedAt.add(const Duration(minutes: 3)),
        ),
      );
      final emptyProfile = await store.loadProfileSnapshot(binding: binding);
      expect(emptyProfile?.domainVersion, '13');
      expect(emptyProfile?.payloadJson, isNull);

      await store.replaceDeviceRegistrySnapshot(
        ProductDeviceRegistrySnapshot(
          binding: binding,
          epoch: registryEpoch,
          domainVersion: '21',
          refreshedAt: refreshedAt,
          devices: const <ProductDeviceRegistryItem>[
            ProductDeviceRegistryItem(
              protocolDeviceId: 'protocol-device-1',
              authGeneration: '184467440737095516160',
              payloadJson: '{"state":"active"}',
            ),
          ],
        ),
      );
      await store.replaceDeviceRegistrySnapshot(
        ProductDeviceRegistrySnapshot(
          binding: binding,
          epoch: registryEpoch,
          domainVersion: '22',
          refreshedAt: refreshedAt.add(const Duration(minutes: 4)),
          devices: const <ProductDeviceRegistryItem>[],
        ),
      );
      final emptyRegistry = await store.loadDeviceRegistrySnapshot(
        binding: binding,
      );
      expect(emptyRegistry?.domainVersion, '22');
      expect(emptyRegistry?.devices, isEmpty);

      await store.close();
    },
  );

  test(
    'Registry epoch reset is durable idempotent and isolated after reopen',
    () async {
      const binding = ProductAccountBinding(
        ownerIdentityId: 'owner-identity-recovery',
        accountId: 'account-recovery',
      );
      const nextEpoch = ProductDeviceRegistryEpoch(
        currentDid: 'did:wba:awiki.info:users:alice-new',
        bindingGeneration: '8',
      );
      const reset = ProductDeviceRegistryEpochResetReference(
        accountUserId: 'account-recovery',
        ownerIdentityId: 'owner-identity-recovery',
        previousDid: 'did:wba:awiki.info:users:alice-old',
        currentDid: 'did:wba:awiki.info:users:alice-new',
        bindingGeneration: '8',
      );
      const authorization = ProductDeviceRegistryEpochResetAuthorization(
        reference: reset,
        handle: 'alice.awiki.info',
        sourceKind: ProductIdentityTransitionSourceKind.joinedDevice,
        sourceId: 'join-session-1',
      );
      final now = DateTime.utc(2026, 8, 3);
      var store = _store(databaseDir);
      await store.replaceProfileSnapshot(
        ProductProfileSnapshot(
          binding: binding,
          domainVersion: '12',
          refreshedAt: now,
          payloadJson: '{"display_name":"Alice"}',
        ),
      );
      await store.replaceAgentInventorySnapshot(
        ProductAgentInventorySnapshot(
          binding: binding,
          domainVersion: '15',
          refreshedAt: now,
          agents: const <ProductAgentInventoryItem>[],
        ),
      );
      await store.replaceDeviceRegistrySnapshot(
        ProductDeviceRegistrySnapshot(
          binding: binding,
          epoch: registryEpoch,
          domainVersion: '9',
          refreshedAt: now,
          devices: const <ProductDeviceRegistryItem>[
            ProductDeviceRegistryItem(
              protocolDeviceId: 'old-device',
              authGeneration: '4',
              payloadJson: '{"status":"active"}',
            ),
          ],
        ),
      );

      await expectLater(
        store.replaceDeviceRegistrySnapshot(
          ProductDeviceRegistrySnapshot(
            binding: binding,
            epoch: nextEpoch,
            domainVersion: '1',
            refreshedAt: now,
            devices: const <ProductDeviceRegistryItem>[],
          ),
        ),
        throwsA(isA<ProductDeviceRegistryEpochMismatchException>()),
      );
      for (final invalidSourceId in <String>[
        'join session',
        'join\u0000session',
        List<String>.filled(129, 'j').join(),
      ]) {
        await expectLater(
          store.applyDeviceRegistryEpochReset(
            ProductDeviceRegistryEpochResetAuthorization(
              reference: reset,
              handle: 'alice.awiki.info',
              sourceKind: ProductIdentityTransitionSourceKind.joinedDevice,
              sourceId: invalidSourceId,
            ),
          ),
          throwsArgumentError,
        );
      }
      await store.close();

      store = _store(databaseDir);
      expect(
        await store.loadDeviceRegistryEpochResetReceipt(
          authorization: authorization,
        ),
        isNull,
      );
      final retainedBeforeReset = await store.loadDeviceRegistrySnapshot(
        binding: binding,
      );
      expect(retainedBeforeReset?.epoch, isNotNull);
      expect(retainedBeforeReset?.domainVersion, '9');
      expect(
        retainedBeforeReset?.devices.single.protocolDeviceId,
        'old-device',
      );

      final firstReceipt = await store.applyDeviceRegistryEpochReset(
        authorization,
      );
      await store.close();

      store = _store(databaseDir);
      final durableReceipt = await store.loadDeviceRegistryEpochResetReceipt(
        authorization: authorization,
      );
      expect(durableReceipt?.appliedAt, firstReceipt.appliedAt);
      expect(await store.loadDeviceRegistrySnapshot(binding: binding), isNull);
      expect(
        (await store.loadProfileSnapshot(binding: binding))?.domainVersion,
        '12',
      );
      expect(
        (await store.loadAgentInventorySnapshot(
          binding: binding,
        ))?.domainVersion,
        '15',
      );

      await store.replaceDeviceRegistrySnapshot(
        ProductDeviceRegistrySnapshot(
          binding: binding,
          epoch: nextEpoch,
          domainVersion: '1',
          refreshedAt: now,
          devices: const <ProductDeviceRegistryItem>[
            ProductDeviceRegistryItem(
              protocolDeviceId: 'new-device',
              authGeneration: '1',
              payloadJson: '{"status":"active"}',
            ),
          ],
        ),
      );
      final replayedReceipt = await store.applyDeviceRegistryEpochReset(
        authorization,
      );
      expect(replayedReceipt.appliedAt, firstReceipt.appliedAt);
      expect(
        (await store.loadDeviceRegistrySnapshot(
          binding: binding,
        ))?.devices.single.protocolDeviceId,
        'new-device',
      );
      await store.close();
    },
  );

  test(
    'mid-transaction failure preserves inventory rows and version',
    () async {
      const binding = ProductAccountBinding(
        ownerIdentityId: 'owner-identity-atomic',
        accountId: 'account-atomic',
      );
      final store = _store(databaseDir);
      await store.replaceAgentInventorySnapshot(
        ProductAgentInventorySnapshot(
          binding: binding,
          domainVersion: '1',
          refreshedAt: DateTime.utc(2026, 7, 28, 9),
          agents: const <ProductAgentInventoryItem>[
            ProductAgentInventoryItem(
              agentDid: 'did:agent:original',
              activeState: 'active',
              payloadJson: '{"name":"Original"}',
            ),
          ],
        ),
      );
      await store.close();

      final database = await databaseFactory.openDatabase(
        _databasePath(databaseDir),
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await database.execute('''
      CREATE TRIGGER fail_inventory_insert
      BEFORE INSERT ON account_agent_inventory_snapshot
      WHEN NEW.agent_did = 'did:agent:explode'
      BEGIN
        SELECT RAISE(ABORT, 'injected_inventory_failure');
      END
    ''');
      final failingStore = AwikiProductLocalStoreSqlite(
        database: database,
        databasePath: _databasePath(databaseDir),
      );

      await expectLater(
        failingStore.replaceAgentInventorySnapshot(
          ProductAgentInventorySnapshot(
            binding: binding,
            domainVersion: '2',
            refreshedAt: DateTime.utc(2026, 7, 28, 10),
            agents: const <ProductAgentInventoryItem>[
              ProductAgentInventoryItem(
                agentDid: 'did:agent:explode',
                activeState: 'active',
                payloadJson: '{"name":"Explode"}',
              ),
            ],
          ),
        ),
        throwsA(anything),
      );

      final retained = await failingStore.loadAgentInventorySnapshot(
        binding: binding,
      );
      expect(retained?.domainVersion, '1');
      expect(retained?.agents.single.agentDid, 'did:agent:original');
      await failingStore.close();
    },
  );

  test(
    'copy-on-read requires an explicit binding and rejects account mismatch',
    () async {
      final store = _store(databaseDir);
      const legacyOwnerDid = 'did:wba:awiki.ai:alice:e1_old';
      const binding = ProductAccountBinding(
        ownerIdentityId: 'owner-identity-copy',
        accountId: 'account-copy',
      );
      await store.saveAgentState(
        LocalAgentState(
          ownerDid: legacyOwnerDid,
          agentDid: 'did:agent:legacy',
          valueJson: '{"active_state":"inactive","name":"Legacy"}',
          updatedAt: DateTime.utc(2026, 7, 28, 7),
        ),
      );

      expect(await store.loadAgentInventorySnapshot(binding: binding), isNull);
      final copied = await store.loadAgentInventorySnapshot(
        binding: binding,
        legacyOwnerDid: legacyOwnerDid,
      );
      expect(copied?.domainVersion, '0');
      expect(copied?.payloadHash, productLegacyAgentSeedPayloadHash);
      expect(copied?.agents.single.agentDid, 'did:agent:legacy');
      expect(copied?.agents.single.activeState, 'inactive');
      expect(
        await store.loadAgentStates(ownerDid: legacyOwnerDid),
        hasLength(1),
      );

      const mismatch = ProductAccountBinding(
        ownerIdentityId: 'owner-identity-copy',
        accountId: 'account-other',
      );
      await expectLater(
        store.loadAgentInventorySnapshot(binding: mismatch),
        throwsA(isA<ProductAccountBindingMismatchException>()),
      );
      await expectLater(
        store.replaceProfileSnapshot(
          ProductProfileSnapshot(
            binding: mismatch,
            domainVersion: '1',
            refreshedAt: DateTime.utc(2026, 7, 28, 8),
            payloadJson: '{"display_name":"Wrong"}',
          ),
        ),
        throwsA(isA<ProductAccountBindingMismatchException>()),
      );
      expect(await store.loadProfileSnapshot(binding: binding), isNull);
      await store.close();
    },
  );

  test('configured scope path never imports a legacy product store', () async {
    final legacyPath =
        '${databaseDir.path}/legacy/${AwikiProductLocalStoreSqlite.databaseName}';
    final targetPath =
        '${databaseDir.path}/support/awiki-me/product/${AwikiProductLocalStoreSqlite.databaseName}';
    await Directory('${databaseDir.path}/legacy').create(recursive: true);
    final legacyStore = AwikiProductLocalStoreSqlite(databasePath: legacyPath);
    await legacyStore.saveAgentState(
      LocalAgentState(
        ownerDid: 'did:alice',
        agentDid: 'did:agent',
        valueJson: '{"state":"legacy"}',
        updatedAt: DateTime.utc(2026, 6, 16),
      ),
    );
    await legacyStore.close();

    final store = AwikiProductLocalStoreSqlite(databasePath: targetPath);
    final states = await store.loadAgentStates(ownerDid: 'did:alice');
    await store.saveAgentState(
      LocalAgentState(
        ownerDid: 'did:alice',
        agentDid: 'did:agent-2',
        valueJson: '{"state":"new"}',
        updatedAt: DateTime.utc(2026, 6, 17),
      ),
    );
    expect(states, isEmpty);
    expect(await File(targetPath).exists(), isTrue);
    final targetRows = await AwikiProductLocalStoreSqlite(
      databasePath: targetPath,
    ).loadAgentStates(ownerDid: 'did:alice');
    expect(targetRows.map((state) => state.agentDid), <String>['did:agent-2']);
  });

  test(
    'warmUp opens the database once and keeps later reads available',
    () async {
      final store = _store(databaseDir);

      await Future.wait(<Future<void>>[store.warmUp(), store.warmUp()]);
      await store.upsertConversationOverlay(
        ProductConversationOverlay(
          ownerDid: 'did:alice',
          threadId: 'dm:alice:bob',
          conversationId: 'dm:alice:bob',
          customTitle: 'Bob',
          updatedAt: DateTime.utc(2026, 6, 27),
        ),
      );

      final overlays = await store.loadConversationOverlays(
        ownerDid: 'did:alice',
        threadIds: const <String>['dm:alice:bob'],
      );

      expect(overlays['dm:alice:bob']?.customTitle, 'Bob');
    },
  );

  test('canonical alias migration is backed up and idempotent', () async {
    final store = _store(databaseDir);
    const legacyId = 'direct-did:did:bob';
    const canonicalId = 'dm:peer-scope:v1:bob';
    await store.upsertConversationOverlay(
      ProductConversationOverlay(
        ownerDid: 'did:alice',
        threadId: legacyId,
        conversationId: legacyId,
        customTitle: 'latest legacy title',
        hidden: true,
        updatedAt: DateTime.utc(2026, 7, 14, 2),
      ),
    );
    await store.upsertConversationOverlayByConversationId(
      ProductConversationOverlay(
        ownerDid: 'did:alice',
        threadId: canonicalId,
        conversationId: canonicalId,
        customTitle: 'older canonical title',
        updatedAt: DateTime.utc(2026, 7, 14, 1),
      ),
    );
    await store.saveDraft(
      MessageDraft(
        ownerDid: 'did:alice',
        threadId: legacyId,
        draftText: 'migrated draft',
        updatedAt: DateTime.utc(2026, 7, 14, 3),
      ),
    );

    const mapping = ProductConversationAliasMigration(
      ownerDid: 'did:alice',
      legacyConversationId: legacyId,
      canonicalConversationId: canonicalId,
    );
    await store.migrateCanonicalConversationAliases(const [mapping]);
    await store.migrateCanonicalConversationAliases(const [mapping]);

    expect(
      await store.loadConversationOverlay(
        ownerDid: 'did:alice',
        threadId: legacyId,
      ),
      isNull,
    );
    final overlay = await store.loadConversationOverlayByConversationId(
      ownerDid: 'did:alice',
      conversationId: canonicalId,
    );
    expect(overlay?.threadId, canonicalId);
    expect(overlay?.customTitle, 'latest legacy title');
    expect(overlay?.hidden, isTrue);
    expect(
      await store.loadDraft(ownerDid: 'did:alice', threadId: legacyId),
      isNull,
    );
    expect(
      (await store.loadDraft(
        ownerDid: 'did:alice',
        threadId: canonicalId,
      ))?.draftText,
      'migrated draft',
    );
    expect(await File(_canonicalBackupPath(databaseDir)).exists(), isTrue);
  });
}

Future<void> _createVersion1Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE conversation_overlays (
      owner_did TEXT NOT NULL,
      thread_id TEXT NOT NULL,
      pinned INTEGER NOT NULL DEFAULT 0,
      muted INTEGER NOT NULL DEFAULT 0,
      hidden INTEGER NOT NULL DEFAULT 0,
      custom_title TEXT,
      avatar_seed TEXT,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (owner_did, thread_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE message_drafts (
      owner_did TEXT NOT NULL,
      thread_id TEXT NOT NULL,
      draft_text TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (owner_did, thread_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE local_ui_preferences (
      owner_did TEXT NOT NULL,
      key TEXT NOT NULL,
      value_json TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (owner_did, key)
    )
  ''');
}

Future<void> _createVersion2Schema(DatabaseExecutor db) async {
  await _createVersion1Schema(db);
  await db.execute('''
    CREATE TABLE local_agent_states (
      owner_did TEXT NOT NULL,
      agent_did TEXT NOT NULL,
      value_json TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (owner_did, agent_did)
    )
  ''');
}

Future<void> _createVersion3Schema(DatabaseExecutor db) async {
  await _createVersion2Schema(db);
  await db.execute(
    'ALTER TABLE conversation_overlays ADD COLUMN conversation_id TEXT',
  );
  await db.execute('''
    UPDATE conversation_overlays
    SET conversation_id = thread_id
    WHERE conversation_id IS NULL OR TRIM(conversation_id) = ''
  ''');
  await db.execute('''
    CREATE INDEX conversation_overlays_owner_conversation_idx
    ON conversation_overlays(owner_did, conversation_id)
  ''');
}

Future<void> _createVersion4Schema(DatabaseExecutor db) async {
  await _createVersion3Schema(db);
  await db.execute('''
    CREATE TABLE account_domain_sync_state (
      owner_identity_id TEXT NOT NULL,
      account_id TEXT NOT NULL,
      domain TEXT NOT NULL,
      domain_version TEXT NOT NULL,
      payload_hash TEXT,
      refreshed_at INTEGER NOT NULL,
      PRIMARY KEY (owner_identity_id, domain)
    )
  ''');
  await db.execute('''
    CREATE TABLE account_agent_inventory_snapshot (
      owner_identity_id TEXT NOT NULL,
      agent_did TEXT NOT NULL,
      inventory_version TEXT NOT NULL,
      active_state TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      PRIMARY KEY (owner_identity_id, agent_did)
    )
  ''');
  await db.execute('''
    CREATE TABLE account_agent_status_snapshot (
      owner_identity_id TEXT NOT NULL,
      agent_did TEXT NOT NULL,
      agent_status_version TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      PRIMARY KEY (owner_identity_id, agent_did)
    )
  ''');
  await db.execute('''
    CREATE TABLE account_profile_snapshot (
      owner_identity_id TEXT PRIMARY KEY,
      profile_version TEXT NOT NULL,
      payload_json TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE account_device_registry_snapshot (
      owner_identity_id TEXT NOT NULL,
      protocol_device_id TEXT NOT NULL,
      registry_version TEXT NOT NULL,
      auth_generation TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      PRIMARY KEY (owner_identity_id, protocol_device_id)
    )
  ''');
}

Future<void> _insertVersion4AccountState(
  DatabaseExecutor db,
  ProductAccountBinding binding,
) async {
  final refreshedAt = DateTime.utc(2026, 8, 3).millisecondsSinceEpoch;
  for (final entry in <(String, String)>[
    ('profile', '12'),
    ('agent_inventory', '15'),
    ('device_registry', '9'),
  ]) {
    await db.insert('account_domain_sync_state', <String, Object?>{
      'owner_identity_id': binding.ownerIdentityId,
      'account_id': binding.accountId,
      'domain': entry.$1,
      'domain_version': entry.$2,
      'refreshed_at': refreshedAt,
    });
  }
  await db.insert('account_profile_snapshot', <String, Object?>{
    'owner_identity_id': binding.ownerIdentityId,
    'profile_version': '12',
    'payload_json': '{"display_name":"Alice"}',
  });
  await db.insert('account_agent_inventory_snapshot', <String, Object?>{
    'owner_identity_id': binding.ownerIdentityId,
    'agent_did': 'did:wba:example.test:agents:assistant',
    'inventory_version': '15',
    'active_state': 'active',
    'payload_json': '{"name":"Assistant"}',
  });
  await db.insert('account_device_registry_snapshot', <String, Object?>{
    'owner_identity_id': binding.ownerIdentityId,
    'protocol_device_id': 'old-device',
    'registry_version': '9',
    'auth_generation': '4',
    'payload_json':
        '{"device_id":"old-device",'
        '"signing_key_id":"did:key:signing",'
        '"e2ee_key_id":"did:key:e2ee",'
        '"status":"active","role":"admin",'
        '"management_ready":true,"auth_generation":"4"}',
  });
}

class _LegacyAdoptionPort implements LegacyRegistryEpochAdoptionPort {
  _LegacyAdoptionPort(this.authority);

  final LegacyRegistryEpochAdoptionAuthority? authority;
  int calls = 0;

  @override
  Future<LegacyRegistryEpochAdoptionAuthority?>
  legacyRegistryEpochAdoptionAuthority(String identitySelector) async {
    calls += 1;
    return authority;
  }
}

class _LegacyUpgradeRemote implements AccountStateSyncPort {
  _LegacyUpgradeRemote({
    this.currentDid = 'did:wba:example.test:alice-old',
    this.identityGeneration = '7',
    this.registryVersion = '10',
  });

  final String currentDid;
  final String identityGeneration;
  final String registryVersion;
  int manifestCalls = 0;
  int registryCalls = 0;

  @override
  Future<AccountStateManifest> loadManifest() async {
    manifestCalls += 1;
    return AccountStateManifest(
      accountId: 'account-legacy-epoch',
      currentDid: currentDid,
      identityGeneration: identityGeneration,
      versions: <ProductAccountDomain, String>{
        ProductAccountDomain.profile: '12',
        ProductAccountDomain.agentInventory: '15',
        ProductAccountDomain.agentStatus: '0',
        ProductAccountDomain.deviceRegistry: registryVersion,
      },
      serverTime: DateTime.utc(2026, 8, 3),
    );
  }

  @override
  Future<AccountStateAgentInventorySnapshot> loadAgentInventory() {
    throw StateError('inventory_should_not_reload');
  }

  @override
  Future<AccountStateAgentStatusSnapshot> loadAgentStatus() async {
    return AccountStateAgentStatusSnapshot(
      accountId: 'account-legacy-epoch',
      agentStatusVersion: '0',
      statuses: const <AccountStateAgentStatusEntry>[],
    );
  }

  @override
  Future<AccountStateProfileSnapshot> loadProfile() {
    throw StateError('profile_should_not_reload');
  }

  @override
  Future<AccountStateDeviceRegistrySnapshot> loadDeviceRegistry() async {
    registryCalls += 1;
    return AccountStateDeviceRegistrySnapshot(
      did: currentDid,
      registryVersion: registryVersion,
      devices: const <AccountStateDeviceRegistryEntry>[
        AccountStateDeviceRegistryEntry(
          protocolDeviceId: 'old-device',
          signingKeyId: 'did:key:signing',
          e2eeKeyId: 'did:key:e2ee',
          status: 'active',
          role: 'admin',
          managementReady: true,
          authGeneration: '4',
        ),
      ],
    );
  }
}

AwikiProductLocalStoreSqlite _store(Directory databaseDir) {
  return AwikiProductLocalStoreSqlite(databasePath: _databasePath(databaseDir));
}

String _databasePath(Directory databaseDir) {
  return '${databaseDir.path}/support/awiki-me/product/${AwikiProductLocalStoreSqlite.databaseName}';
}

String _canonicalBackupPath(Directory databaseDir) {
  return '${databaseDir.path}/support/awiki-me/product/'
      'canonical-conversation-overlay-upgrade/'
      'awiki_me_product_store.pre-canonical-v2.sqlite';
}

String _schemaUpgradeBackupPath(Directory databaseDir) {
  return '${databaseDir.path}/support/awiki-me/product/schema-upgrades/'
      'awiki_me_product_store.pre-v6.sqlite';
}
