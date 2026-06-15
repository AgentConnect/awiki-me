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
    final store = AwikiProductLocalStoreSqlite();
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
    final store = AwikiProductLocalStoreSqlite();
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
      final path =
          '${databaseDir.path}/${AwikiProductLocalStoreSqlite.databaseName}';
      final version1 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => _createVersion1Schema(db),
        ),
      );
      await version1.close();

      final store = AwikiProductLocalStoreSqlite();
      await store.saveAgentState(
        LocalAgentState(
          ownerDid: 'did:alice',
          agentDid: 'did:agent',
          valueJson: '{"state":"ready"}',
          updatedAt: DateTime.utc(2026, 6, 15),
        ),
      );

      final states = await store.loadAgentStates(ownerDid: 'did:alice');
      expect(states, hasLength(1));
      expect(states.single.agentDid, 'did:agent');
      expect(states.single.valueJson, '{"state":"ready"}');
    },
  );
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
