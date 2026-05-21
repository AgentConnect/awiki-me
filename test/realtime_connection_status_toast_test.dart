import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
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

  testWidgets('连接中时显示常驻消息服务 toast', (tester) async {
    final realtimeGateway = FakeRealtimeGateway()
      ..setStatus(RealtimeConnectionStatus.connecting);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
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
    final realtimeGateway = FakeRealtimeGateway()
      ..setStatus(RealtimeConnectionStatus.reconnecting);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
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
    final realtimeGateway = FakeRealtimeGateway()
      ..setStatus(RealtimeConnectionStatus.failed);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        session: session,
        realtimeGateway: realtimeGateway,
      ),
    );
    await tester.pump();

    expect(find.text('消息连接中断，正在重连...'), findsNothing);
    expect(find.text('消息服务已断开，正在尝试恢复'), findsNothing);
  });
}
