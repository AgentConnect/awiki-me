import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('设置页导出身份凭证显示暂未实现普通提示', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:123',
      credentialName: 'default',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token-123',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        gateway: gateway,
        session: session,
      ),
    );

    expect(find.text('导出身份凭证'), findsOneWidget);

    await tester.tap(find.text('导出身份凭证'));
    await tester.pump();

    expect(gateway.exportCalls, 0);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    final feedback = container.read(uiFeedbackProvider);
    expect(feedback?.danger, isFalse);
    expect(feedback?.message.id, 'featureNotImplemented');
  });

  testWidgets('设置页未登录时禁用凭证导出和删除入口', (tester) async {
    final gateway = FakeAwikiGateway();

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const SettingsPage(), gateway: gateway),
    );

    expect(find.text('当前暂无可导出的登录凭证'), findsOneWidget);
    expect(find.text('退出并删除当前登录凭证'), findsOneWidget);

    await tester.tap(find.text('导出身份凭证'));
    await tester.tap(find.text('退出并删除当前凭证'));
    await tester.pump();

    expect(gateway.exportCalls, 0);
    expect(gateway.deleteLocalCredentialCalls, 0);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });

  testWidgets('设置页退出并删除当前凭证会删除本地凭证而不显示未实现错误', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:123',
      credentialName: 'default',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token-123',
    );
    gateway.localCredentials = const <SessionIdentity>[session];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        gateway: gateway,
        session: session,
      ),
    );

    expect(find.text('退出并删除当前凭证'), findsOneWidget);
    expect(find.text('删除本地凭证：default'), findsOneWidget);

    await tester.tap(find.text('退出并删除当前凭证'));
    await tester.pumpAndSettle();

    expect(find.textContaining('将退出当前登录，并删除本地凭证 "default"'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );

    await tester.tap(find.text('退出并删除'));
    await tester.pumpAndSettle();

    expect(gateway.deleteLocalCredentialCalls, 1);
    expect(gateway.logoutCalls, 0);
    expect(container.read(uiFeedbackProvider), isNull);
  });

  testWidgets('设置页隐藏更新日志下载更新和消息推送入口', (tester) async {
    await tester.pumpWidget(buildLocalizedTestApp(home: const SettingsPage()));

    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('查看更新日志'), findsNothing);
    expect(find.text('下载更新'), findsNothing);
    expect(find.text('立即更新'), findsNothing);
    expect(find.text('消息推送通知'), findsNothing);
  });

  testWidgets('设置页检查更新显示暂未实现普通提示', (tester) async {
    final updateService = FakeUpdateService();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        updateService: updateService,
      ),
    );

    await tester.tap(find.text('检查更新'));
    await tester.pump();

    expect(updateService.checkForUpdatesCalls, 0);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    final feedback = container.read(uiFeedbackProvider);
    expect(feedback?.danger, isFalse);
    expect(feedback?.message.id, 'featureNotImplemented');
  });

  testWidgets('设置页展示语言设置并支持切换选项', (tester) async {
    final localePreferenceService = FakeLocalePreferenceService();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        localeMode: AppLocaleMode.system,
        localePreferenceService: localePreferenceService,
      ),
    );

    expect(find.text('语言'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);

    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();

    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('取消'), findsNothing);

    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(find.text('English'), findsWidgets);
    expect(localePreferenceService.saveCalls, 1);
    expect(await localePreferenceService.loadMode(), AppLocaleMode.english);
  });
}
