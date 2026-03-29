import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

import '../../domain/services/did_registration_facade.dart';

class DartDidRegistrationFacade implements DidRegistrationFacade {
  DartDidRegistrationFacade();

  static const String _defaultDomain = 'awiki.ai';
  static const String _vmKeyAuth = 'key-1';
  static const String _algorithmEcPublicKey = '1.2.840.10045.2.1';
  static const String _curveSecp256k1 = '1.3.132.0.10';

  final ECDomainParameters _domain = ECDomainParameters('secp256k1');
  final Random _random = Random.secure();

  @override
  Future<Map<String, Object?>> buildRegisterHandleParams({
    String? phone,
    String? otp,
    String? email,
    required String handle,
    String? inviteCode,
    String? nickName,
  }) async {
    final created = _formatUtc(DateTime.now().toUtc());
    final challenge = _generateChallengeHex(16);

    final keyPair = _generateSecp256k1KeyPair();
    final publicKey = keyPair.publicKey;
    final privateKey = keyPair.privateKey;
    final publicX = publicKey.Q!.x!.toBigInteger()!;
    final publicY = publicKey.Q!.y!.toBigInteger()!;

    final key1Jwk = _secp256k1PublicKeyToJwk(x: publicX, y: publicY);
    final fingerprint = _computeSecp256k1JwkFingerprint(key1Jwk);
    final did = 'did:wba:$_defaultDomain:$handle:k1_$fingerprint';
    final key1Id = '$did#$_vmKeyAuth';

    final didDoc = <String, Object?>{
      '@context': <String>[
        'https://www.w3.org/ns/did/v1',
        'https://w3id.org/security/suites/jws-2020/v1',
        'https://w3id.org/security/suites/secp256k1-2019/v1',
      ],
      'id': did,
      'verificationMethod': <Object?>[
        <String, Object?>{
          'id': key1Id,
          'type': 'EcdsaSecp256k1VerificationKey2019',
          'controller': did,
          'publicKeyJwk': key1Jwk,
        },
      ],
      'authentication': <Object?>[key1Id],
    };

    final proofOptions = <String, Object?>{
      'type': 'EcdsaSecp256k1Signature2019',
      'created': created,
      'verificationMethod': key1Id,
      'proofPurpose': 'authentication',
      'domain': _defaultDomain,
      'challenge': challenge,
    };
    final toBeSigned = _buildProofSigningInput(didDoc, proofOptions);
    final proofValue = _signSecp256k1ToRawBase64Url(privateKey.d!, toBeSigned);
    didDoc['proof'] = <String, Object?>{
      'type': 'EcdsaSecp256k1Signature2019',
      'created': created,
      'verificationMethod': key1Id,
      'proofPurpose': 'authentication',
      'domain': _defaultDomain,
      'challenge': challenge,
      'proofValue': proofValue,
    };

    return <String, Object?>{
      'did': did,
      'did_document': didDoc,
      'proof_purpose': 'authentication',
      'domain': _defaultDomain,
      'challenge': challenge,
      'private_key_pem': _toPem(
        'PRIVATE KEY',
        _encodeSecp256k1PrivateKeyDer(
          privateScalar: privateKey.d!,
          publicKey: publicKey,
        ),
      ),
      'public_key_pem': _toPem(
        'PUBLIC KEY',
        _encodeSecp256k1PublicKeyDer(publicKey),
      ),
      'e2ee_signing_private_pem': null,
      'e2ee_signing_public_pem': null,
      'e2ee_agreement_private_pem': null,
      'e2ee_agreement_public_pem': null,
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
    final verificationMethod = _selectAuthenticationMethodFragment(didDocument);
    final nonce = _generateChallengeHex(16);
    final timestamp = _formatUtc(DateTime.now().toUtc());
    final canonicalJson = _jcsCanonicalize(<String, Object?>{
      'nonce': nonce,
      'timestamp': timestamp,
      'aud': domain,
      'did': did,
    });
    final contentHash = _sha256(canonicalJson);
    final privateScalar = _loadSecp256k1PrivateScalar(privateKeyPem);
    final signature = _signSecp256k1ToRawBase64Url(privateScalar, contentHash);
    return 'DIDWba v="1.1", did="$did", nonce="$nonce", timestamp="$timestamp", verification_method="$verificationMethod", signature="$signature"';
  }

  @override
  Future<bool> isSupported() async => true;

  AsymmetricKeyPair<ECPublicKey, ECPrivateKey> _generateSecp256k1KeyPair() {
    final generator = ECKeyGenerator();
    generator.init(
      ParametersWithRandom(
        ECKeyGeneratorParameters(_domain),
        _secureRandom(),
      ),
    );
    return generator.generateKeyPair();
  }

  SecureRandom _secureRandom() {
    final random = FortunaRandom();
    final seed = Uint8List.fromList(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    random.seed(KeyParameter(seed));
    return random;
  }

  Map<String, String> _secp256k1PublicKeyToJwk({
    required BigInt x,
    required BigInt y,
  }) {
    final xBytes = _toUnsignedFixed(x, 32);
    final yBytes = _toUnsignedFixed(y, 32);
    final compressed = _compressEcPoint(xBytes, yBytes);
    final kid = _base64UrlNoPadding(_sha256(Uint8List.fromList(compressed)));
    return <String, String>{
      'kty': 'EC',
      'crv': 'secp256k1',
      'x': _base64UrlNoPadding(xBytes),
      'y': _base64UrlNoPadding(yBytes),
      'kid': kid,
    };
  }

  String _computeSecp256k1JwkFingerprint(Map<String, String> jwk) {
    final canonical =
        '{"crv":"secp256k1","kty":"EC","x":"${jwk["x"]}","y":"${jwk["y"]}"}';
    return _base64UrlNoPadding(
      _sha256(Uint8List.fromList(ascii.encode(canonical))),
    );
  }

  Uint8List _buildProofSigningInput(
    Map<String, Object?> documentWithoutProof,
    Map<String, Object?> proofOptions,
  ) {
    final docHash = _sha256(_jcsCanonicalize(documentWithoutProof));
    final optionsHash = _sha256(_jcsCanonicalize(proofOptions));
    return Uint8List.fromList(<int>[...optionsHash, ...docHash]);
  }

  String _signSecp256k1ToRawBase64Url(BigInt privateScalar, Uint8List data) {
    final signer = ECDSASigner(null, HMac(SHA256Digest(), 64));
    signer.init(
      true,
      PrivateKeyParameter<ECPrivateKey>(
        ECPrivateKey(privateScalar, _domain),
      ),
    );
    final hashed = _sha256(data);
    final signature = signer.generateSignature(hashed) as ECSignature;
    final rBytes = _toUnsignedFixed(signature.r, 32);
    final sBytes = _toUnsignedFixed(signature.s, 32);
    final raw = Uint8List.fromList(<int>[...rBytes, ...sBytes]);
    return _base64UrlNoPadding(raw);
  }

  String _selectAuthenticationMethodFragment(Map<String, Object?> didDocument) {
    final authentication = didDocument['authentication'];
    if (authentication is! List || authentication.isEmpty) {
      throw ArgumentError('DID document is missing authentication methods.');
    }
    final authMethod = authentication.first;
    final authId = switch (authMethod) {
      String value => value,
      Map<Object?, Object?> value => value['id']?.toString() ?? '',
      _ => '',
    };
    if (authId.isEmpty) {
      throw ArgumentError('Invalid authentication method in DID document.');
    }
    return authId.split('#').last;
  }

  BigInt _loadSecp256k1PrivateScalar(String privateKeyPem) {
    final der = _decodePem(privateKeyPem);
    final parser = ASN1Parser(der);
    final privateKeyInfo = parser.nextObject() as ASN1Sequence;
    final privateOctets = privateKeyInfo.elements![2] as ASN1OctetString;
    final innerParser = ASN1Parser(privateOctets.octets);
    final ecPrivateKey = innerParser.nextObject() as ASN1Sequence;
    final privateKeyBytes =
        (ecPrivateKey.elements![1] as ASN1OctetString).octets!;
    return _decodeBigInt(privateKeyBytes);
  }

  Uint8List _encodeSecp256k1PublicKeyDer(ECPublicKey publicKey) {
    final algorithm = ASN1AlgorithmIdentifier(
      ASN1ObjectIdentifier.fromIdentifierString(_algorithmEcPublicKey),
      parameters: ASN1ObjectIdentifier.fromIdentifierString(_curveSecp256k1),
    );
    final publicKeyInfo = ASN1SubjectPublicKeyInfo(
      algorithm,
      ASN1BitString(stringValues: publicKey.Q!.getEncoded(false)),
    );
    return publicKeyInfo.encode();
  }

  Uint8List _encodeSecp256k1PrivateKeyDer({
    required BigInt privateScalar,
    required ECPublicKey publicKey,
  }) {
    final inner = ASN1Sequence();
    inner.add(ASN1Integer(privateScalar));
    inner.elements!.insert(0, ASN1Integer.fromtInt(1));
    inner.add(ASN1OctetString(octets: _toUnsignedFixed(privateScalar, 32)));

    final curveOid = ASN1ObjectIdentifier.fromIdentifierString(_curveSecp256k1);
    final parametersObject = ASN1Object(tag: 0xA0)
      ..valueBytes = curveOid.encode()
      ..valueByteLength = curveOid.encode().length;
    inner.add(parametersObject);

    final publicBitString =
        ASN1BitString(stringValues: publicKey.Q!.getEncoded(false));
    final publicKeyObject = ASN1Object(tag: 0xA1)
      ..valueBytes = publicBitString.encode()
      ..valueByteLength = publicBitString.encode().length;
    inner.add(publicKeyObject);

    final outer = ASN1PrivateKeyInfo(
      ASN1Integer.fromtInt(0),
      ASN1AlgorithmIdentifier(
        ASN1ObjectIdentifier.fromIdentifierString(_algorithmEcPublicKey),
        parameters: ASN1ObjectIdentifier.fromIdentifierString(_curveSecp256k1),
      ),
      ASN1OctetString(octets: inner.encode()),
    );
    return outer.encode();
  }

  String _toPem(String label, Uint8List der) {
    final base64Body = base64.encode(der);
    final wrapped = base64Body.replaceAllMapped(
      RegExp('.{1,64}'),
      (match) => '${match.group(0)}\n',
    );
    return '-----BEGIN $label-----\n$wrapped-----END $label-----\n';
  }

  Uint8List _decodePem(String pem) {
    final base64Body = pem
        .split('\n')
        .where((line) =>
            !line.startsWith('-----BEGIN') &&
            !line.startsWith('-----END') &&
            line.trim().isNotEmpty)
        .join();
    return Uint8List.fromList(base64.decode(base64Body));
  }

  String _generateChallengeHex(int size) {
    final bytes = List<int>.generate(size, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uint8List _jcsCanonicalize(Object? value) {
    return Uint8List.fromList(utf8.encode(_jcsSerialize(value)));
  }

  String _jcsSerialize(Object? value) {
    if (value == null) {
      return 'null';
    }
    if (value is String) {
      return jsonEncode(value);
    }
    if (value is bool) {
      return value ? 'true' : 'false';
    }
    if (value is int || value is BigInt) {
      return value.toString();
    }
    if (value is double) {
      if (!value.isFinite) {
        throw ArgumentError('JCS does not allow non-finite numbers');
      }
      return value.toString();
    }
    if (value is Map) {
      final entries = value.entries
          .map((entry) => MapEntry(entry.key.toString(), entry.value))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return '{${entries.map((entry) => '${jsonEncode(entry.key)}:${_jcsSerialize(entry.value)}').join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_jcsSerialize).join(',')}]';
    }
    return jsonEncode(value.toString());
  }

  Uint8List _sha256(Uint8List input) => SHA256Digest().process(input);

  String _base64UrlNoPadding(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  Uint8List _compressEcPoint(Uint8List x, Uint8List y) {
    final prefix = (y.last & 1) == 0 ? 0x02 : 0x03;
    return Uint8List.fromList(<int>[prefix, ...x]);
  }

  Uint8List _toUnsignedFixed(BigInt value, int size) {
    final bytes = _encodeBigInt(value);
    if (bytes.length == size) {
      return bytes;
    }
    if (bytes.length == size + 1 && bytes.first == 0) {
      return Uint8List.fromList(bytes.sublist(1));
    }
    if (bytes.length > size) {
      return Uint8List.fromList(bytes.sublist(bytes.length - size));
    }
    return Uint8List.fromList(
      <int>[...List<int>.filled(size - bytes.length, 0), ...bytes],
    );
  }

  Uint8List _encodeBigInt(BigInt value) {
    if (value == BigInt.zero) {
      return Uint8List.fromList(<int>[0]);
    }
    final result = <int>[];
    var current = value;
    while (current > BigInt.zero) {
      result.insert(0, (current & BigInt.from(0xff)).toInt());
      current = current >> 8;
    }
    if (result.isNotEmpty && result.first >= 0x80) {
      result.insert(0, 0);
    }
    return Uint8List.fromList(result);
  }

  BigInt _decodeBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  String _formatUtc(DateTime dateTime) {
    final utc = dateTime.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
  }
}
