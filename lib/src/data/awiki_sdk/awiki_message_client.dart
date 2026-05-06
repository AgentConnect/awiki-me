import 'dart:math';

import 'awiki_anp_proof_builder.dart';
import 'awiki_anp_session.dart';
import 'awiki_service_client.dart';

class AwikiMessageClient {
  AwikiMessageClient({
    required AwikiServiceClient serviceClient,
    AwikiAnpProofBuilder? proofBuilder,
    Random? random,
  }) : _serviceClient = serviceClient,
       _proofBuilder = proofBuilder ?? AwikiAnpProofBuilder(),
       _random = random ?? Random.secure();

  static const String rpcEndpoint = '/im/rpc';

  final AwikiServiceClient _serviceClient;
  final AwikiAnpProofBuilder _proofBuilder;
  final Random _random;

  Future<Map<String, Object?>> getCapabilities({
    required AwikiAnpSession session,
  }) {
    _requireE1Session(session);
    return _serviceClient.rpcCall(
      path: rpcEndpoint,
      method: 'anp.get_capabilities',
      bearerToken: session.jwtToken,
      params: <String, Object?>{
        'meta': _localMeta(
          profile: 'anp.core.binding.v1',
          senderDid: session.did,
          includeOperation: true,
        ),
        'body': <String, Object?>{},
        'client': <String, Object?>{'response_mode': 'wait-final'},
      },
    );
  }

  Future<Map<String, Object?>> sendDirect({
    required AwikiAnpSession session,
    required String targetDid,
    required String text,
    String contentType = 'text/plain',
  }) async {
    _requireE1Session(session);
    const method = 'direct.send';
    final meta = _baseMeta(
      profile: 'anp.direct.base.v1',
      senderDid: session.did,
      targetKind: 'agent',
      targetDid: targetDid,
      contentType: contentType,
      includeMessageId: true,
    );
    final body = <String, Object?>{'text': text};
    final params = await _signedParams(
      session: session,
      method: method,
      meta: meta,
      body: body,
    );
    final result = await _serviceClient.rpcCall(
      path: rpcEndpoint,
      method: method,
      bearerToken: session.jwtToken,
      params: params,
    );
    result.putIfAbsent('message_id', () => meta['message_id']);
    result.putIfAbsent('operation_id', () => meta['operation_id']);
    result.putIfAbsent('target_did', () => targetDid);
    return result;
  }

  Future<Map<String, Object?>> sendGroup({
    required AwikiAnpSession session,
    required String groupDid,
    required String text,
    String contentType = 'text/plain',
  }) async {
    _requireE1Session(session);
    const method = 'group.send';
    final meta = _baseMeta(
      profile: 'anp.group.base.v1',
      senderDid: session.did,
      targetKind: 'group',
      targetDid: groupDid,
      contentType: contentType,
      includeMessageId: true,
    );
    final body = <String, Object?>{'text': text};
    final params = await _signedParams(
      session: session,
      method: method,
      meta: meta,
      body: body,
    );
    final result = await _serviceClient.rpcCall(
      path: rpcEndpoint,
      method: method,
      bearerToken: session.jwtToken,
      params: params,
    );
    result.putIfAbsent('message_id', () => meta['message_id']);
    result.putIfAbsent('operation_id', () => meta['operation_id']);
    result.putIfAbsent('group_did', () => groupDid);
    return result;
  }

  Future<Map<String, Object?>> getInbox({
    required AwikiAnpSession session,
    int limit = 100,
  }) {
    _requireE1Session(session);
    return _serviceClient.rpcCall(
      path: rpcEndpoint,
      method: 'inbox.get',
      bearerToken: session.jwtToken,
      params: <String, Object?>{
        'meta': _localMeta(
          profile: 'anp.inbox.local.v1',
          senderDid: session.did,
          includeOperation: true,
        ),
        'body': <String, Object?>{'user_did': session.did, 'limit': limit},
      },
    );
  }

  Future<Map<String, Object?>> getDirectHistory({
    required AwikiAnpSession session,
    required String peerDid,
    int limit = 100,
    String? cursor,
    int? skip,
  }) {
    _requireE1Session(session);
    return _serviceClient.rpcCall(
      path: rpcEndpoint,
      method: 'direct.get_history',
      bearerToken: session.jwtToken,
      params: <String, Object?>{
        'meta': _localMeta(
          profile: 'anp.direct.local.v1',
          senderDid: session.did,
          includeOperation: true,
        ),
        'body': <String, Object?>{
          'user_did': session.did,
          'peer_did': peerDid,
          'limit': limit,
          if (cursor != null && cursor.isNotEmpty) 'since_seq': cursor,
          if (skip != null && skip > 0) 'skip': skip,
        },
      },
    );
  }

  Future<Map<String, Object?>> markRead({
    required AwikiAnpSession session,
    required List<String> messageIds,
  }) {
    _requireE1Session(session);
    return _serviceClient.rpcCall(
      path: rpcEndpoint,
      method: 'inbox.mark_read',
      bearerToken: session.jwtToken,
      params: <String, Object?>{
        'meta': _localMeta(
          profile: 'anp.inbox.local.v1',
          senderDid: session.did,
          includeOperation: true,
        ),
        'body': <String, Object?>{
          'user_did': session.did,
          'message_ids': messageIds,
        },
      },
    );
  }

  Future<Map<String, Object?>> createGroup({
    required AwikiAnpSession session,
    required String serviceDid,
    required String name,
    required String description,
    required String slug,
    required String goal,
    required String rules,
    String? messagePrompt,
    String? admissionMode,
  }) async {
    _requireE1Session(session);
    const method = 'group.create';
    final meta = _baseMeta(
      profile: 'anp.group.base.v1',
      senderDid: session.did,
      targetKind: 'service',
      targetDid: serviceDid,
      contentType: 'application/json',
    );
    final body = <String, Object?>{
      'group_profile': <String, Object?>{
        'display_name': name,
        if (description.isNotEmpty) 'description': description,
        if (slug.isNotEmpty) 'slug': slug,
        if (goal.isNotEmpty) 'goal': goal,
        if (rules.isNotEmpty) 'rules': rules,
        if (messagePrompt != null && messagePrompt.isNotEmpty)
          'message_prompt': messagePrompt,
      },
      'group_policy': _groupPolicy(admissionMode),
    };
    final params = await _signedParams(
      session: session,
      method: method,
      meta: meta,
      body: body,
    );
    return _serviceClient.rpcCall(
      path: rpcEndpoint,
      method: method,
      bearerToken: session.jwtToken,
      params: params,
    );
  }

  Future<Map<String, Object?>> joinGroup({
    required AwikiAnpSession session,
    required String groupDid,
    String? reasonText,
  }) async {
    _requireE1Session(session);
    return _groupMutation(
      session: session,
      groupDid: groupDid,
      method: 'group.join',
      body: <String, Object?>{
        if (reasonText != null && reasonText.isNotEmpty)
          'reason_text': reasonText,
      },
    );
  }

  Future<Map<String, Object?>> getGroup({
    required AwikiAnpSession session,
    required String groupDid,
  }) {
    _requireE1Session(session);
    return _serviceClient.rpcCall(
      path: rpcEndpoint,
      method: 'group.get',
      bearerToken: session.jwtToken,
      params: <String, Object?>{
        'meta': _groupLocalMeta(session: session, groupDid: groupDid),
        'body': <String, Object?>{'group_did': groupDid},
      },
    );
  }

  Future<Map<String, Object?>> listGroupMembers({
    required AwikiAnpSession session,
    required String groupDid,
    int limit = 100,
  }) {
    _requireE1Session(session);
    return _serviceClient.rpcCall(
      path: rpcEndpoint,
      method: 'group.list_members',
      bearerToken: session.jwtToken,
      params: <String, Object?>{
        'meta': _groupLocalMeta(session: session, groupDid: groupDid),
        'body': <String, Object?>{'group_did': groupDid, 'limit': limit},
      },
    );
  }

  Future<Map<String, Object?>> listGroupMessages({
    required AwikiAnpSession session,
    required String groupDid,
    int limit = 100,
    String? cursor,
    int? skip,
  }) {
    _requireE1Session(session);
    return _serviceClient.rpcCall(
      path: rpcEndpoint,
      method: 'group.list_messages',
      bearerToken: session.jwtToken,
      params: <String, Object?>{
        'meta': _groupLocalMeta(session: session, groupDid: groupDid),
        'body': <String, Object?>{
          'group_did': groupDid,
          'limit': limit,
          if (cursor != null && cursor.isNotEmpty) 'since_seq': cursor,
          if (skip != null && skip > 0) 'skip': skip,
        },
      },
    );
  }

  Future<Map<String, Object?>> _groupMutation({
    required AwikiAnpSession session,
    required String groupDid,
    required String method,
    required Map<String, Object?> body,
  }) async {
    _requireE1Session(session);
    final meta = _baseMeta(
      profile: 'anp.group.base.v1',
      senderDid: session.did,
      targetKind: 'group',
      targetDid: groupDid,
      contentType: 'application/json',
    );
    final params = await _signedParams(
      session: session,
      method: method,
      meta: meta,
      body: body,
    );
    return _serviceClient.rpcCall(
      path: rpcEndpoint,
      method: method,
      bearerToken: session.jwtToken,
      params: params,
    );
  }

  Future<Map<String, Object?>> _signedParams({
    required AwikiAnpSession session,
    required String method,
    required Map<String, Object?> meta,
    required Map<String, Object?> body,
  }) async {
    _requireE1Session(session);
    final didDocument = session.didDocument;
    final privateKeyPem = session.privateKeyPem ?? '';
    if (didDocument == null || didDocument.isEmpty || privateKeyPem.isEmpty) {
      throw StateError('ANP signed message requires DID document and key-1.');
    }
    return <String, Object?>{
      'meta': meta,
      'auth': await _proofBuilder.buildAuth(
        method: method,
        meta: meta,
        body: body,
        didDocument: didDocument,
        privateKeyPem: privateKeyPem,
      ),
      'body': body,
    };
  }

  void _requireE1Session(AwikiAnpSession session) {
    if (!session.isE1Did) {
      throw StateError(
        'ANP message service requires an e1 DID identity. '
        'Legacy K1 identities are not supported.',
      );
    }
  }

  Map<String, Object?> _baseMeta({
    required String profile,
    required String senderDid,
    required String targetKind,
    required String targetDid,
    required String contentType,
    bool includeMessageId = false,
  }) {
    return <String, Object?>{
      'anp_version': '1.0',
      'profile': profile,
      'security_profile': 'transport-protected',
      'sender_did': senderDid,
      'target': <String, Object?>{'kind': targetKind, 'did': targetDid},
      'operation_id': 'op-${_generateId()}',
      if (includeMessageId) 'message_id': 'msg-${_generateId()}',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'content_type': contentType,
    };
  }

  Map<String, Object?> _localMeta({
    required String profile,
    required String senderDid,
    bool includeOperation = false,
  }) {
    return <String, Object?>{
      'anp_version': '1.0',
      'profile': profile,
      'security_profile': 'transport-protected',
      'sender_did': senderDid,
      if (includeOperation) 'operation_id': 'op-${_generateId()}',
      if (includeOperation)
        'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Map<String, Object?> _groupLocalMeta({
    required AwikiAnpSession session,
    required String groupDid,
  }) {
    return <String, Object?>{
      ..._localMeta(profile: 'anp.group.local.v1', senderDid: session.did),
      'target': <String, Object?>{'kind': 'group', 'did': groupDid},
    };
  }

  Map<String, Object?> _groupPolicy(String? admissionMode) {
    return <String, Object?>{
      'admission_mode': admissionMode != null && admissionMode.isNotEmpty
          ? admissionMode
          : 'open-join',
      'attachments_allowed': true,
      'max_members': '500',
      'message_security_profile': 'transport-protected',
      'bootstrap_security_profile': 'transport-protected',
      'permissions': <String, Object?>{
        'send': 'member',
        'add': 'admin',
        'remove': 'admin',
        'update_profile': 'admin',
        'update_policy': 'owner',
      },
    };
  }

  String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final suffix = _random.nextInt(0x7fffffff).toRadixString(16);
    return '$now$suffix';
  }
}
