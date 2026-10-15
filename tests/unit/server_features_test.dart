import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/presentation/server_features/backend_capabilities_provider.dart';
import 'package:awiki_me/src/presentation/server_features/server_features_page.dart';
import 'test_support.dart';

void main() {
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
      expect(find.text('此服务器暂不支持'), findsOneWidget);
      expect(find.textContaining('最近确认'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
