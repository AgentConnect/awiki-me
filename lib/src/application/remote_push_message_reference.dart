import 'dart:convert';

import 'package:crypto/crypto.dart';

String remotePushOpaqueMessageReference(String messageId) {
  return _remotePushOpaqueReference(
    label: 'message',
    value: messageId,
    argumentName: 'messageId',
  );
}

String remotePushOpaqueTargetReference(String ownerDid) {
  return _remotePushOpaqueReference(
    label: 'target',
    value: ownerDid,
    argumentName: 'ownerDid',
  );
}

String _remotePushOpaqueReference({
  required String label,
  required String value,
  required String argumentName,
}) {
  if (value.isEmpty ||
      value.trim() != value ||
      value.runes.length > 256 ||
      value.runes.any((rune) => rune <= 0x1f || rune == 0x7f)) {
    throw ArgumentError.value(value, argumentName, 'unsafe opaque input');
  }
  final digest = sha256.convert(<int>[
    ...utf8.encode('awiki-push-envelope-v1'),
    0,
    ...utf8.encode(label),
    0,
    ...utf8.encode(value),
  ]);
  final encoded = base64Url
      .encode(digest.bytes.take(18).toList(growable: false))
      .replaceAll('=', '');
  return '${label}_$encoded';
}
