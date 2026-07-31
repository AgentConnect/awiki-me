import 'dart:convert';

import 'package:crypto/crypto.dart';

String remotePushOpaqueMessageReference(String messageId) {
  if (messageId.isEmpty ||
      messageId.trim() != messageId ||
      messageId.runes.length > 256 ||
      messageId.runes.any((rune) => rune <= 0x1f || rune == 0x7f)) {
    throw ArgumentError.value(messageId, 'messageId', 'unsafe message ID');
  }
  final digest = sha256.convert(<int>[
    ...utf8.encode('awiki-push-envelope-v1'),
    0,
    ...utf8.encode('message'),
    0,
    ...utf8.encode(messageId),
  ]);
  final encoded = base64Url
      .encode(digest.bytes.take(18).toList(growable: false))
      .replaceAll('=', '');
  return 'message_$encoded';
}
