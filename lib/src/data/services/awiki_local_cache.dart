import 'package:sqflite/sqflite.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_summary.dart';

class AwikiLocalCache {
  AwikiLocalCache({Database? database}) : _database = database;

  static const String _dbName = 'awiki_me_awiki_cache.db';
  static const int _dbVersion = 4;

  Database? _database;

  Future<Database> get _db async {
    if (_database != null) {
      return _database!;
    }
    final base = await getDatabasesPath();
    _database = await openDatabase(
      '$base/$_dbName',
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            owner_did TEXT NOT NULL,
            thread_id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            last_message_preview TEXT NOT NULL,
            last_message_at TEXT NOT NULL,
            unread_count INTEGER NOT NULL DEFAULT 0,
            is_group INTEGER NOT NULL DEFAULT 0,
            target_did TEXT,
            group_id TEXT,
            avatar_seed TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_conversations_owner_time ON conversations(owner_did, last_message_at)',
        );
        await db.execute('''
          CREATE TABLE messages (
            owner_did TEXT NOT NULL,
            local_id TEXT PRIMARY KEY,
            remote_id TEXT,
            thread_id TEXT NOT NULL,
            sender_did TEXT NOT NULL,
            sender_name TEXT,
            receiver_did TEXT,
            group_id TEXT,
            content TEXT NOT NULL,
            original_type TEXT NOT NULL,
            created_at TEXT NOT NULL,
            is_mine INTEGER NOT NULL DEFAULT 0,
            server_sequence INTEGER,
            is_read INTEGER NOT NULL DEFAULT 0,
            is_encrypted INTEGER NOT NULL DEFAULT 0,
            send_state TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_messages_owner_thread_time ON messages(owner_did, thread_id, created_at)',
        );
        await db.execute('''
          CREATE TABLE groups (
            owner_did TEXT NOT NULL,
            group_id TEXT NOT NULL,
            name TEXT NOT NULL,
            description TEXT NOT NULL,
            member_count INTEGER NOT NULL DEFAULT 0,
            last_message_at TEXT,
            my_role TEXT,
            PRIMARY KEY (owner_did, group_id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_groups_owner_time ON groups(owner_did, last_message_at)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN owner_did TEXT NOT NULL DEFAULT \'\'');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_conversations_owner_time ON conversations(owner_did, last_message_at)',
          );
          await db.execute(
              'ALTER TABLE messages ADD COLUMN owner_did TEXT NOT NULL DEFAULT \'\'');
          await db.execute(
              'ALTER TABLE messages ADD COLUMN is_read INTEGER NOT NULL DEFAULT 0');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_messages_owner_thread_time ON messages(owner_did, thread_id, created_at)',
          );
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS groups (
              owner_did TEXT NOT NULL,
              group_id TEXT NOT NULL,
              name TEXT NOT NULL,
              description TEXT NOT NULL,
              member_count INTEGER NOT NULL DEFAULT 0,
              last_message_at TEXT,
              my_role TEXT,
              PRIMARY KEY (owner_did, group_id)
            )
          ''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_groups_owner_time ON groups(owner_did, last_message_at)',
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE messages ADD COLUMN sender_name TEXT',
          );
        }
      },
    );
    return _database!;
  }

  Future<void> upsertGroups({
    required String ownerDid,
    required List<GroupSummary> groups,
  }) async {
    final db = await _db;
    final batch = db.batch();
    for (final item in groups) {
      batch.insert(
        'groups',
        <String, Object?>{
          'owner_did': ownerDid,
          'group_id': item.groupId,
          'name': item.name,
          'description': item.description,
          'member_count': item.memberCount,
          'last_message_at': item.lastMessageAt?.toIso8601String(),
          'my_role': item.myRole,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<GroupSummary>> loadGroups({required String ownerDid}) async {
    final db = await _db;
    final rows = await db.query(
      'groups',
      where: 'owner_did = ?',
      whereArgs: <Object?>[ownerDid],
      orderBy: 'last_message_at DESC',
    );
    return rows
        .map(
          (row) => GroupSummary(
            groupId: row['group_id']?.toString() ?? '',
            name: row['name']?.toString() ?? 'Unnamed Group',
            description: row['description']?.toString() ?? '',
            memberCount:
                int.tryParse(row['member_count']?.toString() ?? '') ?? 0,
            lastMessageAt:
                DateTime.tryParse(row['last_message_at']?.toString() ?? ''),
            myRole: row['my_role']?.toString(),
          ),
        )
        .toList();
  }

  Future<void> upsertConversations({
    required String ownerDid,
    required List<ConversationSummary> conversations,
  }) async {
    final db = await _db;
    final batch = db.batch();
    for (final item in conversations) {
      batch.insert(
        'conversations',
        <String, Object?>{
          'owner_did': ownerDid,
          'thread_id': item.threadId,
          'display_name': item.displayName,
          'last_message_preview': item.lastMessagePreview,
          'last_message_at': item.lastMessageAt.toIso8601String(),
          'unread_count': item.unreadCount,
          'is_group': item.isGroup ? 1 : 0,
          'target_did': item.targetDid,
          'group_id': item.groupId,
          'avatar_seed': item.avatarSeed,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<ConversationSummary>> loadConversations(
      {required String ownerDid}) async {
    final db = await _db;
    final rows = await db.query(
      'conversations',
      where: 'owner_did = ?',
      whereArgs: <Object?>[ownerDid],
      orderBy: 'last_message_at DESC',
    );
    return rows
        .map(
          (row) => ConversationSummary(
            threadId: row['thread_id']?.toString() ?? '',
            displayName: row['display_name']?.toString() ?? '',
            lastMessagePreview: row['last_message_preview']?.toString() ?? '',
            lastMessageAt:
                DateTime.tryParse(row['last_message_at']?.toString() ?? '') ??
                    DateTime.fromMillisecondsSinceEpoch(0),
            unreadCount:
                int.tryParse(row['unread_count']?.toString() ?? '') ?? 0,
            isGroup:
                (int.tryParse(row['is_group']?.toString() ?? '') ?? 0) == 1,
            targetDid: row['target_did']?.toString(),
            groupId: row['group_id']?.toString(),
            avatarSeed: row['avatar_seed']?.toString(),
          ),
        )
        .toList();
  }

  Future<void> upsertMessages({
    required String ownerDid,
    required String threadId,
    required List<ChatMessage> messages,
  }) async {
    final db = await _db;
    final batch = db.batch();
    for (final item in messages) {
      batch.insert(
        'messages',
        <String, Object?>{
          'owner_did': ownerDid,
          'local_id': item.localId,
          'remote_id': item.remoteId,
          'thread_id': threadId,
          'sender_did': item.senderDid,
          'sender_name': item.senderName,
          'receiver_did': item.receiverDid,
          'group_id': item.groupId,
          'content': item.content,
          'original_type': item.originalType,
          'created_at': item.createdAt.toIso8601String(),
          'is_mine': item.isMine ? 1 : 0,
          'server_sequence': item.serverSequence,
          'is_read': item.isMine ? 1 : 0,
          'is_encrypted': item.isEncrypted ? 1 : 0,
          'send_state': item.sendState.name,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<ChatMessage>> loadMessages({
    required String ownerDid,
    required String threadId,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'messages',
      where: 'owner_did = ? AND thread_id = ?',
      whereArgs: <Object?>[ownerDid, threadId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map(
          (row) => ChatMessage(
            localId: row['local_id']?.toString() ?? '',
            remoteId: row['remote_id']?.toString(),
            threadId: row['thread_id']?.toString() ?? threadId,
            senderDid: row['sender_did']?.toString() ?? '',
            senderName: row['sender_name']?.toString(),
            receiverDid: row['receiver_did']?.toString(),
            groupId: row['group_id']?.toString(),
            content: row['content']?.toString() ?? '',
            originalType: row['original_type']?.toString() ?? 'text',
            createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            isMine: (int.tryParse(row['is_mine']?.toString() ?? '') ?? 0) == 1,
            serverSequence:
                int.tryParse(row['server_sequence']?.toString() ?? ''),
            isEncrypted:
                (int.tryParse(row['is_encrypted']?.toString() ?? '') ?? 0) == 1,
            sendState: _parseSendState(row['send_state']?.toString() ?? 'sent'),
          ),
        )
        .toList();
  }

  Future<void> markThreadRead({
    required String ownerDid,
    required String threadId,
  }) async {
    final db = await _db;
    await db.update(
      'messages',
      <String, Object?>{'is_read': 1},
      where: 'owner_did = ? AND thread_id = ? AND is_mine = 0',
      whereArgs: <Object?>[ownerDid, threadId],
    );
    await db.update(
      'conversations',
      <String, Object?>{'unread_count': 0},
      where: 'owner_did = ? AND thread_id = ?',
      whereArgs: <Object?>[ownerDid, threadId],
    );
  }

  Future<void> deleteThread({
    required String ownerDid,
    required String threadId,
  }) async {
    final db = await _db;
    await db.delete(
      'messages',
      where: 'owner_did = ? AND thread_id = ?',
      whereArgs: <Object?>[ownerDid, threadId],
    );
    await db.delete(
      'conversations',
      where: 'owner_did = ? AND thread_id = ?',
      whereArgs: <Object?>[ownerDid, threadId],
    );
  }

  MessageSendState _parseSendState(String raw) {
    return MessageSendState.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => MessageSendState.sent,
    );
  }
}
