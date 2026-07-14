import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../application/models/product_local_models.dart';
import '../../application/product_local_store.dart';
import '../../core/performance_logger.dart';
import 'sqflite_desktop_init.dart';

class AwikiProductLocalStoreSqlite implements ProductLocalStore {
  AwikiProductLocalStoreSqlite({
    Database? database,
    required String databasePath,
  }) : _database = database,
       _databasePath = databasePath;

  static const String databaseName = 'awiki_me_product_store.db';
  static const int databaseVersion = 3;

  Database? _database;
  Future<Database>? _databaseOpening;
  final String _databasePath;

  @override
  Future<void> warmUp() async {
    await AwikiPerformanceLogger.async('product_store.warm_up', () async {
      await _db;
    });
  }

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }
    final opening = _databaseOpening;
    if (opening != null) {
      return opening;
    }
    late final Future<Database> operation;
    operation = _openDatabase().whenComplete(() {
      if (identical(_databaseOpening, operation)) {
        _databaseOpening = null;
      }
    });
    _databaseOpening = operation;
    return operation;
  }

  Future<Database> _openDatabase() async {
    AwikiPerformanceLogger.sync(
      'product_store.ensure_sqflite_desktop_initialized',
      ensureSqfliteDesktopInitialized,
    );
    final path = await AwikiPerformanceLogger.async(
      'product_store.resolve_path',
      _resolveDatabasePath,
    );
    await _backupBeforeSchemaUpgradeIfRequired(path);
    _database = await AwikiPerformanceLogger.async(
      'product_store.open_database',
      () => openDatabase(
        path,
        version: databaseVersion,
        onCreate: (db, _) => _createSchema(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createAgentStatesTable(db);
          }
          if (oldVersion < 3) {
            await _upgradeConversationOverlaysToConversationId(db);
          }
        },
      ),
    );
    return _database!;
  }

  Future<void> _backupBeforeSchemaUpgradeIfRequired(String path) async {
    if (!await File(path).exists()) {
      return;
    }
    final database = await openDatabase(path, singleInstance: false);
    try {
      final version = Sqflite.firstIntValue(
        await database.rawQuery('PRAGMA user_version'),
      );
      if (version != null && version > 0 && version < databaseVersion) {
        await _createCanonicalMigrationBackup(database, databasePath: path);
      }
    } finally {
      await database.close();
    }
  }

  Future<String> _resolveDatabasePath() async {
    final configured = _databasePath.trim();
    if (configured.isEmpty) {
      throw const FileSystemException('product_store_path_missing');
    }
    await Directory(p.dirname(configured)).create(recursive: true);
    return configured;
  }

  Future<void> close() async {
    final opening = _databaseOpening;
    if (opening != null) await opening;
    final database = _database;
    _database = null;
    if (database != null) await database.close();
  }

  /// Atomically rewrites App-owned conversation overlays and drafts using the
  /// Core-owned alias projection. A verified SQLite snapshot is created before
  /// the first mutation; each mapping is journaled in the same transaction as
  /// its data changes so startup can safely retry.
  Future<void> migrateCanonicalConversationAliases(
    Iterable<ProductConversationAliasMigration> mappings,
  ) async {
    final normalized = _normalizeAliasMigrations(mappings);
    if (normalized.isEmpty) {
      return;
    }
    final db = await _db;
    final pending = await _pendingAliasMigrations(db, normalized);
    if (pending.isEmpty) {
      return;
    }
    await _createCanonicalMigrationBackup(db);
    await db.transaction((transaction) async {
      await _createCanonicalMigrationJournal(transaction);
      for (final mapping in pending) {
        await _migrateConversationOverlay(transaction, mapping);
        await _migrateMessageDraft(transaction, mapping);
        await transaction.insert(
          'canonical_conversation_overlay_migrations',
          <String, Object?>{
            'owner_did': mapping.ownerDid,
            'legacy_conversation_id': mapping.legacyConversationId,
            'canonical_conversation_id': mapping.canonicalConversationId,
            'completed_at': DateTime.now().toUtc().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<List<ProductConversationAliasMigration>> _pendingAliasMigrations(
    Database db,
    List<ProductConversationAliasMigration> mappings,
  ) async {
    final journalExists =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
            <Object?>['canonical_conversation_overlay_migrations'],
          ),
        ) ==
        1;
    if (!journalExists) {
      return mappings;
    }
    final pending = <ProductConversationAliasMigration>[];
    for (final mapping in mappings) {
      final completed = Sqflite.firstIntValue(
        await db.rawQuery(
          '''SELECT COUNT(*) FROM canonical_conversation_overlay_migrations
WHERE owner_did = ? AND legacy_conversation_id = ?
  AND canonical_conversation_id = ?''',
          <Object?>[
            mapping.ownerDid,
            mapping.legacyConversationId,
            mapping.canonicalConversationId,
          ],
        ),
      );
      if (completed != 1) {
        pending.add(mapping);
      }
    }
    return pending;
  }

  Future<void> _createCanonicalMigrationBackup(
    Database db, {
    String? databasePath,
  }) async {
    final sourcePath = databasePath ?? _databasePath;
    final backupDirectory = Directory(
      p.join(p.dirname(sourcePath), 'canonical-conversation-overlay-upgrade'),
    );
    await backupDirectory.create(recursive: true);
    final backupPath = p.join(
      backupDirectory.path,
      'awiki_me_product_store.pre-canonical-v2.sqlite',
    );
    if (await File(backupPath).exists()) {
      await _verifyCanonicalMigrationBackup(backupPath);
      return;
    }
    final temporaryPath = '$backupPath.tmp';
    final temporaryFile = File(temporaryPath);
    if (await temporaryFile.exists()) {
      await temporaryFile.delete();
    }
    final escaped = temporaryPath.replaceAll("'", "''");
    await db.execute("VACUUM INTO '$escaped'");
    await _verifyCanonicalMigrationBackup(temporaryPath);
    await File(temporaryPath).rename(backupPath);
  }

  Future<void> _verifyCanonicalMigrationBackup(String path) async {
    if (await File(path).length() == 0) {
      throw const FileSystemException(
        'canonical_conversation_overlay_backup_empty',
      );
    }
    final database = await openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
    );
    try {
      final rows = await database.rawQuery('PRAGMA integrity_check');
      final values = rows.length == 1 ? rows.single.values : const <Object?>[];
      final result = values.length == 1
          ? values.single?.toString().trim().toLowerCase()
          : null;
      if (result != 'ok') {
        throw const FileSystemException(
          'canonical_conversation_overlay_backup_invalid',
        );
      }
    } finally {
      await database.close();
    }
  }

  static Future<void> _createCanonicalMigrationJournal(DatabaseExecutor db) =>
      db.execute('''
CREATE TABLE IF NOT EXISTS canonical_conversation_overlay_migrations (
  owner_did TEXT NOT NULL,
  legacy_conversation_id TEXT NOT NULL,
  canonical_conversation_id TEXT NOT NULL,
  completed_at TEXT NOT NULL,
  PRIMARY KEY (owner_did, legacy_conversation_id)
)''');

  static Future<void> _migrateConversationOverlay(
    DatabaseExecutor db,
    ProductConversationAliasMigration mapping,
  ) async {
    final rows = await db.query(
      'conversation_overlays',
      where: 'owner_did = ? AND (thread_id = ? OR conversation_id = ?)',
      whereArgs: <Object?>[
        mapping.ownerDid,
        mapping.legacyConversationId,
        mapping.legacyConversationId,
      ],
    );
    if (rows.isEmpty) {
      return;
    }
    final canonicalRows = await db.query(
      'conversation_overlays',
      where: 'owner_did = ? AND conversation_id = ?',
      whereArgs: <Object?>[mapping.ownerDid, mapping.canonicalConversationId],
    );
    final candidates = <ProductConversationOverlay>[
      ...rows.map(_overlayFromRow),
      ...canonicalRows.map(_overlayFromRow),
    ];
    candidates.sort((left, right) {
      final byTime = right.updatedAt.compareTo(left.updatedAt);
      if (byTime != 0) return byTime;
      final leftCanonical =
          left.conversationId == mapping.canonicalConversationId;
      final rightCanonical =
          right.conversationId == mapping.canonicalConversationId;
      return leftCanonical == rightCanonical ? 0 : (leftCanonical ? -1 : 1);
    });
    final selected = candidates.first.copyWith(
      threadId: mapping.canonicalConversationId,
      conversationId: mapping.canonicalConversationId,
    );
    await db.delete(
      'conversation_overlays',
      where:
          'owner_did = ? AND (thread_id = ? OR conversation_id = ? OR conversation_id = ?)',
      whereArgs: <Object?>[
        mapping.ownerDid,
        mapping.legacyConversationId,
        mapping.legacyConversationId,
        mapping.canonicalConversationId,
      ],
    );
    await db.insert(
      'conversation_overlays',
      _overlayToRow(selected),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> _migrateMessageDraft(
    DatabaseExecutor db,
    ProductConversationAliasMigration mapping,
  ) async {
    final rows = await db.query(
      'message_drafts',
      where: 'owner_did = ? AND thread_id IN (?, ?)',
      whereArgs: <Object?>[
        mapping.ownerDid,
        mapping.legacyConversationId,
        mapping.canonicalConversationId,
      ],
    );
    if (rows.isEmpty) {
      return;
    }
    final drafts = rows.map(_draftFromRow).toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final selected = MessageDraft(
      ownerDid: mapping.ownerDid,
      threadId: mapping.canonicalConversationId,
      draftText: drafts.first.draftText,
      updatedAt: drafts.first.updatedAt,
    );
    await db.delete(
      'message_drafts',
      where: 'owner_did = ? AND thread_id IN (?, ?)',
      whereArgs: <Object?>[
        mapping.ownerDid,
        mapping.legacyConversationId,
        mapping.canonicalConversationId,
      ],
    );
    await db.insert(
      'message_drafts',
      _draftToRow(selected),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE conversation_overlays (
        owner_did TEXT NOT NULL,
        thread_id TEXT NOT NULL,
        conversation_id TEXT,
        pinned INTEGER NOT NULL DEFAULT 0,
        muted INTEGER NOT NULL DEFAULT 0,
        hidden INTEGER NOT NULL DEFAULT 0,
        custom_title TEXT,
        avatar_seed TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (owner_did, thread_id)
      )
    ''');
    await _createConversationOverlayConversationIdIndex(db);
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
    await _createAgentStatesTable(db);
  }

  static Future<void> _createAgentStatesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_agent_states (
        owner_did TEXT NOT NULL,
        agent_did TEXT NOT NULL,
        value_json TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (owner_did, agent_did)
      )
    ''');
  }

  static Future<void> _upgradeConversationOverlaysToConversationId(
    DatabaseExecutor db,
  ) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(conversation_overlays)',
    );
    final hasConversationId = columns.any(
      (column) => column['name'] == 'conversation_id',
    );
    if (!hasConversationId) {
      await db.execute(
        'ALTER TABLE conversation_overlays ADD COLUMN conversation_id TEXT',
      );
    }
    await db.execute('''
      UPDATE conversation_overlays
      SET conversation_id = thread_id
      WHERE conversation_id IS NULL OR TRIM(conversation_id) = ''
    ''');
    await _createConversationOverlayConversationIdIndex(db);
  }

  static Future<void> _createConversationOverlayConversationIdIndex(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS conversation_overlays_owner_conversation_idx
      ON conversation_overlays(owner_did, conversation_id)
    ''');
  }

  @override
  Future<ProductConversationOverlay?> loadConversationOverlay({
    required String ownerDid,
    required String threadId,
  }) async {
    final rows = await (await _db).query(
      'conversation_overlays',
      where: 'owner_did = ? AND thread_id = ?',
      whereArgs: <Object?>[ownerDid, threadId],
      limit: 1,
    );
    return rows.isEmpty ? null : _overlayFromRow(rows.single);
  }

  @override
  Future<ProductConversationOverlay?> loadConversationOverlayByConversationId({
    required String ownerDid,
    required String conversationId,
  }) async {
    final rows = await (await _db).query(
      'conversation_overlays',
      where: 'owner_did = ? AND conversation_id = ?',
      whereArgs: <Object?>[ownerDid, conversationId],
    );
    return _overlaysByConversationId(rows)[conversationId];
  }

  @override
  Future<Map<String, ProductConversationOverlay>> loadConversationOverlays({
    required String ownerDid,
    Iterable<String>? threadIds,
  }) async {
    final ids = threadIds?.toList(growable: false);
    final db = await _db;
    final rows = await AwikiPerformanceLogger.async(
      'product_store.conversation_overlays.query',
      () => ids == null || ids.isEmpty
          ? db.query(
              'conversation_overlays',
              where: 'owner_did = ?',
              whereArgs: <Object?>[ownerDid],
            )
          : db.query(
              'conversation_overlays',
              where:
                  'owner_did = ? AND thread_id IN (${List.filled(ids.length, '?').join(',')})',
              whereArgs: <Object?>[ownerDid, ...ids],
            ),
      fields: <String, Object?>{'keys': ids?.length ?? 0},
    );
    return AwikiPerformanceLogger.sync(
      'product_store.conversation_overlays.decode',
      () => Map<String, ProductConversationOverlay>.fromEntries(
        rows.map((row) {
          final overlay = _overlayFromRow(row);
          return MapEntry(overlay.threadId, overlay);
        }),
      ),
      fields: <String, Object?>{'rows': rows.length},
    );
  }

  @override
  Future<Map<String, ProductConversationOverlay>>
  loadConversationOverlaysByConversationId({
    required String ownerDid,
    Iterable<String>? conversationIds,
  }) async {
    final ids = conversationIds?.toList(growable: false);
    if (ids != null && ids.isEmpty) {
      return const <String, ProductConversationOverlay>{};
    }
    final db = await _db;
    final rows = await AwikiPerformanceLogger.async(
      'product_store.conversation_overlays.query_by_conversation_id',
      () => ids == null
          ? db.query(
              'conversation_overlays',
              where: 'owner_did = ?',
              whereArgs: <Object?>[ownerDid],
            )
          : db.query(
              'conversation_overlays',
              where:
                  'owner_did = ? AND conversation_id IN (${List.filled(ids.length, '?').join(',')})',
              whereArgs: <Object?>[ownerDid, ...ids],
            ),
      fields: <String, Object?>{'keys': ids?.length ?? 0},
    );
    return AwikiPerformanceLogger.sync(
      'product_store.conversation_overlays.decode_by_conversation_id',
      () => _overlaysByConversationId(rows),
      fields: <String, Object?>{'rows': rows.length},
    );
  }

  @override
  Future<void> upsertConversationOverlay(
    ProductConversationOverlay overlay,
  ) async {
    await (await _db).insert(
      'conversation_overlays',
      _overlayToRow(overlay),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> upsertConversationOverlayByConversationId(
    ProductConversationOverlay overlay,
  ) async {
    final conversationId = overlay.conversationId;
    await upsertConversationOverlay(
      overlay.copyWith(
        threadId: conversationId,
        conversationId: conversationId,
      ),
    );
  }

  @override
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    required DateTime updatedAt,
  }) async {
    await setConversationHidden(
      ownerDid: ownerDid,
      conversationKey: threadId,
      hidden: hidden,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> setConversationHidden({
    required String ownerDid,
    required String conversationKey,
    required bool hidden,
    required DateTime updatedAt,
  }) async {
    final existing = await loadConversationOverlay(
      ownerDid: ownerDid,
      threadId: conversationKey,
    );
    await upsertConversationOverlay(
      (existing ??
              ProductConversationOverlay(
                ownerDid: ownerDid,
                threadId: conversationKey,
                conversationId: conversationKey,
                updatedAt: updatedAt,
              ))
          .copyWith(hidden: hidden, updatedAt: updatedAt),
    );
  }

  @override
  Future<void> setConversationHiddenByConversationId({
    required String ownerDid,
    required String conversationId,
    required bool hidden,
    required DateTime updatedAt,
  }) async {
    final existing = await loadConversationOverlayByConversationId(
      ownerDid: ownerDid,
      conversationId: conversationId,
    );
    await upsertConversationOverlayByConversationId(
      (existing ??
              ProductConversationOverlay(
                ownerDid: ownerDid,
                threadId: conversationId,
                conversationId: conversationId,
                updatedAt: updatedAt,
              ))
          .copyWith(
            threadId: conversationId,
            conversationId: conversationId,
            hidden: hidden,
            updatedAt: updatedAt,
          ),
    );
  }

  @override
  Future<void> deleteConversationOverlay({
    required String ownerDid,
    required String threadId,
  }) async {
    await (await _db).delete(
      'conversation_overlays',
      where: 'owner_did = ? AND thread_id = ?',
      whereArgs: <Object?>[ownerDid, threadId],
    );
  }

  @override
  Future<void> deleteConversationOverlayByConversationId({
    required String ownerDid,
    required String conversationId,
  }) async {
    await (await _db).delete(
      'conversation_overlays',
      where: 'owner_did = ? AND conversation_id = ?',
      whereArgs: <Object?>[ownerDid, conversationId],
    );
  }

  @override
  Future<MessageDraft?> loadDraft({
    required String ownerDid,
    required String threadId,
  }) async {
    final rows = await (await _db).query(
      'message_drafts',
      where: 'owner_did = ? AND thread_id = ?',
      whereArgs: <Object?>[ownerDid, threadId],
      limit: 1,
    );
    return rows.isEmpty ? null : _draftFromRow(rows.single);
  }

  @override
  Future<void> saveDraft(MessageDraft draft) async {
    await (await _db).insert(
      'message_drafts',
      _draftToRow(draft),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteDraft({
    required String ownerDid,
    required String threadId,
  }) async {
    await (await _db).delete(
      'message_drafts',
      where: 'owner_did = ? AND thread_id = ?',
      whereArgs: <Object?>[ownerDid, threadId],
    );
  }

  @override
  Future<LocalUiPreference?> loadUiPreference({
    required String ownerDid,
    required String key,
  }) async {
    final rows = await (await _db).query(
      'local_ui_preferences',
      where: 'owner_did = ? AND key = ?',
      whereArgs: <Object?>[ownerDid, key],
      limit: 1,
    );
    return rows.isEmpty ? null : _preferenceFromRow(rows.single);
  }

  @override
  Future<void> saveUiPreference(LocalUiPreference preference) async {
    await (await _db).insert(
      'local_ui_preferences',
      _preferenceToRow(preference),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteUiPreference({
    required String ownerDid,
    required String key,
  }) async {
    await (await _db).delete(
      'local_ui_preferences',
      where: 'owner_did = ? AND key = ?',
      whereArgs: <Object?>[ownerDid, key],
    );
  }

  @override
  Future<List<LocalAgentState>> loadAgentStates({
    required String ownerDid,
  }) async {
    final rows = await (await _db).query(
      'local_agent_states',
      where: 'owner_did = ?',
      whereArgs: <Object?>[ownerDid],
      orderBy: 'updated_at DESC',
    );
    return rows.map(_agentStateFromRow).toList();
  }

  @override
  Future<void> saveAgentState(LocalAgentState state) async {
    await (await _db).insert(
      'local_agent_states',
      _agentStateToRow(state),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteAgentState({
    required String ownerDid,
    required String agentDid,
  }) async {
    await (await _db).delete(
      'local_agent_states',
      where: 'owner_did = ? AND agent_did = ?',
      whereArgs: <Object?>[ownerDid, agentDid],
    );
  }
}

ProductConversationOverlay _overlayFromRow(Map<String, Object?> row) {
  return ProductConversationOverlay(
    ownerDid: row['owner_did']?.toString() ?? '',
    threadId: row['thread_id']?.toString() ?? '',
    conversationId: row['conversation_id']?.toString().trim().isNotEmpty == true
        ? row['conversation_id']!.toString()
        : row['thread_id']?.toString() ?? '',
    pinned: _readBool(row['pinned']),
    muted: _readBool(row['muted']),
    hidden: _readBool(row['hidden']),
    customTitle: row['custom_title']?.toString(),
    avatarSeed: row['avatar_seed']?.toString(),
    updatedAt: _readDate(row['updated_at']),
  );
}

Map<String, Object?> _overlayToRow(ProductConversationOverlay overlay) {
  return <String, Object?>{
    'owner_did': overlay.ownerDid,
    'thread_id': overlay.threadId,
    'conversation_id': overlay.conversationId,
    'pinned': overlay.pinned ? 1 : 0,
    'muted': overlay.muted ? 1 : 0,
    'hidden': overlay.hidden ? 1 : 0,
    'custom_title': overlay.customTitle,
    'avatar_seed': overlay.avatarSeed,
    'updated_at': overlay.updatedAt.toUtc().toIso8601String(),
  };
}

Map<String, ProductConversationOverlay> _overlaysByConversationId(
  List<Map<String, Object?>> rows,
) {
  final overlays = <String, ProductConversationOverlay>{};
  for (final row in rows) {
    final overlay = _overlayFromRow(row);
    final conversationId = overlay.conversationId;
    final existing = overlays[conversationId];
    if (existing == null || _preferConversationOverlay(overlay, existing)) {
      overlays[conversationId] = overlay;
    }
  }
  return overlays;
}

bool _preferConversationOverlay(
  ProductConversationOverlay candidate,
  ProductConversationOverlay existing,
) {
  final candidateIsCanonical =
      candidate.threadId.trim() == candidate.conversationId;
  final existingIsCanonical =
      existing.threadId.trim() == existing.conversationId;
  if (candidateIsCanonical != existingIsCanonical) {
    return candidateIsCanonical;
  }
  return candidate.updatedAt.isAfter(existing.updatedAt);
}

MessageDraft _draftFromRow(Map<String, Object?> row) {
  return MessageDraft(
    ownerDid: row['owner_did']?.toString() ?? '',
    threadId: row['thread_id']?.toString() ?? '',
    draftText: row['draft_text']?.toString() ?? '',
    updatedAt: _readDate(row['updated_at']),
  );
}

Map<String, Object?> _draftToRow(MessageDraft draft) {
  return <String, Object?>{
    'owner_did': draft.ownerDid,
    'thread_id': draft.threadId,
    'draft_text': draft.draftText,
    'updated_at': draft.updatedAt.toUtc().toIso8601String(),
  };
}

LocalUiPreference _preferenceFromRow(Map<String, Object?> row) {
  return LocalUiPreference(
    ownerDid: row['owner_did']?.toString() ?? '',
    key: row['key']?.toString() ?? '',
    valueJson: row['value_json']?.toString() ?? '',
    updatedAt: _readDate(row['updated_at']),
  );
}

Map<String, Object?> _preferenceToRow(LocalUiPreference preference) {
  return <String, Object?>{
    'owner_did': preference.ownerDid,
    'key': preference.key,
    'value_json': preference.valueJson,
    'updated_at': preference.updatedAt.toUtc().toIso8601String(),
  };
}

LocalAgentState _agentStateFromRow(Map<String, Object?> row) {
  return LocalAgentState(
    ownerDid: row['owner_did']?.toString() ?? '',
    agentDid: row['agent_did']?.toString() ?? '',
    valueJson: row['value_json']?.toString() ?? '',
    updatedAt: _readDate(row['updated_at']),
  );
}

Map<String, Object?> _agentStateToRow(LocalAgentState state) {
  return <String, Object?>{
    'owner_did': state.ownerDid,
    'agent_did': state.agentDid,
    'value_json': state.valueJson,
    'updated_at': state.updatedAt.toUtc().toIso8601String(),
  };
}

bool _readBool(Object? value) {
  return (int.tryParse(value?.toString() ?? '') ?? 0) == 1;
}

DateTime _readDate(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

List<ProductConversationAliasMigration> _normalizeAliasMigrations(
  Iterable<ProductConversationAliasMigration> mappings,
) {
  final byOwnerAndAlias = <String, ProductConversationAliasMigration>{};
  for (final mapping in mappings) {
    final ownerDid = mapping.ownerDid.trim();
    final legacyConversationId = mapping.legacyConversationId.trim();
    final canonicalConversationId = mapping.canonicalConversationId.trim();
    if (ownerDid.isEmpty ||
        legacyConversationId.isEmpty ||
        canonicalConversationId.isEmpty ||
        legacyConversationId == canonicalConversationId) {
      continue;
    }
    final normalized = ProductConversationAliasMigration(
      ownerDid: ownerDid,
      legacyConversationId: legacyConversationId,
      canonicalConversationId: canonicalConversationId,
    );
    final key = '$ownerDid\n$legacyConversationId';
    final existing = byOwnerAndAlias[key];
    if (existing != null &&
        existing.canonicalConversationId != canonicalConversationId) {
      throw StateError('conversation_alias_conflict');
    }
    byOwnerAndAlias[key] = normalized;
  }
  final result = byOwnerAndAlias.values.toList(growable: false);
  result.sort((left, right) {
    final byOwner = left.ownerDid.compareTo(right.ownerDid);
    if (byOwner != 0) return byOwner;
    return left.legacyConversationId.compareTo(right.legacyConversationId);
  });
  return result;
}
