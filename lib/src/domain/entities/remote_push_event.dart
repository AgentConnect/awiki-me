import 'dart:convert';

enum RemotePushEventKind {
  registrationChanged('registration_changed'),
  messageReceived('message_received'),
  notificationReceived('notification_received'),
  notificationReceivedInApp('notification_received_in_app'),
  notificationOpened('notification_opened'),
  notificationRemoved('notification_removed');

  const RemotePushEventKind(this.wireName);

  final String wireName;

  static RemotePushEventKind parse(String value) {
    return values.firstWhere(
      (kind) => kind.wireName == value,
      orElse: () =>
          throw FormatException('Unsupported remote push event kind: $value'),
    );
  }
}

class RemotePushEvent {
  const RemotePushEvent({
    required this.deliveryId,
    required this.kind,
    required this.payload,
    required this.receivedAt,
  });

  factory RemotePushEvent.fromPlatform(Object? raw) {
    final event = _stringKeyedMap(raw, field: 'event');
    final kindValue = event['kind'];
    if (kindValue is! String || kindValue.isEmpty) {
      throw const FormatException('Remote push event kind is missing');
    }
    final receivedAtMs = event['received_at_ms'];
    if (receivedAtMs is! num) {
      throw const FormatException('Remote push received_at_ms is missing');
    }
    final deliveryId = event['delivery_id'];
    if (deliveryId is! String || deliveryId.isEmpty) {
      throw const FormatException('Remote push delivery_id is missing');
    }
    final payload = _stringKeyedMap(event['payload'], field: 'payload');
    final extraMap = payload['extraMap'];
    if (extraMap is String && extraMap.trimLeft().startsWith('{')) {
      try {
        payload['extraMap'] = _normalizeValue(jsonDecode(extraMap));
      } on FormatException {
        // Preserve provider data when extraMap is not valid JSON.
      }
    }
    return RemotePushEvent(
      deliveryId: deliveryId,
      kind: RemotePushEventKind.parse(kindValue),
      payload: payload,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        receivedAtMs.toInt(),
        isUtc: true,
      ),
    );
  }

  final String deliveryId;
  final RemotePushEventKind kind;
  final Map<String, Object?> payload;
  final DateTime receivedAt;
}

Map<String, Object?> _stringKeyedMap(Object? raw, {required String field}) {
  if (raw is! Map) {
    throw FormatException('Remote push $field must be a map');
  }
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) {
      throw FormatException('Remote push $field contains a non-string key');
    }
    result[entry.key as String] = _normalizeValue(entry.value);
  }
  return result;
}

Object? _normalizeValue(Object? value) {
  if (value is Map) {
    return _stringKeyedMap(value, field: 'payload');
  }
  if (value is List) {
    return value.map(_normalizeValue).toList(growable: false);
  }
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  return value.toString();
}
