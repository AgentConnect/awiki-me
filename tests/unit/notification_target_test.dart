import 'dart:convert';

import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/domain/entities/notification_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final scope = StorageScopeId.parse('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

  test('round-trips strict version 2 payload with owner identity', () {
    final target = NotificationTarget(
      storageScopeId: scope,
      ownerDid: 'did:test:owner',
      conversationId: 'dm:canonical-conversation',
    );

    final restored = NotificationTarget.decode(target.encode());

    expect(restored.storageScopeId, scope);
    expect(restored.ownerDid, 'did:test:owner');
    expect(restored.conversationId, 'dm:canonical-conversation');
    expect(jsonDecode(target.encode()), <String, Object?>{
      'schema_version': 2,
      'storage_scope_id': scope.value,
      'owner_did': 'did:test:owner',
      'conversation_id': 'dm:canonical-conversation',
    });
  });

  test('rejects malformed, unknown-version and noncanonical payloads', () {
    for (final payload in <String?>[
      null,
      '',
      '{broken',
      jsonEncode(<String, Object?>{
        'schema_version': 3,
        'storage_scope_id': scope.value,
        'owner_did': 'did:test:owner',
        'conversation_id': 'dm:1',
      }),
      jsonEncode(<String, Object?>{
        'schema_version': 1,
        'storage_scope_id': scope.value,
        'conversation_id': 'dm:1',
      }),
      jsonEncode(<String, Object?>{
        'schema_version': 2,
        'storage_scope_id': scope.value.toUpperCase(),
        'owner_did': 'did:test:owner',
        'conversation_id': 'dm:1',
      }),
      jsonEncode(<String, Object?>{
        'schema_version': 2,
        'storage_scope_id': scope.value,
        'owner_did': 'did:test:owner',
        'conversation_id': ' dm:1 ',
      }),
      jsonEncode(<String, Object?>{
        'schema_version': 2,
        'storage_scope_id': scope.value,
        'owner_did': 'did:test:owner',
        'conversation_id': 'dm:1',
        'extra': true,
      }),
    ]) {
      final activation = NotificationActivation.fromPayload(payload);
      expect(activation.isValid, isFalse, reason: '$payload');
      expect(activation.target, isNull);
    }
  });

  test('constructor rejects empty, control and oversized conversation IDs', () {
    for (final conversationId in <String>[
      '',
      'dm:\n1',
      List<String>.filled(
        NotificationTarget.maxConversationIdLength + 1,
        'x',
      ).join(),
    ]) {
      expect(
        () => NotificationTarget(
          storageScopeId: scope,
          ownerDid: 'did:test:owner',
          conversationId: conversationId,
        ),
        throwsFormatException,
      );
    }
  });

  test('constructor rejects invalid owner DID', () {
    for (final ownerDid in <String>[
      '',
      'owner-without-did-prefix',
      ' did:test:owner ',
      'did:test:\nowner',
      List<String>.filled(NotificationTarget.maxOwnerDidLength + 1, 'x').join(),
    ]) {
      expect(
        () => NotificationTarget(
          storageScopeId: scope,
          ownerDid: ownerDid,
          conversationId: 'dm:1',
        ),
        throwsFormatException,
      );
    }
  });
}
