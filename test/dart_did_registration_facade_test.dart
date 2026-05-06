import 'package:awiki_me/src/data/services/dart_did_registration_facade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'buildRegisterHandleParams creates e1 DID document and key material',
    () async {
      final facade = DartDidRegistrationFacade();

      final payload = await facade.buildRegisterHandleParams(handle: 'alice');

      final did = payload['did'] as String;
      final didDocument = payload['did_document'] as Map<String, Object?>;
      final proof = didDocument['proof'] as Map<String, Object?>;
      final verificationMethods = didDocument['verificationMethod'] as List;
      final key1 = verificationMethods.first as Map<Object?, Object?>;
      expect(did, startsWith('did:wba:awiki.ai:alice:e1_'));
      expect(didDocument['id'], did);
      expect(didDocument['authentication'], <String>['$did#key-1']);
      expect(didDocument['assertionMethod'], <String>['$did#key-1']);
      expect(didDocument['keyAgreement'], <String>['$did#key-3']);
      expect(key1['id'], '$did#key-1');
      expect(key1['type'], 'Multikey');
      expect(key1['publicKeyMultibase']?.toString(), startsWith('z'));
      expect(proof['type'], 'DataIntegrityProof');
      expect(proof['cryptosuite'], 'eddsa-jcs-2022');
      expect(proof['proofPurpose'], 'assertionMethod');
      expect(proof['verificationMethod'], '$did#key-1');
      expect(proof['domain'], 'awiki.ai');
      expect(proof['challenge']?.toString(), hasLength(32));
      expect(payload['private_key_pem']?.toString(), contains('PRIVATE KEY'));
      expect(payload['public_key_pem']?.toString(), contains('PUBLIC KEY'));
      expect(
        payload['e2ee_signing_private_pem']?.toString(),
        contains('PRIVATE KEY'),
      );
      expect(
        payload['e2ee_agreement_private_pem']?.toString(),
        contains('PRIVATE KEY'),
      );
    },
  );

  test('generateDidAuthHeader signs e1 DIDWba auth header', () async {
    final facade = DartDidRegistrationFacade();
    final payload = await facade.buildRegisterHandleParams(handle: 'alice');
    final did = payload['did'] as String;

    final header = await facade.generateDidAuthHeader(
      didDocument: payload['did_document'] as Map<String, Object?>,
      privateKeyPem: payload['private_key_pem'] as String,
      domain: 'awiki.ai',
    );

    expect(header, startsWith('DIDWba v="1.1"'));
    expect(header, contains('did="$did"'));
    expect(header, contains('verification_method="key-1"'));
    expect(header, contains('signature="'));
  });

  test('buildRegisterHandleParams supports configured DID domain', () async {
    final facade = DartDidRegistrationFacade(domain: 'awiki.info');

    final payload = await facade.buildRegisterHandleParams(handle: 'alice');
    final did = payload['did'] as String;
    final didDocument = payload['did_document'] as Map<String, Object?>;
    final proof = didDocument['proof'] as Map<String, Object?>;

    expect(did, startsWith('did:wba:awiki.info:alice:e1_'));
    expect(payload['domain'], 'awiki.info');
    expect(proof['domain'], 'awiki.info');
  });

  test('generateDidAuthHeader rejects legacy non-e1 DID document', () async {
    final facade = DartDidRegistrationFacade();

    expect(
      () => facade.generateDidAuthHeader(
        didDocument: <String, Object?>{
          'id': 'did:wba:awiki.ai:alice:k1_legacy',
          'authentication': <String>['did:wba:awiki.ai:alice:k1_legacy#key-1'],
        },
        privateKeyPem: 'not-used',
        domain: 'awiki.ai',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
