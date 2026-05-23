import 'package:sqflite/sqflite.dart';

import '../../application/models/product_local_models.dart';
import '../../application/product_local_store.dart';

class AwikiProductLocalStoreSqlite implements ProductLocalStore {
  AwikiProductLocalStoreSqlite({Database? database}) : _database = database;

  static const String databaseName = 'awiki_me_product_store.db';
  static const int databaseVersion = 1;

  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }
    final base = await getDatabasesPath();
    _database = await openDatabase(
      '$base/$databaseName',
      version: databaseVersion,
      onCreate: (db, _) => _createSchema(db),
    );
    return _database!;
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
    final rows = ids == null || ids.isEmpty
        ? await (await _db).query(
            'conversation_overlays',
            where: 'owner_did = ?',
            whereArgs: <Object?>[ownerDid],
          )
        : await (await _db).query(
            'conversation_overlays',
            where:
                'owner_did = ? AND thread_id IN (${List.filled(ids.length, '?').join(',')})',
            whereArgs: <Object?>[ownerDid, ...ids],
          );
    return Map<String, ProductConversationOverlay>.fromEntries(
      rows.map((row) {
        final overlay = _overlayFromRow(row);
        return MapEntry(overlay.threadId, overlay);
      }),
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
    final existing = await loadConversationOverlay(
      ownerDid: ownerDid,
      threadId: threadId,
    );
    await upsertConversationOverlay(
      (existing ??
              ProductConversationOverlay(
                ownerDid: ownerDid,
                threadId: threadId,
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

bool _readBool(Object? value) {
  return (int.tryParse(value?.toString() ?? '') ?? 0) == 1;
}

DateTime _readDate(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}
