// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:awiki_me/src/data/push/aliyun_emas_platform.dart';
import 'package:awiki_me/src/data/push/aliyun_emas_remote_push_client.dart';
import 'package:awiki_me/src/domain/entities/remote_push_event.dart';
import 'package:awiki_me/src/domain/services/notification_channels.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'AWiki Me',
      packageName: 'ai.awiki.awikime',
      version: '0.1.22',
      buildNumber: '32',
      buildSignature: '',
    );
  });

  group('AliyunEmasRemotePushClient', () {
    test('initializes once and exposes the EMAS DeviceId', () async {
      final platform = _FakeAliyunEmasPlatform(
        appId: ' 12345678 ',
        deviceId: ' device-123 ',
      );
      final client = AliyunEmasRemotePushClient(platform: platform);

      final first = await client.initialize();
      final second = await client.initialize();

      expect(first, same(second));
      expect(first?.provider, aliyunEmasPushProvider);
      expect(first?.providerDeviceId, 'device-123');
      expect(first?.platform, 'android');
      expect(first?.clientProduct, 'awiki-me');
      expect(first?.clientVersion, '0.1.22+32');
      expect(first?.capabilities, const <String>['awiki.agent.message.v1']);
      expect(first?.appId, '12345678');
      expect(first?.logicalDeviceId, isNull);
      expect(client.registration, same(first));
      expect(platform.initializeCalls, 1);
      expect(platform.createChannelCalls, 2);
      expect(platform.calls, <String>[
        'create_channel',
        'create_channel',
        'initialize',
      ]);
      expect(platform.channelIds, <String>[
        awikiMessageNotificationChannelId,
        awikiStructuredNormalNotificationChannelId,
      ]);
      expect(platform.channelNames, <String>[
        awikiMessageNotificationChannelName,
        awikiStructuredNormalNotificationChannelName,
      ]);
      await client.dispose();
    });

    test('reports an iOS registration for the shared native bridge', () async {
      final platform = _FakeAliyunEmasPlatform(deviceId: 'ios-device-123');
      final client = AliyunEmasRemotePushClient(
        platform: platform,
        clientPlatform: 'ios',
      );

      final registration = await client.initialize();

      expect(registration?.provider, aliyunEmasPushProvider);
      expect(registration?.providerDeviceId, 'ios-device-123');
      expect(registration?.platform, 'ios');
      expect(registration?.appId, isNull);
      expect(platform.getAppIdCalls, 0);
      await client.dispose();
    });

    test(
      'uses a header-safe version without a trailing build separator',
      () async {
        final client = AliyunEmasRemotePushClient(
          platform: _FakeAliyunEmasPlatform(),
          packageInfoLoader: () async => PackageInfo(
            appName: 'AWiki Me',
            packageName: 'ai.awiki.awikime',
            version: '0.1.22',
            buildNumber: '',
            buildSignature: '',
          ),
        );

        final registration = await client.initialize();

        expect(registration?.clientVersion, '0.1.22');
        await client.dispose();
      },
    );

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
      'forwards target fences and retains intercepted notice metadata',
      () async {
        final platform = _FakeAliyunEmasPlatform();
        final client = AliyunEmasRemotePushClient(platform: platform);
        await client.initialize();

        await client.setActiveNotificationTargetReference(
          'target_AAAAAAAAAAAAAAAAAAAAAAAA',
        );
        await platform.emit(<Object?>[
          <String, Object?>{
            'delivery_id': 'delivery-intercepted',
            'kind': 'notification_received_in_app',
            'received_at_ms': DateTime.now().millisecondsSinceEpoch,
            'payload': <String, Object?>{
              'title': 'must not be retained',
              'summary': 'must not be retained',
              'extraMap': <String, Object?>{
                'ty': 'group_message',
                'ts': 'target_AAAAAAAAAAAAAAAAAAAAAAAA',
                'unsafe': 'must not be retained',
              },
            },
          },
        ]);

        expect(
          platform.activeTargetReference,
          'target_AAAAAAAAAAAAAAAAAAAAAAAA',
        );
        expect(
          client.pendingEvents.single.kind,
          RemotePushEventKind.notificationReceivedInApp,
        );
        expect(client.pendingEvents.single.payload, <String, Object?>{
          'extraMap': <String, Object?>{
            'ty': 'group_message',
            'ts': 'target_AAAAAAAAAAAAAAAAAAAAAAAA',
          },
        });

        await client.setActiveNotificationTargetReference(null);
        expect(platform.activeTargetReference, isNull);
        await client.dispose();
      },
    );

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
        expect(client.registration?.appId, '12345678');
        await client.dispose();
      },
    );

    test('preserves the AppKey when registration changes', () async {
      final platform = _FakeAliyunEmasPlatform(
        appId: '12345678',
        deviceId: 'device-before-refresh',
      );
      final client = AliyunEmasRemotePushClient(platform: platform);

      await client.initialize();
      expect(platform.getAppIdCalls, 1);

      platform
        ..appId = 'unexpected-replacement'
        ..deviceId = 'device-after-refresh';
      await platform.emit(<Object?>[
        <String, Object?>{
          'delivery_id': 'registration-refresh-delivery',
          'kind': 'registration_changed',
          'received_at_ms': DateTime.now().millisecondsSinceEpoch,
          'payload': <String, Object?>{},
        },
      ]);

      expect(client.registration?.providerDeviceId, 'device-after-refresh');
      expect(client.registration?.appId, '12345678');
      expect(platform.getAppIdCalls, 1);
      await client.dispose();
    });

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

    test('rejects an empty Android AppKey after registration', () async {
      final platform = _FakeAliyunEmasPlatform(appId: '  ');
      final client = AliyunEmasRemotePushClient(platform: platform);

      await expectLater(
        client.initialize(),
        throwsA(
          isA<RemotePushInitializationException>()
              .having((error) => error.operation, 'operation', 'get_app_id')
              .having((error) => error.code, 'code', 'empty_app_id'),
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

    test(
      'fails closed when the structured normal channel is unavailable',
      () async {
        final platform = _FakeAliyunEmasPlatform(
          channelResults: <Map<dynamic, dynamic>>[
            <dynamic, dynamic>{'code': '10000'},
            <dynamic, dynamic>{
              'code': 'channel_failed',
              'errorMsg': 'structured channel unavailable',
            },
          ],
        );
        final client = AliyunEmasRemotePushClient(platform: platform);

        await expectLater(
          client.initialize(),
          throwsA(
            isA<RemotePushInitializationException>()
                .having(
                  (error) => error.operation,
                  'operation',
                  'create_structured_normal_notification_channel',
                )
                .having((error) => error.code, 'code', 'channel_failed'),
          ),
        );
        expect(platform.initializeCalls, 0);
        await client.dispose();
      },
    );
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
    this.appId = '12345678',
    this.deviceId = 'device-123',
    this.initializeResult = const <dynamic, dynamic>{'code': '10000'},
    this.initializeResults,
    this.channelResult = const <dynamic, dynamic>{'code': '10000'},
    this.channelResults,
    this.pendingEvents = const <Object?>[],
  });

  final bool configured;
  String appId;
  String deviceId;
  final Map<dynamic, dynamic> initializeResult;
  final List<Map<dynamic, dynamic>>? initializeResults;
  final Map<dynamic, dynamic> channelResult;
  final List<Map<dynamic, dynamic>>? channelResults;
  final List<Object?> pendingEvents;
  RemotePushPlatformEventHandler? _handler;
  int initializeCalls = 0;
  int createChannelCalls = 0;
  int getAppIdCalls = 0;
  final List<String> calls = <String>[];
  final List<String> channelIds = <String>[];
  final List<String> channelNames = <String>[];
  Set<String> acknowledgedDeliveryIds = <String>{};
  String? activeTargetReference;

  @override
  Future<void> acknowledgePendingEvents(Iterable<String> deliveryIds) async {
    acknowledgedDeliveryIds = deliveryIds.toSet();
  }

  @override
  Future<void> setActiveNotificationTargetReference(
    String? targetReference,
  ) async {
    activeTargetReference = targetReference;
  }

  @override
  Future<Map<dynamic, dynamic>> createNotificationChannel({
    required String id,
    required String name,
    required String description,
  }) async {
    createChannelCalls += 1;
    calls.add('create_channel');
    channelIds.add(id);
    channelNames.add(name);
    final results = channelResults;
    if (results != null && createChannelCalls <= results.length) {
      return results[createChannelCalls - 1];
    }
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
  Future<String> getAppId() async {
    getAppIdCalls += 1;
    return appId;
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
