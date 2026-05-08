import 'dart:convert';

import 'package:anp/anp.dart';
import 'package:awiki_me/src/data/awiki_sdk/awiki_anp_session.dart';
import 'package:awiki_me/src/data/awiki_sdk/awiki_message_client.dart';
import 'package:awiki_me/src/data/awiki_sdk/awiki_service_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('direct.send uses /im/rpc and ANP meta auth body envelope', () async {
    late http.Request capturedRequest;
    late Map<String, Object?> capturedPayload;
    final client = MockClient((request) async {
      capturedRequest = request;
      capturedPayload = jsonDecode(request.body) as Map<String, Object?>;
      return http.Response(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'req-1',
          'result': <String, Object?>{
            'accepted': true,
            'message_id': 'msg-remote',
            'operation_id': 'op-remote',
          },
        }),
        200,
      );
    });

    final key = generatePrivateKeyMaterial(KeyType.ed25519);
    const senderDid = 'did:wba:awiki.ai:user:alice:e1_sender';
    const targetDid = 'did:wba:awiki.ai:user:bob:e1_peer';
    final session = AwikiAnpSession(
      did: senderDid,
      jwtToken: 'token',
      didDocument: <String, Object?>{
        'id': senderDid,
        'authentication': <String>['$senderDid#key-1'],
      },
      privateKeyPem: key.toPem(),
    );
    final messageClient = AwikiMessageClient(
      serviceClient: AwikiServiceClient(
        baseUrl: 'https://awiki.ai',
        httpClient: client,
      ),
    );

    final result = await messageClient.sendDirect(
      session: session,
      targetDid: targetDid,
      text: 'hello',
    );

    expect(capturedRequest.url.path, '/im/rpc');
    expect(capturedPayload['method'], 'direct.send');
    expect(capturedRequest.headers['Authorization'], 'Bearer token');
    final params = capturedPayload['params'] as Map<String, Object?>;
    final meta = params['meta'] as Map<String, Object?>;
    final auth = params['auth'] as Map<String, Object?>;
    final body = params['body'] as Map<String, Object?>;
    expect(meta['profile'], 'anp.direct.base.v1');
    expect(meta['security_profile'], 'transport-protected');
    expect(meta['sender_did'], session.did);
    expect(meta['target'], <String, Object?>{
      'kind': 'agent',
      'did': targetDid,
    });
    expect(meta['operation_id']?.toString().startsWith('op-'), isTrue);
    expect(meta['message_id']?.toString().startsWith('msg-'), isTrue);
    expect(auth['scheme'], 'anp-rfc9421-origin-proof-v1');
    final proof = auth['origin_proof'] as Map<String, Object?>;
    expect(proof['contentDigest']?.toString(), startsWith('sha-256=:'));
    expect(proof['signatureInput']?.toString(), contains('"@method"'));
    expect(proof['signatureInput']?.toString(), contains('"@target-uri"'));
    expect(proof['signatureInput']?.toString(), contains('"content-digest"'));
    expect(proof['signature']?.toString(), startsWith('sig1=:'));
    expect(body['text'], 'hello');
    expect(result['message_id'], 'msg-remote');
  });

  test('message service methods reject legacy non-e1 DID identities', () async {
    final key = generatePrivateKeyMaterial(KeyType.ed25519);
    final messageClient = AwikiMessageClient(
      serviceClient: AwikiServiceClient(
        baseUrl: 'https://awiki.ai',
        httpClient: MockClient((request) async {
          fail('legacy K1 DID must be rejected before sending HTTP request');
        }),
      ),
    );

    expect(
      () => messageClient.sendDirect(
        session: AwikiAnpSession(
          did: 'did:wba:awiki.ai:user:alice:k1_legacy',
          jwtToken: 'token',
          didDocument: <String, Object?>{
            'id': 'did:wba:awiki.ai:user:alice:k1_legacy',
            'authentication': <String>[
              'did:wba:awiki.ai:user:alice:k1_legacy#key-1',
            ],
          },
          privateKeyPem: key.toPem(),
        ),
        targetDid: 'did:wba:awiki.ai:user:bob:e1_peer',
        text: 'hello',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('e1 DID identity'),
        ),
      ),
    );

    expect(
      () => messageClient.getInbox(
        session: const AwikiAnpSession(
          did: 'did:wba:awiki.ai:user:alice:k1_legacy',
          jwtToken: 'token',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('e1 DID identity'),
        ),
      ),
    );
  });

  test('inbox.get uses local inbox profile without origin proof', () async {
    late Map<String, Object?> capturedPayload;
    final client = MockClient((request) async {
      capturedPayload = jsonDecode(request.body) as Map<String, Object?>;
      return http.Response(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'req-1',
          'result': <String, Object?>{'messages': <Object?>[]},
        }),
        200,
      );
    });
    final messageClient = AwikiMessageClient(
      serviceClient: AwikiServiceClient(
        baseUrl: 'https://awiki.ai',
        httpClient: client,
      ),
    );

    await messageClient.getInbox(
      session: const AwikiAnpSession(
        did: 'did:wba:awiki.ai:user:alice:e1_sender',
        jwtToken: 'token',
      ),
      limit: 20,
    );

    expect(capturedPayload['method'], 'inbox.get');
    final params = capturedPayload['params'] as Map<String, Object?>;
    expect(params.containsKey('auth'), isFalse);
    final meta = params['meta'] as Map<String, Object?>;
    final body = params['body'] as Map<String, Object?>;
    expect(meta['profile'], 'anp.inbox.local.v1');
    expect(body['user_did'], 'did:wba:awiki.ai:user:alice:e1_sender');
    expect(body['limit'], 20);
  });
}
