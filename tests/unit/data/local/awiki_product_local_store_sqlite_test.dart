import 'dart:io';

import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });

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
      expect(overlay?.effectiveConversationId, 'direct:bob');
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
      expect(legacy?.effectiveConversationId, 'direct-did:did:bob');
      expect(bobOwner?.customTitle, 'Bob private');

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
    expect(
      await File(
        '${databaseDir.path}/support/awiki-me/product/'
        'canonical-conversation-overlay-upgrade/'
        'awiki_me_product_store.pre-canonical-v2.sqlite',
      ).exists(),
      isTrue,
    );
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

AwikiProductLocalStoreSqlite _store(Directory databaseDir) {
  return AwikiProductLocalStoreSqlite(databasePath: _databasePath(databaseDir));
}

String _databasePath(Directory databaseDir) {
  return '${databaseDir.path}/support/awiki-me/product/${AwikiProductLocalStoreSqlite.databaseName}';
}
