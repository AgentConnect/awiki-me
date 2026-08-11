import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'models/product_local_models.dart';
import 'product_local_store.dart';

typedef AgentMessageNativeIdDeriver = int Function(String fullDigest);

/// Stable, secret-free owner/account partition for Agent-message presentation.
///
/// The account ID is hashed before it becomes part of the Product store key.
/// Authentication generations deliberately do not participate: receipts and
/// receipt state must survive an ordinary credential refresh for the same owner
/// and account.
final class AgentMessagePresentationOwnerScope {
  AgentMessagePresentationOwnerScope({
    required String ownerIdentityId,
    required String accountId,
  }) : ownerIdentityId = _required(ownerIdentityId),
       accountHash = _hash(_required(accountId)) {
    ownerHash = _hash('${this.ownerIdentityId}\u0000$accountHash');
  }

  final String ownerIdentityId;
  final String accountHash;
  late final String ownerHash;

  String get storageOwnerKey => ownerHash;

  static String _required(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized != value) {
      throw ArgumentError.value(value, 'value', 'owner scope is invalid');
    }
    return normalized;
  }
}

/// Owner/account-scoped local preference and receipt owner for Agent messages.
///
/// No body, DID, conversation ID, raw event ID, or payload is persisted.
/// Every ledger read/modify/write is serialized, and an unreadable ledger
/// fails closed instead of being replaced with an empty one.
final class AgentMessagePresentationStore {
  AgentMessagePresentationStore(
    this._store, {
    AgentMessageNativeIdDeriver? nativeIdDeriver,
    int maxReceipts = 4096,
  }) : assert(maxReceipts > 0),
       _nativeIdDeriver = nativeIdDeriver ?? _defaultNativeId,
       _maxReceipts = maxReceipts;

  static const _receiptKey = 'agent_message_presentation_receipts.v1';
  static const _ledgerVersion = 1;
  static const _retention = Duration(days: 7);

  final ProductLocalStore _store;
  final AgentMessageNativeIdDeriver _nativeIdDeriver;
  final int _maxReceipts;
  Future<void> _operationTail = Future<void>.value();

  /// Durably claims an event before a native cue/submit.
  ///
  /// A native-ID collision between different full digests is returned as a
  /// closed result; the colliding event is never persisted or submitted.
  Future<AgentMessagePresentationClaim> claim({
    required AgentMessagePresentationOwnerScope owner,
    required String eventId,
    required String senderDid,
    required DateTime now,
  }) => _serialize(() async {
    var receipts = await _loadReceipts(owner: owner, now: now);
    final eventHash = _hash(_requiredEventId(eventId));
    final senderHash = _hash(_requiredSenderDid(senderDid));
    final fullDigest = _hash('${owner.ownerHash}\u0000$eventHash');
    final nativeId = _nativeIdDeriver(fullDigest);
    if (nativeId < 0 || nativeId > 0x7fffffff) {
      throw StateError('agent-message native ID derivation is unavailable');
    }
    for (final receipt in receipts) {
      if (receipt.fullDigest == fullDigest) {
        if (receipt.senderHash != senderHash) {
          throw StateError(
            'agent-message presentation event binding is unavailable',
          );
        }
        return AgentMessagePresentationClaim.existing(receipt);
      }
      if (receipt.nativeId == nativeId) {
        return const AgentMessagePresentationClaim.collision();
      }
    }
    if (receipts.length >= _maxReceipts) {
      receipts = _makeRoomForClaim(receipts);
      if (receipts.length >= _maxReceipts) {
        throw StateError(
          'agent-message presentation ledger capacity is unavailable',
        );
      }
    }
    final receipt = AgentMessagePresentationReceipt(
      ownerHash: owner.ownerHash,
      eventHash: eventHash,
      senderHash: senderHash,
      fullDigest: fullDigest,
      nativeId: nativeId,
      disposition: AgentMessageReceiptDisposition.claimed,
      at: now.toUtc(),
    );
    await _saveReceipts(
      owner: owner,
      receipts: <AgentMessagePresentationReceipt>[...receipts, receipt],
      now: now,
    );
    return AgentMessagePresentationClaim.claimed(receipt);
  });

  /// Moves a claim to one terminal disposition exactly once.
  ///
  /// Repeating the same terminal disposition is idempotent. Any attempt to
  /// rewrite one terminal outcome to another fails closed.
  Future<void> markDisposition({
    required AgentMessagePresentationOwnerScope owner,
    required String eventId,
    required AgentMessageReceiptDisposition disposition,
    required DateTime now,
  }) {
    if (disposition == AgentMessageReceiptDisposition.claimed) {
      throw ArgumentError.value(disposition, 'disposition');
    }
    return _serialize(() async {
      final eventHash = _hash(_requiredEventId(eventId));
      final fullDigest = _hash('${owner.ownerHash}\u0000$eventHash');
      final receipts = await _loadReceipts(owner: owner, now: now);
      final index = receipts.indexWhere(
        (receipt) => receipt.fullDigest == fullDigest,
      );
      if (index < 0) {
        throw StateError('agent-message presentation claim is unavailable');
      }
      final current = receipts[index];
      if (current.disposition == disposition) {
        return;
      }
      if (current.isTerminal) {
        throw StateError('agent-message presentation disposition is terminal');
      }
      final updated = <AgentMessagePresentationReceipt>[...receipts];
      updated[index] = current.copyWith(
        disposition: disposition,
        at: now.toUtc(),
      );
      await _saveReceipts(owner: owner, receipts: updated, now: now);
    });
  }

  Future<AgentMessageUrgentPresentationCounts> recentUrgentPresentationCounts({
    required AgentMessagePresentationOwnerScope owner,
    required String senderDid,
    required DateTime since,
    required DateTime now,
  }) => _serialize(() async {
    final normalizedSince = since.toUtc();
    final normalizedNow = now.toUtc();
    if (normalizedSince.isAfter(normalizedNow)) {
      throw ArgumentError.value(since, 'since');
    }
    final senderHash = _hash(_requiredSenderDid(senderDid));
    final receipts = await _loadReceipts(owner: owner, now: normalizedNow);
    var senderCount = 0;
    var accountCount = 0;
    for (final receipt in receipts) {
      if (receipt.disposition != AgentMessageReceiptDisposition.presentedApp ||
          receipt.at.isBefore(normalizedSince)) {
        continue;
      }
      accountCount += 1;
      if (receipt.senderHash == senderHash) {
        senderCount += 1;
      }
    }
    return AgentMessageUrgentPresentationCounts(
      senderCount: senderCount,
      accountCount: accountCount,
    );
  });

  Future<List<AgentMessagePresentationReceipt>> _loadReceipts({
    required AgentMessagePresentationOwnerScope owner,
    required DateTime now,
  }) async {
    final stored = await _store.loadUiPreference(
      ownerDid: owner.storageOwnerKey,
      key: _receiptKey,
    );
    if (stored == null) return const <AgentMessagePresentationReceipt>[];
    try {
      final decoded = jsonDecode(stored.valueJson);
      if (decoded is! Map<String, Object?> ||
          decoded.length != 3 ||
          decoded['version'] != _ledgerVersion ||
          decoded['owner_hash'] != owner.ownerHash ||
          decoded['receipts'] is! List<Object?>) {
        throw const FormatException();
      }
      final receipts = <AgentMessagePresentationReceipt>[];
      final fullDigests = <String>{};
      final nativeIds = <int>{};
      for (final raw in decoded['receipts']! as List<Object?>) {
        if (raw is! Map<String, Object?>) {
          throw const FormatException();
        }
        final receipt = AgentMessagePresentationReceipt.fromJson(raw);
        if (receipt.ownerHash != owner.ownerHash ||
            receipt.fullDigest !=
                _hash('${receipt.ownerHash}\u0000${receipt.eventHash}') ||
            !fullDigests.add(receipt.fullDigest) ||
            !nativeIds.add(receipt.nativeId)) {
          throw const FormatException();
        }
        if (!receipt.isTerminal ||
            now.toUtc().difference(receipt.at) <= _retention) {
          receipts.add(receipt);
        }
      }
      return _boundedReceipts(receipts);
    } on Object {
      throw StateError('agent-message presentation ledger is unavailable');
    }
  }

  Future<void> _saveReceipts({
    required AgentMessagePresentationOwnerScope owner,
    required List<AgentMessagePresentationReceipt> receipts,
    required DateTime now,
  }) => _store.saveUiPreference(
    LocalUiPreference(
      ownerDid: owner.storageOwnerKey,
      key: _receiptKey,
      valueJson: jsonEncode(<String, Object?>{
        'version': _ledgerVersion,
        'owner_hash': owner.ownerHash,
        'receipts': _boundedReceipts(
          receipts,
        ).map((receipt) => receipt.toJson()).toList(),
      }),
      updatedAt: now.toUtc(),
    ),
  );

  Future<T> _serialize<T>(Future<T> Function() operation) async {
    final previous = _operationTail;
    final release = Completer<void>();
    _operationTail = release.future;
    await previous.catchError((Object _) {});
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }

  List<AgentMessagePresentationReceipt> _boundedReceipts(
    List<AgentMessagePresentationReceipt> receipts,
  ) {
    final nonterminal = receipts
        .where((receipt) => !receipt.isTerminal)
        .toList();
    if (nonterminal.length > _maxReceipts) {
      throw StateError(
        'agent-message presentation ledger capacity is unavailable',
      );
    }
    final terminal = receipts.where((receipt) => receipt.isTerminal).toList()
      ..sort((left, right) => left.at.compareTo(right.at));
    final terminalBudget = _maxReceipts - nonterminal.length;
    return <AgentMessagePresentationReceipt>[
      ...nonterminal,
      ...terminal.skip(
        terminal.length > terminalBudget ? terminal.length - terminalBudget : 0,
      ),
    ];
  }

  List<AgentMessagePresentationReceipt> _makeRoomForClaim(
    List<AgentMessagePresentationReceipt> receipts,
  ) {
    final terminal = receipts.where((receipt) => receipt.isTerminal).toList()
      ..sort((left, right) => left.at.compareTo(right.at));
    if (terminal.isEmpty) return receipts;
    final remove = terminal.first.fullDigest;
    return receipts.where((receipt) => receipt.fullDigest != remove).toList();
  }

  static int _defaultNativeId(String fullDigest) =>
      int.parse(fullDigest.substring(0, 8), radix: 16) & 0x7fffffff;

  static String _requiredEventId(String value) {
    if (value.isEmpty || value.trim() != value) {
      throw ArgumentError.value(value, 'eventId');
    }
    return value;
  }

  static String _requiredSenderDid(String value) {
    if (!value.startsWith('did:') ||
        value.trim() != value ||
        value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      throw ArgumentError.value(value, 'senderDid');
    }
    return value;
  }
}

enum AgentMessageReceiptDisposition {
  claimed,
  suppressedForeground,
  suppressedMuted,
  presentedApp,
  providerPresented,
  deferredProvider,
  downgradedNormal,
}

final class AgentMessagePresentationReceipt {
  const AgentMessagePresentationReceipt({
    required this.ownerHash,
    required this.eventHash,
    required this.senderHash,
    required this.fullDigest,
    required this.nativeId,
    required this.disposition,
    required this.at,
  });

  final String ownerHash;
  final String eventHash;
  final String senderHash;
  final String fullDigest;
  final int nativeId;
  final AgentMessageReceiptDisposition disposition;
  final DateTime at;

  bool get isTerminal => disposition != AgentMessageReceiptDisposition.claimed;

  factory AgentMessagePresentationReceipt.fromJson(Map<String, Object?> json) {
    if (json.length != 7 ||
        json['owner_hash'] is! String ||
        json['event_hash'] is! String ||
        json['sender_hash'] is! String ||
        json['full_digest'] is! String ||
        json['native_id'] is! int ||
        json['disposition'] is! String ||
        json['at'] is! String) {
      throw const FormatException();
    }
    final ownerHash = json['owner_hash']! as String;
    final eventHash = json['event_hash']! as String;
    final senderHash = json['sender_hash']! as String;
    final fullDigest = json['full_digest']! as String;
    final nativeId = json['native_id']! as int;
    final dispositionName = json['disposition']! as String;
    final disposition = AgentMessageReceiptDisposition.values
        .where((candidate) => candidate.name == dispositionName)
        .firstOrNull;
    final at = DateTime.tryParse(json['at']! as String);
    if (!_isDigest(ownerHash) ||
        !_isDigest(eventHash) ||
        !_isDigest(senderHash) ||
        !_isDigest(fullDigest) ||
        nativeId < 0 ||
        nativeId > 0x7fffffff ||
        disposition == null ||
        at == null) {
      throw const FormatException();
    }
    return AgentMessagePresentationReceipt(
      ownerHash: ownerHash,
      eventHash: eventHash,
      senderHash: senderHash,
      fullDigest: fullDigest,
      nativeId: nativeId,
      disposition: disposition,
      at: at.toUtc(),
    );
  }

  AgentMessagePresentationReceipt copyWith({
    AgentMessageReceiptDisposition? disposition,
    DateTime? at,
  }) => AgentMessagePresentationReceipt(
    ownerHash: ownerHash,
    eventHash: eventHash,
    senderHash: senderHash,
    fullDigest: fullDigest,
    nativeId: nativeId,
    disposition: disposition ?? this.disposition,
    at: at ?? this.at,
  );

  Map<String, Object> toJson() => <String, Object>{
    'owner_hash': ownerHash,
    'event_hash': eventHash,
    'sender_hash': senderHash,
    'full_digest': fullDigest,
    'native_id': nativeId,
    'disposition': disposition.name,
    'at': at.toUtc().toIso8601String(),
  };

  static bool _isDigest(String value) =>
      value.length == 64 &&
      value.codeUnits.every(
        (unit) =>
            (unit >= 0x30 && unit <= 0x39) || (unit >= 0x61 && unit <= 0x66),
      );
}

final class AgentMessageUrgentPresentationCounts {
  const AgentMessageUrgentPresentationCounts({
    required this.senderCount,
    required this.accountCount,
  });

  final int senderCount;
  final int accountCount;
}

final class AgentMessagePresentationClaim {
  const AgentMessagePresentationClaim._(
    this.receipt,
    this.isNew,
    this.isCollision,
  );

  const AgentMessagePresentationClaim.claimed(
    AgentMessagePresentationReceipt receipt,
  ) : this._(receipt, true, false);

  const AgentMessagePresentationClaim.existing(
    AgentMessagePresentationReceipt receipt,
  ) : this._(receipt, false, false);

  const AgentMessagePresentationClaim.collision() : this._(null, false, true);

  final AgentMessagePresentationReceipt? receipt;
  final bool isNew;
  final bool isCollision;
}

String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
