import 'dart:convert';

import '../../application/tenant/app_tenant.dart';

final class NotificationTarget {
  const NotificationTarget._({
    required this.storageScopeId,
    required this.ownerDid,
    required this.conversationId,
  });

  factory NotificationTarget({
    required StorageScopeId storageScopeId,
    required String ownerDid,
    required String conversationId,
  }) {
    _validateOwnerDid(ownerDid);
    _validateConversationId(conversationId);
    return NotificationTarget._(
      storageScopeId: storageScopeId,
      ownerDid: ownerDid,
      conversationId: conversationId,
    );
  }

  static const int schemaVersion = 2;
  static const int maxOwnerDidLength = 2048;
  static const int maxConversationIdLength = 512;

  final StorageScopeId storageScopeId;
  final String ownerDid;
  final String conversationId;

  factory NotificationTarget.fromJson(Map<String, Object?> json) {
    if (json.length != 4 ||
        json['schema_version'] != schemaVersion ||
        json['storage_scope_id'] is! String ||
        json['owner_did'] is! String ||
        json['conversation_id'] is! String) {
      throw const FormatException('notification_target_invalid');
    }
    final scope = StorageScopeId.parse(json['storage_scope_id']! as String);
    final ownerDid = json['owner_did']! as String;
    final conversationId = json['conversation_id']! as String;
    _validateOwnerDid(ownerDid);
    _validateConversationId(conversationId);
    return NotificationTarget(
      storageScopeId: scope,
      ownerDid: ownerDid,
      conversationId: conversationId,
    );
  }

  factory NotificationTarget.decode(String encoded) {
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      throw const FormatException('notification_target_invalid');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('notification_target_invalid');
    }
    return NotificationTarget.fromJson(decoded);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': schemaVersion,
    'storage_scope_id': storageScopeId.value,
    'owner_did': ownerDid,
    'conversation_id': conversationId,
  };

  String encode() => jsonEncode(toJson());

  static void _validateOwnerDid(String ownerDid) {
    if (!ownerDid.startsWith('did:') ||
        ownerDid.trim() != ownerDid ||
        ownerDid.length > maxOwnerDidLength ||
        ownerDid.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      throw const FormatException('notification_target_invalid');
    }
  }

  static void _validateConversationId(String conversationId) {
    if (conversationId.isEmpty ||
        conversationId.trim() != conversationId ||
        conversationId.length > maxConversationIdLength ||
        conversationId.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      throw const FormatException('notification_target_invalid');
    }
  }
}

final class NotificationActivation {
  const NotificationActivation._({this.target});

  const NotificationActivation.invalid() : this._();

  const NotificationActivation.valid(NotificationTarget target)
    : this._(target: target);

  factory NotificationActivation.fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) {
      return const NotificationActivation.invalid();
    }
    try {
      return NotificationActivation.valid(NotificationTarget.decode(payload));
    } on FormatException {
      return const NotificationActivation.invalid();
    }
  }

  final NotificationTarget? target;
  bool get isValid => target != null;
}
