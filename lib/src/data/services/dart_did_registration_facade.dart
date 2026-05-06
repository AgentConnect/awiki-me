import 'dart:math';

import 'package:anp/anp.dart';

import '../../domain/services/did_registration_facade.dart';

class DartDidRegistrationFacade implements DidRegistrationFacade {
  DartDidRegistrationFacade({String? domain})
    : _domain = _normalizeDomain(
        domain ??
            const String.fromEnvironment(
              'AWIKI_DID_DOMAIN',
              defaultValue: _defaultDomain,
            ),
      );

  static const String _defaultDomain = 'awiki.ai';
  static const String _vmKeyAuth = vmKeyAuth;
  static const String _vmKeyE2eeSigning = vmKeyE2eeSigning;
  static const String _vmKeyE2eeAgreement = vmKeyE2eeAgreement;

  final Random _random = Random.secure();
  final String _domain;

  @override
  Future<Map<String, Object?>> buildRegisterHandleParams({
    String? phone,
    String? otp,
    String? email,
    required String handle,
    String? inviteCode,
    String? nickName,
  }) async {
    final challenge = _generateChallengeHex(16);
    final bundle = createDidWbaDocument(
      _domain,
      options: DidDocumentOptions(
        pathSegments: <String>[handle],
        didProfile: DidProfile.e1,
        proofPurpose: 'assertionMethod',
        domain: _domain,
        challenge: challenge,
      ),
    );
    final did = bundle.did;
    final auth = bundle.keys[_vmKeyAuth]!;
    final signing = bundle.keys[_vmKeyE2eeSigning]!;
    final agreement = bundle.keys[_vmKeyE2eeAgreement]!;

    return <String, Object?>{
      'did': did,
      'did_document': bundle.didDocument,
      'proof_purpose': 'assertionMethod',
      'domain': _domain,
      'challenge': challenge,
      'private_key_pem': auth.privateKeyPem,
      'public_key_pem': auth.publicKeyPem,
      'e2ee_signing_private_pem': signing.privateKeyPem,
      'e2ee_signing_public_pem': signing.publicKeyPem,
      'e2ee_agreement_private_pem': agreement.privateKeyPem,
      'e2ee_agreement_public_pem': agreement.publicKeyPem,
    };
  }

  @override
  Future<String> generateDidAuthHeader({
    required Map<String, Object?> didDocument,
    required String privateKeyPem,
    required String domain,
  }) async {
    final did = didDocument['id']?.toString();
    if (did == null || did.isEmpty) {
      throw ArgumentError('DID document is missing the id field.');
    }
    if (!_isE1Did(did)) {
      throw ArgumentError('Only e1 DID identities are supported.');
    }
    return generateAuthHeader(
      didDocument,
      domain,
      privateKeyFromPem(privateKeyPem),
    );
  }

  @override
  Future<bool> isSupported() async => true;

  bool _isE1Did(String did) => did.trim().split(':').last.startsWith('e1_');

  static String _normalizeDomain(String domain) {
    final normalized = domain.trim();
    return normalized.isEmpty ? _defaultDomain : normalized;
  }

  String _generateChallengeHex(int size) {
    final bytes = List<int>.generate(size, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
