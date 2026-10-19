import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/presentation/server_features/new_tenant_capability_summary.dart';
import 'dart:async';
import 'package:awiki_me/src/application/ports/backend_capabilities_port.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/data/services/method_channel_attachment_picker_service.dart';
import 'package:awiki_me/src/presentation/server_features/backend_capabilities_provider.dart';
import 'package:awiki_me/src/presentation/server_features/server_features_page.dart';
import 'test_support.dart';

class _ObservedCapabilities extends FakeIdentityCorePort
    implements BackendCapabilitiesObservationPort {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> watchBackendCapabilities() => updates.stream;
}

void main() {
  for (final width in [390.0, 1100.0]) {
    testWidgets(
      'capability timestamps identify independent sources at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          buildLocalizedTestApp(
            home: const ServerFeaturesPage(),
            providerOverrides: [
              backendFeaturesProvider.overrideWithValue(
                const AsyncData(
                  BackendFeatures({
                    'public': {'status': 'confirmed', 'fetched_at': 100},
                    'message': {'status': 'stale', 'fetched_at': 200},
                  }),
                ),
              ),
            ],
          ),
        );
        await tester.pump();
        expect(find.textContaining('账户与服务功能'), findsOneWidget);
        expect(find.textContaining('聊天与加密功能'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final pending in [false, true]) {
    for (final width in [390.0, 1100.0]) {
      testWidgets('新增租户摘要只在确认后显示 $pending $width', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          buildLocalizedTestApp(
            home: const NewTenantCapabilitySummary(
              child: CupertinoPageScaffold(child: Text('local history')),
            ),
            providerOverrides: [
              activeAppTenantProvider.overrideWithValue(
                defaultTenantProfile().copyWith(
                  capabilitySummaryPending: pending,
                ),
              ),
              backendFeaturesProvider.overrideWithValue(
                const AsyncData(
                  BackendFeatures({
                    'public': {
                      'status': 'confirmed',
                      'capabilities': {
                        'identity.multi_device': {'support': 'supported'},
                        'agents.managed_agents': {'support': 'supported'},
                      },
                    },
                  }),
                ),
              ),
            ],
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const Key('new-tenant-capability-summary')),
          pending ? findsOneWidget : findsNothing,
        );
        expect(find.text('local history'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 8));
        expect(
          find.byKey(const Key('new-tenant-capability-summary')),
          findsNothing,
        );
      });
    }
  }

  test('能力订阅保持旧快照并响应关闭和恢复，不等待主动刷新', () async {
    final identity = _ObservedCapabilities();
    final container = ProviderContainer(
      overrides: [identityCorePortProvider.overrideWithValue(identity)],
    );
    final subscription = container.listen(
      backendFeaturesProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await identity.updates.close();
    });
    Map<String, dynamic> source(String status, String support) => {
      'public': {
        'status': status,
        'capabilities': {
          'agents.managed_agents': {'support': support},
        },
      },
    };
    identity.updates.add(source('confirmed', 'supported'));
    await container.read(backendFeaturesFutureProvider);
    expect(container.read(agentImEnabledProvider), isTrue);
    identity.updates.add(source('stale', 'supported'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(agentImEnabledProvider), isTrue);
    identity.updates.add(source('confirmed', 'unsupported'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(agentImEnabledProvider), isFalse);
    identity.updates.add(source('confirmed', 'supported'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(agentImEnabledProvider), isTrue);
  });

  for (final status in ['confirmed', 'stale', 'unavailable', 'incompatible']) {
    test('文件选择器使用当前消息能力上限 $status', () {
      final container = ProviderContainer(
        overrides: [
          backendFeaturesProvider.overrideWithValue(
            AsyncData(
              BackendFeatures({
                'message': {
                  'status': status,
                  'capabilities': {
                    'attachments': {
                      'support': 'supported',
                      'limits': {'max_object_bytes': '4096'},
                    },
                  },
                },
              }),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final picker =
          container.read(attachmentPickerServiceProvider)
              as MethodChannelAttachmentPickerService;
      expect(
        picker.maxAttachmentSizeBytes,
        ['confirmed', 'stale'].contains(status)
            ? 4096
            : defaultMaxAttachmentSizeBytes,
      );
    });
  }
  test('服务器上限不能扩大客户端上限或使用另一个权威来源', () {
    const features = BackendFeatures({
      'public': {
        'status': 'confirmed',
        'capabilities': {
          'attachments': {
            'support': 'supported',
            'limits': {'max_object_bytes': 1},
          },
        },
      },
      'message': {
        'status': 'confirmed',
        'capabilities': {
          'attachments': {
            'support': 'supported',
            'limits': {'max_object_bytes': 9000},
          },
        },
      },
    });
    expect(
      features.boundedPositiveLimit('attachments', 'max_object_bytes', 4000),
      4000,
    );
  });
  test('能力投影隔离权威来源，未知不会当作关闭', () {
    const features = BackendFeatures({
      'public': {
        'status': 'confirmed',
        'capabilities': {
          'direct_e2ee': {'support': 'supported'},
          'identity.multi_device': {'support': 'unsupported'},
        },
      },
      'message': {
        'status': 'stale',
        'capabilities': {
          'direct': {'support': 'supported'},
        },
      },
    });
    expect(features.support('direct_e2ee'), 'unknown');
    expect(features.support('identity.multi_device'), 'unsupported');
    expect(features.supports('direct'), isTrue);
    expect(features.stale, isTrue);
  });
  for (final width in [390.0, 1100.0]) {
    for (final enabled in [false, true]) {
      testWidgets('导航按 Agent 能力显示入口 $width $enabled', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          buildLocalizedTestApp(
            home: const AppShell(),
            session: const SessionIdentity(
              did: 'did:test:capability',
              credentialName: 'capability.json',
              displayName: 'Candidate',
            ),
            providerOverrides: [
              agentImEnabledProvider.overrideWithValue(enabled),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            Key(width > 900 ? 'desktop-rail-agents' : 'compact-nav-agents'),
          ),
          enabled ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(
            Key(width > 900 ? 'desktop-rail-messages' : 'compact-nav-messages'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('服务器功能页面适配 $width 宽度', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendFeaturesProvider.overrideWithValue(
              const AsyncData(
                BackendFeatures({
                  'public': {
                    'status': 'stale',
                    'capabilities': {
                      'identity.multi_device': {'support': 'unsupported'},
                    },
                  },
                }),
              ),
            ),
          ],
          child: buildLocalizedTestApp(home: const ServerFeaturesPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('服务器功能'), findsOneWidget);
      final refresh = find.byKey(const Key('server-features-refresh'));
      final buttonRect = tester.getRect(refresh);
      final iconRect = tester.getRect(
        find.descendant(
          of: refresh,
          matching: find.byIcon(CupertinoIcons.refresh),
        ),
      );
      expect(buttonRect.contains(iconRect.topLeft), isTrue);
      expect(buttonRect.contains(iconRect.bottomRight), isTrue);
      expect(buttonRect.right, lessThanOrEqualTo(width));
      expect(find.text('此服务器暂不支持'), findsOneWidget);
      expect(find.textContaining('最近确认'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
