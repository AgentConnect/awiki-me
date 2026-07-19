import 'package:awiki_me/src/domain/entities/remote_push_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemotePushEvent', () {
    test('normalizes Android notification-open payload', () {
      final event = RemotePushEvent.fromPlatform(<String, Object?>{
        'delivery_id': 'delivery-1',
        'kind': 'notification_opened',
        'received_at_ms': 1721376000123,
        'payload': <Object?, Object?>{
          'title': 'AWiki',
          'extraMap': '{"eid":"notify_1","thread":"thread_1"}',
        },
      });

      expect(event.kind, RemotePushEventKind.notificationOpened);
      expect(event.receivedAt.isUtc, isTrue);
      expect(
        event.receivedAt,
        DateTime.fromMillisecondsSinceEpoch(1721376000123, isUtc: true),
      );
      expect(event.payload['title'], 'AWiki');
      expect(event.payload['extraMap'], <String, Object?>{
        'eid': 'notify_1',
        'thread': 'thread_1',
      });
    });

    test('keeps malformed extraMap as provider data', () {
      final event = RemotePushEvent.fromPlatform(<String, Object?>{
        'delivery_id': 'delivery-2',
        'kind': 'notification_received',
        'received_at_ms': 1721376000123,
        'payload': <String, Object?>{'extraMap': '{not-json'},
      });

      expect(event.payload['extraMap'], '{not-json');
    });

    test('normalizes nested platform maps and lists', () {
      final event = RemotePushEvent.fromPlatform(<String, Object?>{
        'delivery_id': 'delivery-3',
        'kind': 'message_received',
        'received_at_ms': 1721376000123,
        'payload': <Object?, Object?>{
          'extraMap': <Object?, Object?>{
            'flags': <Object?>[true, 2, null],
          },
        },
      });

      expect(event.payload['extraMap'], <String, Object?>{
        'flags': <Object?>[true, 2, null],
      });
    });

    test('rejects unsupported kinds and malformed payloads', () {
      expect(
        () => RemotePushEvent.fromPlatform(<String, Object?>{
          'delivery_id': 'delivery-4',
          'kind': 'unknown',
          'received_at_ms': 1,
          'payload': <String, Object?>{},
        }),
        throwsFormatException,
      );
      expect(
        () => RemotePushEvent.fromPlatform(<String, Object?>{
          'delivery_id': 'delivery-5',
          'kind': 'message_received',
          'received_at_ms': 1,
          'payload': 'not-a-map',
        }),
        throwsFormatException,
      );
    });
  });
}
