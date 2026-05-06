import 'package:anp/anp.dart';

const String awikiOriginProofScheme = 'anp-rfc9421-origin-proof-v1';

class AwikiAnpProofBuilder {
  Future<Map<String, Object?>> buildAuth({
    required String method,
    required Map<String, Object?> meta,
    required Map<String, Object?> body,
    required Map<String, Object?> didDocument,
    required String privateKeyPem,
  }) async {
    final keyId = authenticationVerificationMethodId(didDocument);
    if (keyId.isEmpty) {
      throw StateError('DID document is missing authentication method.');
    }
    final privateKey = privateKeyFromPem(privateKeyPem);
    final signer = PrivateKeyMessageSigner(
      keyId: keyId,
      privateKey: privateKey,
    );
    final proof = await generateRfc9421OriginProof(method, meta, body, signer);
    return <String, Object?>{
      'scheme': awikiOriginProofScheme,
      'origin_proof': proof.toJson(),
    };
  }

  String authenticationVerificationMethodId(Map<String, Object?> didDocument) {
    final authentication = didDocument['authentication'];
    final first = _firstVerificationMethod(authentication);
    if (first.isNotEmpty) {
      return first;
    }
    final verificationMethod = didDocument['verificationMethod'];
    if (verificationMethod is List && verificationMethod.isNotEmpty) {
      final item = verificationMethod.first;
      if (item is Map && item['id'] != null) {
        return item['id'].toString();
      }
      if (item is String) {
        return item;
      }
    }
    return '';
  }

  String _firstVerificationMethod(Object? raw) {
    if (raw is String) {
      return raw;
    }
    if (raw is List && raw.isNotEmpty) {
      final item = raw.first;
      if (item is String) {
        return item;
      }
      if (item is Map && item['id'] != null) {
        return item['id'].toString();
      }
    }
    if (raw is Map && raw['id'] != null) {
      return raw['id'].toString();
    }
    return '';
  }
}
