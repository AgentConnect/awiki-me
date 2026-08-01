import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  const session = SessionIdentity(
    did: 'did:test:me',
    credentialName: 'default',
    displayName: 'Me',
    handle: 'me',
    jwtToken: 'token',
  );

  FakeAwikiGateway gatewayWithProfile() {
    return FakeAwikiGateway()
      ..myProfile = const UserProfile(
        did: 'did:test:me',
        nickName: 'Me',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
        handle: 'me',
      );
  }

  testWidgets('连接中时显示常驻消息服务 toast', (tester) async {
    final gateway = gatewayWithProfile();
    final realtimeGateway = FakeRealtimeGateway()
      ..setStatus(RealtimeConnectionStatus.connecting);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: session,
        realtimeGateway: realtimeGateway,
      ),
    );
    await tester.pump();

    expect(find.text('正在连接消息服务...'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));

    expect(find.text('正在连接消息服务...'), findsOneWidget);
  });

  testWidgets('连接恢复后隐藏常驻消息服务 toast', (tester) async {
    final gateway = gatewayWithProfile();
    final realtimeGateway = FakeRealtimeGateway()
      ..setStatus(RealtimeConnectionStatus.reconnecting);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: session,
        realtimeGateway: realtimeGateway,
      ),
    );
    await tester.pump();

    expect(find.text('消息连接中断，正在重连...'), findsOneWidget);

    realtimeGateway.setStatus(RealtimeConnectionStatus.connected);
    await tester.pump();

    expect(find.text('消息连接中断，正在重连...'), findsNothing);
  });

  testWidgets('连接失败时不显示持续重连 toast', (tester) async {
    final gateway = gatewayWithProfile();
    final realtimeGateway = FakeRealtimeGateway()
      ..setStatus(RealtimeConnectionStatus.failed);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: session,
        realtimeGateway: realtimeGateway,
      ),
    );
    await tester.pump();

    expect(find.text('消息连接中断，正在重连...'), findsNothing);
    expect(find.text('消息服务已断开，正在尝试恢复'), findsNothing);
  });

  testWidgets('AppShell 恢复中显示全局同步进度', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gatewayWithProfile(),
        session: session,
        providerOverrides: <Override>[
          messageSyncCoordinatorProvider.overrideWith(
            (ref) => _FixedMessageSyncCoordinator(
              ref,
              const MessageSyncCoordinatorState(
                status: MessageSyncCoordinatorStatus.recovering,
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('正在恢复近期消息和当前已读状态…'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsWidgets);
  });

  testWidgets('AppShell 持续时间阈值前显示非红色自动重试提示', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gatewayWithProfile(),
        session: session,
        providerOverrides: <Override>[
          messageSyncCoordinatorProvider.overrideWith(
            (ref) => _FixedMessageSyncCoordinator(
              ref,
              const MessageSyncCoordinatorState(
                status: MessageSyncCoordinatorStatus.retryableFailure,
                consecutiveRetryableFailures: 1,
                automaticRetryPending: true,
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('消息服务暂时不可用，正在自动重试…'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsWidgets);
  });

  testWidgets('AppShell 持续时间阈值后显示全局同步错误', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gatewayWithProfile(),
        session: session,
        providerOverrides: <Override>[
          messageSyncCoordinatorProvider.overrideWith(
            (ref) => _FixedMessageSyncCoordinator(
              ref,
              const MessageSyncCoordinatorState(
                status: MessageSyncCoordinatorStatus.retryableFailure,
                consecutiveRetryableFailures: 2,
                retryableFailureVisible: true,
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('暂时无法同步新消息，请检查网络后重试。'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
  });

  testWidgets('AppShell 单独提示已提交后的列表刷新失败', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gatewayWithProfile(),
        session: session,
        providerOverrides: <Override>[
          messageSyncCoordinatorProvider.overrideWith(
            (ref) => _FixedMessageSyncCoordinator(
              ref,
              const MessageSyncCoordinatorState(
                status: MessageSyncCoordinatorStatus.projectionRefreshFailed,
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('消息已同步，但列表刷新失败，请重试重新加载。'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
  });
}

class _FixedMessageSyncCoordinator extends MessageSyncCoordinator {
  _FixedMessageSyncCoordinator(
    super.ref,
    MessageSyncCoordinatorState initialState,
  ) {
    state = initialState;
  }
}
