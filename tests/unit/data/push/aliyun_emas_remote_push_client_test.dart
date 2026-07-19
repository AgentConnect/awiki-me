import 'package:awiki_me/src/data/push/aliyun_emas_platform.dart';
import 'package:awiki_me/src/data/push/aliyun_emas_remote_push_client.dart';
import 'package:awiki_me/src/domain/entities/remote_push_event.dart';
import 'package:awiki_me/src/domain/services/notification_channels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AliyunEmasRemotePushClient', () {
    test('initializes once and exposes the EMAS DeviceId', () async {
      final platform = _FakeAliyunEmasPlatform(deviceId: ' device-123 ');
      final client = AliyunEmasRemotePushClient(platform: platform);

      final first = await client.initialize();
      final second = await client.initialize();

      expect(first, same(second));
      expect(first?.provider, aliyunEmasPushProvider);
      expect(first?.providerDeviceId, 'device-123');
      expect(first?.platform, 'android');
      expect(client.registration, same(first));
      expect(platform.initializeCalls, 1);
      expect(platform.createChannelCalls, 1);
      expect(platform.calls, <String>['create_channel', 'initialize']);
      expect(platform.channelId, awikiMessageNotificationChannelId);
      expect(platform.channelName, awikiMessageNotificationChannelName);
      await client.dispose();
    });

    test('delivers queued and live native events through one stream', () async {
      final platform = _FakeAliyunEmasPlatform(
        pendingEvents: <Object?>[
          _event('notification_opened', messageId: 'queued'),
        ],
      );
      final client = AliyunEmasRemotePushClient(platform: platform);
      final received = <RemotePushEvent>[];
      final subscription = client.events.listen(received.add);

      await client.initialize();
      await platform.emit(<Object?>[
        _event('message_received', messageId: 'live'),
      ]);

      expect(received.map((event) => event.kind), <RemotePushEventKind>[
        RemotePushEventKind.notificationOpened,
        RemotePushEventKind.messageReceived,
      ]);
      expect(received[0].payload['msgId'], 'queued');
      expect(received[1].payload['msgId'], 'live');
      expect(client.pendingEvents, hasLength(2));
      final queued = client.pendingEvents.firstWhere(
        (event) => event.payload['msgId'] == 'queued',
      );
      await client.acknowledgePendingEvents(<String>[queued.deliveryId]);
      expect(platform.acknowledgedDeliveryIds, <String>{queued.deliveryId});
      expect(
        client.pendingEvents.map((event) => event.payload['msgId']),
        <String>['live'],
      );
      await subscription.cancel();
      await client.dispose();
    });

    test('bounds replay events and removes live notification text', () async {
      final platform = _FakeAliyunEmasPlatform();
      final client = AliyunEmasRemotePushClient(platform: platform);
      await client.initialize();

      for (var index = 0; index < 40; index += 1) {
        await platform.emit(<Object?>[
          <String, Object?>{
            'delivery_id': 'delivery-$index',
            'kind': 'message_received',
            'received_at_ms': DateTime.now().millisecondsSinceEpoch,
            'payload': <String, Object?>{
              'msgId': 'message-$index',
              'content': 'must not be retained',
              'traceInfo': 'must not be retained',
            },
          },
        ]);
      }

      final pending = client.pendingEvents;
      expect(pending, hasLength(32));
      expect(pending.first.payload, <String, Object?>{'msgId': 'message-8'});
      expect(pending.last.payload, <String, Object?>{'msgId': 'message-39'});
      await client.dispose();
    });

    test(
      'retries initialization after a transient registration error',
      () async {
        final platform = _FakeAliyunEmasPlatform(
          initializeResults: <Map<dynamic, dynamic>>[
            <dynamic, dynamic>{'code': 'network_error'},
            <dynamic, dynamic>{'code': '10000'},
          ],
        );
        final client = AliyunEmasRemotePushClient(platform: platform);

        await expectLater(
          client.initialize(),
          throwsA(isA<RemotePushInitializationException>()),
        );
        expect((await client.initialize())?.providerDeviceId, 'device-123');
        expect(platform.initializeCalls, 2);
        await client.dispose();
      },
    );

    test('does not re-emit unacknowledged native events on retry', () async {
      final platform = _FakeAliyunEmasPlatform(
        initializeResults: <Map<dynamic, dynamic>>[
          <dynamic, dynamic>{'code': 'network_error'},
          <dynamic, dynamic>{'code': '10000'},
        ],
        pendingEvents: <Object?>[
          _event('notification_opened', messageId: 'queued'),
        ],
      );
      final client = AliyunEmasRemotePushClient(platform: platform);
      final received = <RemotePushEvent>[];
      final subscription = client.events.listen(received.add);

      await expectLater(
        client.initialize(),
        throwsA(isA<RemotePushInitializationException>()),
      );
      await client.initialize();

      expect(received, hasLength(1));
      expect(received.single.payload['msgId'], 'queued');
      expect(client.pendingEvents, hasLength(1));
      await subscription.cancel();
      await client.dispose();
    });

    test(
      'accepts SDK automatic retry success as registration change',
      () async {
        final platform = _FakeAliyunEmasPlatform(
          initializeResult: <dynamic, dynamic>{'code': 'network_error'},
          deviceId: 'device-after-retry',
        );
        final client = AliyunEmasRemotePushClient(platform: platform);

        await expectLater(
          client.initialize(),
          throwsA(isA<RemotePushInitializationException>()),
        );
        await platform.emit(<Object?>[
          <String, Object?>{
            'delivery_id': 'registration-delivery',
            'kind': 'registration_changed',
            'received_at_ms': DateTime.now().millisecondsSinceEpoch,
            'payload': <String, Object?>{},
          },
        ]);

        expect(client.registration?.providerDeviceId, 'device-after-retry');
        await client.dispose();
      },
    );

    test('stays disabled when native Android config is absent', () async {
      final platform = _FakeAliyunEmasPlatform(configured: false);
      final client = AliyunEmasRemotePushClient(platform: platform);

      expect(await client.initialize(), isNull);
      expect(platform.initializeCalls, 0);
      expect(platform.createChannelCalls, 0);
      await client.dispose();
    });

    test(
      'surfaces SDK registration failures without exposing config',
      () async {
        final platform = _FakeAliyunEmasPlatform(
          initializeResult: <dynamic, dynamic>{
            'code': '304',
            'errorMsg': 'INVALID_PACKAGE',
          },
        );
        final client = AliyunEmasRemotePushClient(platform: platform);

        await expectLater(
          client.initialize(),
          throwsA(
            isA<RemotePushInitializationException>()
                .having((error) => error.operation, 'operation', 'initialize')
                .having((error) => error.code, 'code', '304')
                .having((error) => error.message, 'message', 'INVALID_PACKAGE'),
          ),
        );
        await client.dispose();
      },
    );

    test('rejects an empty DeviceId after successful registration', () async {
      final platform = _FakeAliyunEmasPlatform(deviceId: '  ');
      final client = AliyunEmasRemotePushClient(platform: platform);

      await expectLater(
        client.initialize(),
        throwsA(
          isA<RemotePushInitializationException>()
              .having((error) => error.operation, 'operation', 'get_device_id')
              .having((error) => error.code, 'code', 'empty_device_id'),
        ),
      );
      await client.dispose();
    });

    test('surfaces notification channel creation failures', () async {
      final platform = _FakeAliyunEmasPlatform(
        channelResult: <dynamic, dynamic>{
          'code': 'channel_failed',
          'errorMsg': 'channel unavailable',
        },
      );
      final client = AliyunEmasRemotePushClient(platform: platform);

      await expectLater(
        client.initialize(),
        throwsA(
          isA<RemotePushInitializationException>()
              .having(
                (error) => error.operation,
                'operation',
                'create_notification_channel',
              )
              .having((error) => error.code, 'code', 'channel_failed'),
        ),
      );
      expect(platform.initializeCalls, 0);
      await client.dispose();
    });
  });
}

Map<String, Object?> _event(String kind, {required String messageId}) {
  return <String, Object?>{
    'delivery_id': 'delivery-$messageId',
    'kind': kind,
    'received_at_ms': DateTime.now().millisecondsSinceEpoch,
    'payload': <String, Object?>{'msgId': messageId},
  };
}

class _FakeAliyunEmasPlatform implements AliyunEmasPlatform {
  _FakeAliyunEmasPlatform({
    this.configured = true,
    this.deviceId = 'device-123',
    this.initializeResult = const <dynamic, dynamic>{'code': '10000'},
    this.initializeResults,
    this.channelResult = const <dynamic, dynamic>{'code': '10000'},
    this.pendingEvents = const <Object?>[],
  });

  final bool configured;
  final String deviceId;
  final Map<dynamic, dynamic> initializeResult;
  final List<Map<dynamic, dynamic>>? initializeResults;
  final Map<dynamic, dynamic> channelResult;
  final List<Object?> pendingEvents;
  RemotePushPlatformEventHandler? _handler;
  int initializeCalls = 0;
  int createChannelCalls = 0;
  final List<String> calls = <String>[];
  String? channelId;
  String? channelName;
  Set<String> acknowledgedDeliveryIds = <String>{};

  @override
  Future<void> acknowledgePendingEvents(Iterable<String> deliveryIds) async {
    acknowledgedDeliveryIds = deliveryIds.toSet();
  }

  @override
  Future<Map<dynamic, dynamic>> createNotificationChannel({
    required String id,
    required String name,
    required String description,
  }) async {
    createChannelCalls += 1;
    calls.add('create_channel');
    channelId = id;
    channelName = name;
    return channelResult;
  }

  @override
  Future<void> dispose() async {
    _handler = null;
  }

  @override
  Future<List<Object?>> loadPendingEvents() async => pendingEvents;

  Future<void> emit(List<Object?> events) async {
    await _handler?.call(events);
  }

  @override
  Future<String> getDeviceId() async => deviceId;

  @override
  Future<Map<dynamic, dynamic>> initialize() async {
    initializeCalls += 1;
    calls.add('initialize');
    final results = initializeResults;
    if (results != null && initializeCalls <= results.length) {
      return results[initializeCalls - 1];
    }
    return initializeResult;
  }

  @override
  Future<bool> isConfigured() async => configured;

  @override
  Future<void> setEventHandler(RemotePushPlatformEventHandler? handler) async {
    _handler = handler;
  }
}
