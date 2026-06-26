import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../application/models/product_local_models.dart';
import '../../application/product_local_store.dart';
import '../../core/performance_logger.dart';
import '../im_core/awiki_im_core_paths.dart';
import 'sqflite_desktop_init.dart';

class AwikiProductLocalStoreSqlite implements ProductLocalStore {
  AwikiProductLocalStoreSqlite({
    Database? database,
    String? databasePath,
    String? legacyDatabasePath,
  }) : _database = database,
       _databasePath = databasePath,
       _legacyDatabasePath = legacyDatabasePath;

  static const String databaseName = 'awiki_me_product_store.db';
  static const int databaseVersion = 2;

  Database? _database;
  final String? _databasePath;
  final String? _legacyDatabasePath;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }
    AwikiPerformanceLogger.sync(
      'product_store.ensure_sqflite_desktop_initialized',
      ensureSqfliteDesktopInitialized,
    );
    final path = await AwikiPerformanceLogger.async(
      'product_store.resolve_path',
      _resolveDatabasePath,
    );
    try {
      await AwikiPerformanceLogger.async(
        'product_store.migrate_legacy',
        () => _migrateLegacyDatabaseIfNeeded(path),
      );
    } catch (_) {
      // Legacy cache migration is best-effort. A broken old cache must not
      // prevent the current product store from opening at the new app path.
    }
    _database = await AwikiPerformanceLogger.async(
      'product_store.open',
      () => openDatabase(
        path,
        version: databaseVersion,
        onCreate: (db, _) => _createSchema(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createAgentStatesTable(db);
          }
        },
      ),
    );
    return _database!;
  }

  Future<String> _resolveDatabasePath() async {
    final configured = _databasePath?.trim();
    if (configured != null && configured.isNotEmpty) {
      await Directory(p.dirname(configured)).create(recursive: true);
      return configured;
    }
    final e2eRoot = awikiE2eAppStateRoot();
    final base = e2eRoot == null
        ? p.join(
            (await getApplicationSupportDirectory()).path,
            'awiki-me',
            'product',
          )
        : p.join(e2eRoot, 'support', 'awiki-me', 'product');
    await Directory(base).create(recursive: true);
    return p.join(base, databaseName);
  }

  Future<void> _migrateLegacyDatabaseIfNeeded(String targetPath) async {
    final targetFile = File(targetPath);
    if (await targetFile.exists()) {
      return;
    }
    final legacyPath = await _resolveLegacyDatabasePath();
    if (legacyPath == null ||
        p.equals(p.absolute(legacyPath), p.absolute(targetFile.path))) {
      return;
    }
    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) {
      return;
    }
    await targetFile.parent.create(recursive: true);
    await _copyIfExists(legacyPath, targetPath);
    for (final suffix in const <String>['-wal', '-shm', '-journal']) {
      await _copyIfExists('$legacyPath$suffix', '$targetPath$suffix');
    }
  }

  Future<String?> _resolveLegacyDatabasePath() async {
    final configured = _legacyDatabasePath?.trim();
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }
    final legacyBase = await getDatabasesPath();
    return p.join(legacyBase, databaseName);
  }

  static Future<void> _copyIfExists(String from, String to) async {
    final source = File(from);
    if (!await source.exists()) {
      return;
    }
    await source.copy(to);
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
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
                updatedAt: updatedAt,
              ))
          .copyWith(hidden: hidden, updatedAt: updatedAt),
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
    'pinned': overlay.pinned ? 1 : 0,
    'muted': overlay.muted ? 1 : 0,
    'hidden': overlay.hidden ? 1 : 0,
    'custom_title': overlay.customTitle,
    'avatar_seed': overlay.avatarSeed,
    'updated_at': overlay.updatedAt.toUtc().toIso8601String(),
  };
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
