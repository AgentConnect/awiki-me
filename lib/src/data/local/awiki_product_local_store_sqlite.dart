import 'dart:io';
import 'dart:convert';

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
  static const int databaseVersion = 6;

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
          if (oldVersion < 4) {
            await _createAccountDomainSnapshotTables(db);
          }
          if (oldVersion < 5) {
            await _createDeviceRegistryEpochTables(db);
          }
          if (oldVersion < 6) {
            await _createHandleRecoveryLocatorTable(db);
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
        await _createSchemaUpgradeBackup(database, databasePath: path);
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
    await _createVerifiedBackup(
      db,
      backupPath: backupPath,
      emptyErrorCode: 'canonical_conversation_overlay_backup_empty',
      invalidErrorCode: 'canonical_conversation_overlay_backup_invalid',
    );
  }

  Future<void> _createSchemaUpgradeBackup(
    Database db, {
    required String databasePath,
  }) async {
    final backupDirectory = Directory(
      p.join(p.dirname(databasePath), 'schema-upgrades'),
    );
    await backupDirectory.create(recursive: true);
    final backupPath = p.join(
      backupDirectory.path,
      'awiki_me_product_store.pre-v$databaseVersion.sqlite',
    );
    await _createVerifiedBackup(
      db,
      backupPath: backupPath,
      emptyErrorCode: 'product_store_schema_backup_empty',
      invalidErrorCode: 'product_store_schema_backup_invalid',
    );
  }

  Future<void> _createVerifiedBackup(
    Database db, {
    required String backupPath,
    required String emptyErrorCode,
    required String invalidErrorCode,
  }) async {
    if (await File(backupPath).exists()) {
      await _verifyDatabaseBackup(
        backupPath,
        emptyErrorCode: emptyErrorCode,
        invalidErrorCode: invalidErrorCode,
      );
      return;
    }
    final temporaryPath = '$backupPath.tmp';
    final temporaryFile = File(temporaryPath);
    if (await temporaryFile.exists()) {
      await temporaryFile.delete();
    }
    final escaped = temporaryPath.replaceAll("'", "''");
    await db.execute("VACUUM INTO '$escaped'");
    await _verifyDatabaseBackup(
      temporaryPath,
      emptyErrorCode: emptyErrorCode,
      invalidErrorCode: invalidErrorCode,
    );
    await File(temporaryPath).rename(backupPath);
  }

  Future<void> _verifyDatabaseBackup(
    String path, {
    required String emptyErrorCode,
    required String invalidErrorCode,
  }) async {
    if (await File(path).length() == 0) {
      throw FileSystemException(emptyErrorCode);
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
        throw FileSystemException(invalidErrorCode);
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
    await _createAccountDomainSnapshotTables(db);
    await _createDeviceRegistryEpochTables(db);
    await _createHandleRecoveryLocatorTable(db);
  }

  static Future<void> _createHandleRecoveryLocatorTable(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS handle_recovery_locator (
        local_identity_id TEXT PRIMARY KEY,
        operation_id TEXT NOT NULL,
        full_handle TEXT NOT NULL,
        recovery_id TEXT,
        CHECK (TRIM(local_identity_id) <> ''),
        CHECK (TRIM(operation_id) <> ''),
        CHECK (TRIM(full_handle) <> ''),
        CHECK (recovery_id IS NULL OR TRIM(recovery_id) <> '')
      )
    ''');
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

  static Future<void> _createAccountDomainSnapshotTables(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_domain_sync_state (
        owner_identity_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        domain TEXT NOT NULL,
        domain_version TEXT NOT NULL,
        payload_hash TEXT,
        refreshed_at INTEGER NOT NULL,
        PRIMARY KEY (owner_identity_id, domain),
        CHECK (TRIM(owner_identity_id) <> ''),
        CHECK (TRIM(account_id) <> ''),
        CHECK (refreshed_at >= 0),
        CHECK (
          domain IN (
            'profile',
            'agent_inventory',
            'agent_status',
            'device_registry'
          )
        ),
        CHECK (
          domain_version = '0' OR (
            domain_version NOT GLOB '*[^0-9]*'
            AND SUBSTR(domain_version, 1, 1) BETWEEN '1' AND '9'
          )
        )
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS account_domain_sync_state_account_idx
      ON account_domain_sync_state(account_id, domain)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_agent_inventory_snapshot (
        owner_identity_id TEXT NOT NULL,
        agent_did TEXT NOT NULL,
        inventory_version TEXT NOT NULL,
        active_state TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY (owner_identity_id, agent_did),
        CHECK (TRIM(owner_identity_id) <> ''),
        CHECK (TRIM(agent_did) <> ''),
        CHECK (TRIM(active_state) <> ''),
        CHECK (
          inventory_version = '0' OR (
            inventory_version NOT GLOB '*[^0-9]*'
            AND SUBSTR(inventory_version, 1, 1) BETWEEN '1' AND '9'
          )
        )
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_agent_status_snapshot (
        owner_identity_id TEXT NOT NULL,
        agent_did TEXT NOT NULL,
        agent_status_version TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY (owner_identity_id, agent_did),
        CHECK (TRIM(owner_identity_id) <> ''),
        CHECK (TRIM(agent_did) <> ''),
        CHECK (
          agent_status_version = '0' OR (
            agent_status_version NOT GLOB '*[^0-9]*'
            AND SUBSTR(agent_status_version, 1, 1) BETWEEN '1' AND '9'
          )
        )
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_profile_snapshot (
        owner_identity_id TEXT PRIMARY KEY,
        profile_version TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        CHECK (TRIM(owner_identity_id) <> ''),
        CHECK (
          profile_version = '0' OR (
            profile_version NOT GLOB '*[^0-9]*'
            AND SUBSTR(profile_version, 1, 1) BETWEEN '1' AND '9'
          )
        )
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_device_registry_snapshot (
        owner_identity_id TEXT NOT NULL,
        protocol_device_id TEXT NOT NULL,
        registry_version TEXT NOT NULL,
        auth_generation TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY (owner_identity_id, protocol_device_id),
        CHECK (TRIM(owner_identity_id) <> ''),
        CHECK (TRIM(protocol_device_id) <> ''),
        CHECK (
          registry_version = '0' OR (
            registry_version NOT GLOB '*[^0-9]*'
            AND SUBSTR(registry_version, 1, 1) BETWEEN '1' AND '9'
          )
        ),
        CHECK (
          auth_generation = '0' OR (
            auth_generation NOT GLOB '*[^0-9]*'
            AND SUBSTR(auth_generation, 1, 1) BETWEEN '1' AND '9'
          )
        )
      )
    ''');
  }

  static Future<void> _createDeviceRegistryEpochTables(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_device_registry_epoch (
        owner_identity_id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        current_did TEXT NOT NULL,
        binding_generation TEXT NOT NULL,
        CHECK (TRIM(owner_identity_id) <> ''),
        CHECK (TRIM(account_id) <> ''),
        CHECK (TRIM(current_did) <> ''),
        CHECK (
          binding_generation NOT GLOB '*[^0-9]*'
          AND SUBSTR(binding_generation, 1, 1) BETWEEN '1' AND '9'
        )
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_device_registry_epoch_reset_receipt (
        account_user_id TEXT NOT NULL,
        owner_identity_id TEXT NOT NULL,
        previous_did TEXT NOT NULL,
        current_did TEXT NOT NULL,
        binding_generation TEXT NOT NULL,
        handle TEXT NOT NULL,
        source_kind TEXT NOT NULL,
        source_id TEXT NOT NULL,
        applied_at INTEGER NOT NULL,
        PRIMARY KEY (
          account_user_id,
          owner_identity_id,
          previous_did,
          current_did,
          binding_generation,
          handle,
          source_kind,
          source_id
        ),
        CHECK (TRIM(account_user_id) <> ''),
        CHECK (TRIM(owner_identity_id) <> ''),
        CHECK (TRIM(previous_did) <> ''),
        CHECK (TRIM(current_did) <> ''),
        CHECK (previous_did <> current_did),
        CHECK (TRIM(handle) <> ''),
        CHECK (source_kind IN ('initiator', 'joined_device')),
        CHECK (TRIM(source_id) <> ''),
        CHECK (applied_at >= 0),
        CHECK (
          binding_generation NOT GLOB '*[^0-9]*'
          AND SUBSTR(binding_generation, 1, 1) BETWEEN '1' AND '9'
        )
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_device_registry_epoch_adoption_receipt (
        owner_identity_id TEXT PRIMARY KEY,
        account_user_id TEXT NOT NULL,
        current_did TEXT NOT NULL,
        binding_generation TEXT NOT NULL,
        protocol_device_id TEXT NOT NULL,
        device_auth_generation TEXT NOT NULL,
        provenance_id TEXT NOT NULL,
        adopted_at INTEGER NOT NULL,
        CHECK (TRIM(owner_identity_id) <> ''),
        CHECK (TRIM(account_user_id) <> ''),
        CHECK (TRIM(current_did) <> ''),
        CHECK (TRIM(protocol_device_id) <> ''),
        CHECK (TRIM(provenance_id) <> ''),
        CHECK (adopted_at >= 0),
        CHECK (
          binding_generation NOT GLOB '*[^0-9]*'
          AND SUBSTR(binding_generation, 1, 1) BETWEEN '1' AND '9'
        ),
        CHECK (
          device_auth_generation = '0' OR (
            device_auth_generation NOT GLOB '*[^0-9]*'
            AND SUBSTR(device_auth_generation, 1, 1) BETWEEN '1' AND '9'
          )
        )
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

  @override
  Future<ProductAccountDomainSyncState?> loadDomainSyncState({
    required ProductAccountBinding binding,
    required ProductAccountDomain domain,
  }) async {
    validateProductAccountBinding(binding);
    final db = await _db;
    await _assertAccountBinding(db, binding);
    return _loadDomainState(db, binding, domain);
  }

  @override
  Future<Map<ProductAccountDomain, ProductAccountDomainSyncState>>
  loadDomainSyncStates({required ProductAccountBinding binding}) async {
    validateProductAccountBinding(binding);
    final db = await _db;
    await _assertAccountBinding(db, binding);
    final states = <ProductAccountDomain, ProductAccountDomainSyncState>{};
    for (final domain in ProductAccountDomain.values) {
      final state = await _loadDomainState(db, binding, domain);
      if (state != null) {
        states[domain] = state;
      }
    }
    return states;
  }

  @override
  Future<ProductAgentInventorySnapshot?> loadAgentInventorySnapshot({
    required ProductAccountBinding binding,
    String? legacyOwnerDid,
  }) async {
    validateProductAccountBinding(binding);
    if (legacyOwnerDid == null) {
      return _loadAgentInventorySnapshot(await _db, binding);
    }
    _requireLegacyOwnerDid(legacyOwnerDid);
    return (await _db).transaction((transaction) async {
      final existing = await _loadAgentInventorySnapshot(transaction, binding);
      if (existing != null) {
        return existing;
      }
      final legacyRows = await transaction.query(
        'local_agent_states',
        where: 'owner_did = ?',
        whereArgs: <Object?>[legacyOwnerDid],
        orderBy: 'updated_at DESC',
      );
      final legacyStates = legacyRows
          .map(_agentStateFromRow)
          .toList(growable: false);
      final snapshot = ProductAgentInventorySnapshot(
        binding: binding,
        domainVersion: '0',
        payloadHash: productLegacyAgentSeedPayloadHash,
        refreshedAt: _legacyRefreshedAt(
          legacyStates.map((state) => state.updatedAt),
        ),
        agents: legacyStates.map(
          (state) => ProductAgentInventoryItem(
            agentDid: state.agentDid,
            activeState: _legacyAgentActiveState(state.valueJson),
            payloadJson: state.valueJson,
          ),
        ),
      );
      validateProductAgentInventorySnapshot(snapshot);
      await _replaceAgentInventorySnapshot(transaction, snapshot);
      return snapshot;
    });
  }

  @override
  Future<void> replaceAgentInventorySnapshot(
    ProductAgentInventorySnapshot snapshot,
  ) async {
    validateProductAgentInventorySnapshot(snapshot);
    await (await _db).transaction(
      (transaction) => _replaceAgentInventorySnapshot(transaction, snapshot),
    );
  }

  @override
  Future<ProductAgentStatusSnapshot?> loadAgentStatusSnapshot({
    required ProductAccountBinding binding,
  }) async {
    validateProductAccountBinding(binding);
    final db = await _db;
    await _assertAccountBinding(db, binding);
    final state = await _loadDomainState(
      db,
      binding,
      ProductAccountDomain.agentStatus,
    );
    if (state == null) {
      return null;
    }
    final rows = await db.query(
      'account_agent_status_snapshot',
      where: 'owner_identity_id = ?',
      whereArgs: <Object?>[binding.ownerIdentityId],
      orderBy: 'agent_did ASC',
    );
    _assertRowsUseDomainVersion(
      rows,
      column: 'agent_status_version',
      domainVersion: state.domainVersion,
    );
    final snapshot = ProductAgentStatusSnapshot(
      binding: binding,
      domainVersion: state.domainVersion,
      payloadHash: state.payloadHash,
      refreshedAt: state.refreshedAt,
      statuses: rows.map(
        (row) => ProductAgentStatusItem(
          agentDid: row['agent_did']?.toString() ?? '',
          payloadJson: row['payload_json']?.toString() ?? '',
        ),
      ),
    );
    validateProductAgentStatusSnapshot(snapshot);
    return snapshot;
  }

  @override
  Future<void> replaceAgentStatusSnapshot(
    ProductAgentStatusSnapshot snapshot,
  ) async {
    validateProductAgentStatusSnapshot(snapshot);
    await (await _db).transaction((transaction) async {
      await _assertAccountBinding(transaction, snapshot.binding);
      await _assertNonRegressingDomainVersion(
        transaction,
        snapshot.binding,
        ProductAccountDomain.agentStatus,
        snapshot.domainVersion,
      );
      await transaction.delete(
        'account_agent_status_snapshot',
        where: 'owner_identity_id = ?',
        whereArgs: <Object?>[snapshot.binding.ownerIdentityId],
      );
      for (final status in snapshot.statuses) {
        await transaction
            .insert('account_agent_status_snapshot', <String, Object?>{
              'owner_identity_id': snapshot.binding.ownerIdentityId,
              'agent_did': status.agentDid,
              'agent_status_version': snapshot.domainVersion,
              'payload_json': status.payloadJson,
            });
      }
      await _writeDomainState(transaction, snapshot.syncState);
    });
  }

  @override
  Future<ProductProfileSnapshot?> loadProfileSnapshot({
    required ProductAccountBinding binding,
  }) async {
    validateProductAccountBinding(binding);
    final db = await _db;
    await _assertAccountBinding(db, binding);
    final state = await _loadDomainState(
      db,
      binding,
      ProductAccountDomain.profile,
    );
    if (state == null) {
      return null;
    }
    final rows = await db.query(
      'account_profile_snapshot',
      where: 'owner_identity_id = ?',
      whereArgs: <Object?>[binding.ownerIdentityId],
      limit: 1,
    );
    if (rows.isNotEmpty &&
        rows.single['profile_version']?.toString() != state.domainVersion) {
      throw StateError('product_profile_snapshot_version_mismatch');
    }
    final snapshot = ProductProfileSnapshot(
      binding: binding,
      domainVersion: state.domainVersion,
      payloadHash: state.payloadHash,
      refreshedAt: state.refreshedAt,
      payloadJson: rows.isEmpty
          ? null
          : rows.single['payload_json']?.toString() ?? '',
    );
    validateProductProfileSnapshot(snapshot);
    return snapshot;
  }

  @override
  Future<void> replaceProfileSnapshot(ProductProfileSnapshot snapshot) async {
    validateProductProfileSnapshot(snapshot);
    await (await _db).transaction((transaction) async {
      await _assertAccountBinding(transaction, snapshot.binding);
      await _assertNonRegressingDomainVersion(
        transaction,
        snapshot.binding,
        ProductAccountDomain.profile,
        snapshot.domainVersion,
      );
      await transaction.delete(
        'account_profile_snapshot',
        where: 'owner_identity_id = ?',
        whereArgs: <Object?>[snapshot.binding.ownerIdentityId],
      );
      final payloadJson = snapshot.payloadJson;
      if (payloadJson != null) {
        await transaction.insert('account_profile_snapshot', <String, Object?>{
          'owner_identity_id': snapshot.binding.ownerIdentityId,
          'profile_version': snapshot.domainVersion,
          'payload_json': payloadJson,
        });
      }
      await _writeDomainState(transaction, snapshot.syncState);
    });
  }

  @override
  Future<ProductDeviceRegistrySnapshot?> loadDeviceRegistrySnapshot({
    required ProductAccountBinding binding,
  }) async {
    validateProductAccountBinding(binding);
    final db = await _db;
    await _assertAccountBinding(db, binding);
    final state = await _loadDomainState(
      db,
      binding,
      ProductAccountDomain.deviceRegistry,
    );
    if (state == null) {
      return null;
    }
    final epoch = await _loadDeviceRegistryEpoch(db, binding);
    if (epoch == null) {
      throw const ProductDeviceRegistryEpochMismatchException();
    }
    final rows = await db.query(
      'account_device_registry_snapshot',
      where: 'owner_identity_id = ?',
      whereArgs: <Object?>[binding.ownerIdentityId],
      orderBy: 'protocol_device_id ASC',
    );
    _assertRowsUseDomainVersion(
      rows,
      column: 'registry_version',
      domainVersion: state.domainVersion,
    );
    final snapshot = ProductDeviceRegistrySnapshot(
      binding: binding,
      epoch: epoch,
      domainVersion: state.domainVersion,
      payloadHash: state.payloadHash,
      refreshedAt: state.refreshedAt,
      devices: rows.map(
        (row) => ProductDeviceRegistryItem(
          protocolDeviceId: row['protocol_device_id']?.toString() ?? '',
          authGeneration: row['auth_generation']?.toString() ?? '',
          payloadJson: row['payload_json']?.toString() ?? '',
        ),
      ),
    );
    validateProductDeviceRegistrySnapshot(snapshot);
    return snapshot;
  }

  @override
  Future<ProductDeviceRegistryEpoch?> loadDeviceRegistryEpoch({
    required ProductAccountBinding binding,
  }) async {
    validateProductAccountBinding(binding);
    final db = await _db;
    await _assertAccountBinding(db, binding);
    return _loadDeviceRegistryEpoch(db, binding);
  }

  @override
  Future<ProductDeviceRegistryEpochResetReceipt?>
  loadDeviceRegistryEpochResetReceipt({
    required ProductDeviceRegistryEpochResetAuthorization authorization,
  }) async {
    validateProductDeviceRegistryEpochResetAuthorization(authorization);
    final db = await _db;
    await _assertAccountBinding(db, authorization.reference.binding);
    return _loadDeviceRegistryEpochResetReceipt(db, authorization);
  }

  @override
  Future<ProductDeviceRegistryEpochResetReceipt> applyDeviceRegistryEpochReset(
    ProductDeviceRegistryEpochResetAuthorization authorization,
  ) async {
    validateProductDeviceRegistryEpochResetAuthorization(authorization);
    final reference = authorization.reference;
    return (await _db).transaction((transaction) async {
      await _assertAccountBinding(transaction, reference.binding);
      final existingReceipt = await _loadDeviceRegistryEpochResetReceipt(
        transaction,
        authorization,
      );
      if (existingReceipt != null) {
        return existingReceipt;
      }
      final existingEpoch = await _loadDeviceRegistryEpoch(
        transaction,
        reference.binding,
      );
      final existingRegistryState = await _loadDomainState(
        transaction,
        reference.binding,
        ProductAccountDomain.deviceRegistry,
      );
      if ((existingEpoch == null && existingRegistryState != null) ||
          (existingEpoch != null &&
              (existingEpoch.currentDid != reference.previousDid ||
                  compareProductDecimalVersions(
                        reference.bindingGeneration,
                        existingEpoch.bindingGeneration,
                      ) <=
                      0))) {
        throw const ProductDeviceRegistryEpochMismatchException();
      }
      final appliedAt = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().toUtc().millisecondsSinceEpoch,
        isUtc: true,
      );
      await transaction.insert(
        'account_device_registry_epoch_reset_receipt',
        <String, Object?>{
          'account_user_id': reference.accountUserId,
          'owner_identity_id': reference.ownerIdentityId,
          'previous_did': reference.previousDid,
          'current_did': reference.currentDid,
          'binding_generation': reference.bindingGeneration,
          'handle': authorization.handle,
          'source_kind': productIdentityTransitionSourceKindWireName(
            authorization.sourceKind,
          ),
          'source_id': authorization.sourceId,
          'applied_at': appliedAt.millisecondsSinceEpoch,
        },
      );
      await transaction.delete(
        'account_device_registry_snapshot',
        where: 'owner_identity_id = ?',
        whereArgs: <Object?>[reference.ownerIdentityId],
      );
      await transaction.delete(
        'account_domain_sync_state',
        where: 'owner_identity_id = ? AND domain = ?',
        whereArgs: <Object?>[
          reference.ownerIdentityId,
          ProductAccountDomain.deviceRegistry.storageValue,
        ],
      );
      final epochValues = <String, Object?>{
        'account_id': reference.accountUserId,
        'current_did': reference.currentDid,
        'binding_generation': reference.bindingGeneration,
      };
      if (existingEpoch == null) {
        await transaction.insert(
          'account_device_registry_epoch',
          <String, Object?>{
            'owner_identity_id': reference.ownerIdentityId,
            ...epochValues,
          },
        );
      } else {
        await transaction.update(
          'account_device_registry_epoch',
          epochValues,
          where: 'owner_identity_id = ?',
          whereArgs: <Object?>[reference.ownerIdentityId],
        );
      }
      return ProductDeviceRegistryEpochResetReceipt(
        authorization: authorization,
        appliedAt: appliedAt,
      );
    });
  }

  @override
  Future<LegacyRegistryEpochAdoptionReceipt?>
  loadLegacyRegistryEpochAdoptionReceipt({
    required ProductAccountBinding binding,
  }) async {
    validateProductAccountBinding(binding);
    final db = await _db;
    await _assertAccountBinding(db, binding);
    return _loadLegacyRegistryEpochAdoptionReceipt(db, binding);
  }

  @override
  Future<LegacyRegistryEpochAdoptionReceipt> adoptLegacyDeviceRegistryEpoch(
    LegacyRegistryEpochAdoptionAuthority authority,
  ) async {
    validateLegacyRegistryEpochAdoptionAuthority(authority);
    return (await _db).transaction((transaction) async {
      await _assertAccountBinding(transaction, authority.binding);
      final existingReceipt = await _loadLegacyRegistryEpochAdoptionReceipt(
        transaction,
        authority.binding,
      );
      final existingEpoch = await _loadDeviceRegistryEpoch(
        transaction,
        authority.binding,
      );
      if (existingReceipt != null) {
        if (existingReceipt.authority.matches(authority) &&
            existingEpoch?.matches(authority.epoch) == true) {
          return existingReceipt;
        }
        throw const ProductLegacyRegistryEpochAdoptionMismatchException();
      }
      if (existingEpoch != null) {
        throw const ProductLegacyRegistryEpochAdoptionMismatchException();
      }
      final resetReceiptCount = Sqflite.firstIntValue(
        await transaction.rawQuery(
          'SELECT COUNT(*) FROM account_device_registry_epoch_reset_receipt '
          'WHERE owner_identity_id = ?',
          <Object?>[authority.ownerIdentityId],
        ),
      );
      if (resetReceiptCount != 0) {
        throw const ProductLegacyRegistryEpochAdoptionMismatchException();
      }
      final state = await _loadDomainState(
        transaction,
        authority.binding,
        ProductAccountDomain.deviceRegistry,
      );
      if (state == null) {
        throw const ProductLegacyRegistryEpochAdoptionMismatchException();
      }
      final rows = await transaction.query(
        'account_device_registry_snapshot',
        where:
            'owner_identity_id = ? AND protocol_device_id = ? '
            'AND auth_generation = ? AND registry_version = ?',
        whereArgs: <Object?>[
          authority.ownerIdentityId,
          authority.protocolDeviceId,
          authority.deviceAuthGeneration,
          state.domainVersion,
        ],
      );
      if (rows.length != 1 ||
          !_isActiveRegistryPayload(rows.single['payload_json']?.toString())) {
        throw const ProductLegacyRegistryEpochAdoptionMismatchException();
      }
      final adoptedAt = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().toUtc().millisecondsSinceEpoch,
        isUtc: true,
      );
      await transaction.insert(
        'account_device_registry_epoch_adoption_receipt',
        <String, Object?>{
          'owner_identity_id': authority.ownerIdentityId,
          'account_user_id': authority.accountUserId,
          'current_did': authority.currentDid,
          'binding_generation': authority.bindingGeneration,
          'protocol_device_id': authority.protocolDeviceId,
          'device_auth_generation': authority.deviceAuthGeneration,
          'provenance_id': authority.provenanceId,
          'adopted_at': adoptedAt.millisecondsSinceEpoch,
        },
      );
      await transaction
          .insert('account_device_registry_epoch', <String, Object?>{
            'owner_identity_id': authority.ownerIdentityId,
            'account_id': authority.accountUserId,
            'current_did': authority.currentDid,
            'binding_generation': authority.bindingGeneration,
          });
      return LegacyRegistryEpochAdoptionReceipt(
        authority: authority,
        adoptedAt: adoptedAt,
      );
    });
  }

  @override
  Future<void> replaceDeviceRegistrySnapshot(
    ProductDeviceRegistrySnapshot snapshot,
  ) async {
    validateProductDeviceRegistrySnapshot(snapshot);
    await (await _db).transaction((transaction) async {
      await _assertAccountBinding(transaction, snapshot.binding);
      final existingEpoch = await _loadDeviceRegistryEpoch(
        transaction,
        snapshot.binding,
      );
      if (existingEpoch != null && !existingEpoch.matches(snapshot.epoch)) {
        throw const ProductDeviceRegistryEpochMismatchException();
      }
      if (existingEpoch == null) {
        final existingState = await _loadDomainState(
          transaction,
          snapshot.binding,
          ProductAccountDomain.deviceRegistry,
        );
        if (existingState != null) {
          throw const ProductDeviceRegistryEpochMismatchException();
        }
        await transaction
            .insert('account_device_registry_epoch', <String, Object?>{
              'owner_identity_id': snapshot.binding.ownerIdentityId,
              'account_id': snapshot.binding.accountId,
              'current_did': snapshot.epoch.currentDid,
              'binding_generation': snapshot.epoch.bindingGeneration,
            });
      }
      await _assertNonRegressingDomainVersion(
        transaction,
        snapshot.binding,
        ProductAccountDomain.deviceRegistry,
        snapshot.domainVersion,
      );
      await transaction.delete(
        'account_device_registry_snapshot',
        where: 'owner_identity_id = ?',
        whereArgs: <Object?>[snapshot.binding.ownerIdentityId],
      );
      for (final device in snapshot.devices) {
        await transaction
            .insert('account_device_registry_snapshot', <String, Object?>{
              'owner_identity_id': snapshot.binding.ownerIdentityId,
              'protocol_device_id': device.protocolDeviceId,
              'registry_version': snapshot.domainVersion,
              'auth_generation': device.authGeneration,
              'payload_json': device.payloadJson,
            });
      }
      await _writeDomainState(transaction, snapshot.syncState);
    });
  }

  static Future<ProductDeviceRegistryEpoch?> _loadDeviceRegistryEpoch(
    DatabaseExecutor db,
    ProductAccountBinding binding,
  ) async {
    final rows = await db.query(
      'account_device_registry_epoch',
      where: 'owner_identity_id = ? AND account_id = ?',
      whereArgs: <Object?>[binding.ownerIdentityId, binding.accountId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final epoch = ProductDeviceRegistryEpoch(
      currentDid: rows.single['current_did']?.toString() ?? '',
      bindingGeneration: rows.single['binding_generation']?.toString() ?? '',
    );
    validateProductDeviceRegistryEpoch(epoch);
    return epoch;
  }

  static Future<ProductDeviceRegistryEpochResetReceipt?>
  _loadDeviceRegistryEpochResetReceipt(
    DatabaseExecutor db,
    ProductDeviceRegistryEpochResetAuthorization authorization,
  ) async {
    final reference = authorization.reference;
    final rows = await db.query(
      'account_device_registry_epoch_reset_receipt',
      where:
          'account_user_id = ? AND owner_identity_id = ? '
          'AND previous_did = ? AND current_did = ? '
          'AND binding_generation = ? AND handle = ? '
          'AND source_kind = ? AND source_id = ?',
      whereArgs: <Object?>[
        reference.accountUserId,
        reference.ownerIdentityId,
        reference.previousDid,
        reference.currentDid,
        reference.bindingGeneration,
        authorization.handle,
        productIdentityTransitionSourceKindWireName(authorization.sourceKind),
        authorization.sourceId,
      ],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ProductDeviceRegistryEpochResetReceipt(
      authorization: authorization,
      appliedAt: DateTime.fromMillisecondsSinceEpoch(
        int.parse(rows.single['applied_at'].toString()),
        isUtc: true,
      ),
    );
  }

  static Future<LegacyRegistryEpochAdoptionReceipt?>
  _loadLegacyRegistryEpochAdoptionReceipt(
    DatabaseExecutor db,
    ProductAccountBinding binding,
  ) async {
    final rows = await db.query(
      'account_device_registry_epoch_adoption_receipt',
      where: 'owner_identity_id = ? AND account_user_id = ?',
      whereArgs: <Object?>[binding.ownerIdentityId, binding.accountId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.single;
    final authority = LegacyRegistryEpochAdoptionAuthority(
      ownerIdentityId: row['owner_identity_id']?.toString() ?? '',
      accountUserId: row['account_user_id']?.toString() ?? '',
      currentDid: row['current_did']?.toString() ?? '',
      bindingGeneration: row['binding_generation']?.toString() ?? '',
      protocolDeviceId: row['protocol_device_id']?.toString() ?? '',
      deviceAuthGeneration: row['device_auth_generation']?.toString() ?? '',
      provenanceId: row['provenance_id']?.toString() ?? '',
    );
    validateLegacyRegistryEpochAdoptionAuthority(authority);
    return LegacyRegistryEpochAdoptionReceipt(
      authority: authority,
      adoptedAt: DateTime.fromMillisecondsSinceEpoch(
        int.parse(row['adopted_at'].toString()),
        isUtc: true,
      ),
    );
  }

  static Future<ProductAgentInventorySnapshot?> _loadAgentInventorySnapshot(
    DatabaseExecutor db,
    ProductAccountBinding binding,
  ) async {
    await _assertAccountBinding(db, binding);
    final state = await _loadDomainState(
      db,
      binding,
      ProductAccountDomain.agentInventory,
    );
    if (state == null) {
      return null;
    }
    final rows = await db.query(
      'account_agent_inventory_snapshot',
      where: 'owner_identity_id = ?',
      whereArgs: <Object?>[binding.ownerIdentityId],
      orderBy: 'agent_did ASC',
    );
    _assertRowsUseDomainVersion(
      rows,
      column: 'inventory_version',
      domainVersion: state.domainVersion,
    );
    final snapshot = ProductAgentInventorySnapshot(
      binding: binding,
      domainVersion: state.domainVersion,
      payloadHash: state.payloadHash,
      refreshedAt: state.refreshedAt,
      agents: rows.map(
        (row) => ProductAgentInventoryItem(
          agentDid: row['agent_did']?.toString() ?? '',
          activeState: row['active_state']?.toString() ?? '',
          payloadJson: row['payload_json']?.toString() ?? '',
        ),
      ),
    );
    validateProductAgentInventorySnapshot(snapshot);
    return snapshot;
  }

  static Future<void> _replaceAgentInventorySnapshot(
    DatabaseExecutor db,
    ProductAgentInventorySnapshot snapshot,
  ) async {
    await _assertAccountBinding(db, snapshot.binding);
    await _assertNonRegressingDomainVersion(
      db,
      snapshot.binding,
      ProductAccountDomain.agentInventory,
      snapshot.domainVersion,
    );
    await db.delete(
      'account_agent_inventory_snapshot',
      where: 'owner_identity_id = ?',
      whereArgs: <Object?>[snapshot.binding.ownerIdentityId],
    );
    for (final agent in snapshot.agents) {
      await db.insert('account_agent_inventory_snapshot', <String, Object?>{
        'owner_identity_id': snapshot.binding.ownerIdentityId,
        'agent_did': agent.agentDid,
        'inventory_version': snapshot.domainVersion,
        'active_state': agent.activeState,
        'payload_json': agent.payloadJson,
      });
    }
    await _writeDomainState(db, snapshot.syncState);
  }

  static Future<void> _assertAccountBinding(
    DatabaseExecutor db,
    ProductAccountBinding binding,
  ) async {
    final rows = await db.query(
      'account_domain_sync_state',
      columns: const <String>['account_id'],
      where: 'owner_identity_id = ?',
      whereArgs: <Object?>[binding.ownerIdentityId],
      distinct: true,
    );
    for (final row in rows) {
      if (row['account_id']?.toString() != binding.accountId) {
        throw const ProductAccountBindingMismatchException();
      }
    }
  }

  static Future<ProductAccountDomainSyncState?> _loadDomainState(
    DatabaseExecutor db,
    ProductAccountBinding binding,
    ProductAccountDomain domain,
  ) async {
    final rows = await db.query(
      'account_domain_sync_state',
      where: 'owner_identity_id = ? AND domain = ?',
      whereArgs: <Object?>[binding.ownerIdentityId, domain.storageValue],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.single;
    if (row['account_id']?.toString() != binding.accountId) {
      throw const ProductAccountBindingMismatchException();
    }
    final state = ProductAccountDomainSyncState(
      binding: binding,
      domain: domain,
      domainVersion: row['domain_version']?.toString() ?? '',
      payloadHash: row['payload_hash']?.toString(),
      refreshedAt: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(row['refreshed_at']?.toString() ?? '') ?? -1,
        isUtc: true,
      ),
    );
    if (!isCanonicalProductDecimal(state.domainVersion) ||
        state.refreshedAt.millisecondsSinceEpoch < 0) {
      throw StateError('product_domain_sync_state_invalid');
    }
    return state;
  }

  static Future<void> _assertNonRegressingDomainVersion(
    DatabaseExecutor db,
    ProductAccountBinding binding,
    ProductAccountDomain domain,
    String incomingVersion,
  ) async {
    final existing = await _loadDomainState(db, binding, domain);
    if (existing != null &&
        compareProductDecimalVersions(incomingVersion, existing.domainVersion) <
            0) {
      throw const ProductDomainVersionRegressionException();
    }
  }

  static Future<void> _writeDomainState(
    DatabaseExecutor db,
    ProductAccountDomainSyncState state,
  ) async {
    await db.insert('account_domain_sync_state', <String, Object?>{
      'owner_identity_id': state.binding.ownerIdentityId,
      'account_id': state.binding.accountId,
      'domain': state.domain.storageValue,
      'domain_version': state.domainVersion,
      'payload_hash': state.payloadHash,
      'refreshed_at': state.refreshedAt.toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

void _assertRowsUseDomainVersion(
  List<Map<String, Object?>> rows, {
  required String column,
  required String domainVersion,
}) {
  for (final row in rows) {
    if (row[column]?.toString() != domainVersion) {
      throw StateError('product_snapshot_row_version_mismatch');
    }
  }
}

bool _isActiveRegistryPayload(String? payloadJson) {
  if (payloadJson == null) return false;
  try {
    final value = jsonDecode(payloadJson);
    return value is Map && value['status'] == 'active';
  } on FormatException {
    return false;
  }
}

void _requireLegacyOwnerDid(String value) {
  if (value.isEmpty || value.trim() != value) {
    throw ArgumentError.value(
      value,
      'legacyOwnerDid',
      'must be non-empty and contain no surrounding whitespace',
    );
  }
}

DateTime _legacyRefreshedAt(Iterable<DateTime> values) {
  var latest = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  for (final value in values) {
    final utc = value.toUtc();
    if (utc.isAfter(latest)) {
      latest = utc;
    }
  }
  return latest;
}

String _legacyAgentActiveState(String valueJson) {
  try {
    final value = jsonDecode(valueJson);
    if (value is Map) {
      final activeState = value['active_state']?.toString();
      if (activeState != null &&
          activeState.isNotEmpty &&
          activeState.trim() == activeState) {
        return activeState;
      }
    }
  } on FormatException {
    // Snapshot validation reports malformed legacy payloads before commit.
  }
  return 'legacy_unknown';
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
