import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:awiki_me/src/presentation/shared/tenant_management_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('设置页不展示当前没有真实 SDK 能力的凭证导出入口', (tester) async {
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

    expect(find.text('导出身份凭证'), findsNothing);
    expect(gateway.exportCalls, 0);
  });

  testWidgets('设置页未登录时隐藏凭证导出并禁用删除入口', (tester) async {
    final gateway = FakeAwikiGateway();

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const SettingsPage(), gateway: gateway),
    );

    expect(find.text('当前暂无可导出的登录凭证'), findsNothing);
    expect(find.text('退出并删除当前登录凭证'), findsOneWidget);

    await tester.tap(find.text('退出并删除当前凭证'));
    await tester.pump();

    expect(gateway.exportCalls, 0);
    expect(gateway.deleteLocalCredentialCalls, 0);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });

  testWidgets('桌面 272px 设置栏完整显示真实设置项且不溢出', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    const session = SessionIdentity(
      did: 'did:test:settings-sidebar',
      credentialName: 'settings-sidebar-credential',
      displayName: 'Settings User',
      handle: 'settings-user',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 272,
            height: 900,
            child: SettingsPage(embedded: true),
          ),
        ),
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('settings-tenant-row')), findsNothing);
    expect(find.byType(TenantManagementDialog), findsNothing);
    expect(find.byKey(const Key('settings-general-section')), findsOneWidget);
    expect(find.byKey(const Key('settings-session-section')), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(
      find.byKey(const Key('settings-expanded-list-header')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('settings-expanded-list-header')))
          .height,
      56,
    );
    final sectionSurface = find
        .descendant(
          of: find.byKey(const Key('settings-general-section')),
          matching: find.byType(DecoratedBox),
        )
        .first;
    expect(tester.getSize(sectionSurface).width, greaterThanOrEqualTo(256));
  });

  testWidgets('紧凑设置页使用单层窄边距扩大设置行宽度', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(393, 852));

    await tester.pumpWidget(buildLocalizedTestApp(home: const SettingsPage()));
    await tester.pumpAndSettle();

    final sectionSurface = find
        .descendant(
          of: find.byKey(const Key('settings-general-section')),
          matching: find.byType(DecoratedBox),
        )
        .first;
    expect(tester.getSize(sectionSurface).width, greaterThanOrEqualTo(373));
    expect(tester.takeException(), isNull);
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

  testWidgets('Mac 嵌入式设置页退出登录后不会关闭根页面', (tester) async {
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
        home: const SettingsPage(embedded: true),
        gateway: gateway,
        session: session,
      ),
    );

    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录').last);
    await tester.pumpAndSettle();

    expect(gateway.logoutCalls, 1);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('Mac 嵌入式设置页退出并删除凭证后不会关闭根页面', (tester) async {
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
        home: const SettingsPage(embedded: true),
        gateway: gateway,
        session: session,
      ),
    );

    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.text('退出并删除当前凭证'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出并删除'));
    await tester.pumpAndSettle();

    expect(gateway.deleteLocalCredentialCalls, 1);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('设置页隐藏更新日志下载更新和消息推送入口', (tester) async {
    await tester.pumpWidget(buildLocalizedTestApp(home: const SettingsPage()));

    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('查看更新日志'), findsNothing);
    expect(find.text('下载更新'), findsNothing);
    expect(find.text('立即更新'), findsNothing);
    expect(find.text('消息推送通知'), findsNothing);
  });

  testWidgets('设置页检查更新调用真实更新服务', (tester) async {
    final updateService = FakeUpdateService();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        updateService: updateService,
      ),
    );

    await tester.tap(find.text('检查更新'));
    await tester.pump();

    expect(updateService.checkForUpdatesCalls, 1);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    expect(
      container.read(uiFeedbackProvider)?.message.id,
      'updateAlreadyLatest',
    );
  });

  testWidgets('租户管理组件可切换到真实租户配置', (tester) async {
    final primary = defaultTenantProfile(now: DateTime.utc(2026, 7, 1));
    final custom = AppTenantProfile(
      tenantProfileId: TenantProfileId.generate(),
      storageScopeId: StorageScopeId.generate(),
      kind: AppTenantKind.custom,
      name: '新加坡测试',
      backendBaseUrl: 'https://sg.example.com',
      didHost: 'sg.example.com',
      lifecycle: AppTenantLifecycle.active,
      createdAt: DateTime.utc(2026, 7, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 7, 1).toIso8601String(),
    );
    final registry = AppTenantRegistry(
      revision: 1,
      activeTenantProfileId: primary.tenantProfileId,
      tenants: <AppTenantProfile>[primary, custom],
    );
    late StateSetter refresh;
    final actions = FakeAppTenantActions(initialRegistry: registry)
      ..onChanged = () => refresh(() {});

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          refresh = setState;
          return buildLocalizedTestApp(
            home: const TenantManagementDialog(),
            providerOverrides: <Override>[
              appTenantRegistryProvider.overrideWithValue(actions.registry),
              activeAppTenantProvider.overrideWithValue(
                actions.registry.activeTenant,
              ),
              appTenantActionsProvider.overrideWithValue(actions),
            ],
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('租户'), findsOneWidget);
    expect(find.textContaining('AWiki'), findsWidgets);
    expect(find.byType(TenantManagementDialog), findsOneWidget);
    expect(
      find.byKey(const Key('tenant-management-create-button')),
      findsOneWidget,
    );
    expect(find.text('新加坡测试'), findsOneWidget);

    await tester.tap(find.byKey(Key('settings-tenant-option:${custom.id}')));
    await tester.pumpAndSettle();

    expect(actions.useTenantCalls, 1);
    expect(actions.registry.activeTenant.id, custom.id);
  });

  testWidgets('租户管理组件可新建编辑删除并保留本地数据保护', (tester) async {
    final primary = defaultTenantProfile(now: DateTime.utc(2026, 7, 1));
    final custom = AppTenantProfile(
      tenantProfileId: TenantProfileId.generate(),
      storageScopeId: StorageScopeId.generate(),
      kind: AppTenantKind.custom,
      name: '新加坡测试',
      backendBaseUrl: 'https://sg.example.com',
      didHost: 'sg.example.com',
      lifecycle: AppTenantLifecycle.active,
      createdAt: DateTime.utc(2026, 7, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 7, 1).toIso8601String(),
    );
    final registry = AppTenantRegistry(
      revision: 1,
      activeTenantProfileId: primary.tenantProfileId,
      tenants: <AppTenantProfile>[primary, custom],
    );
    late StateSetter refresh;
    final actions = FakeAppTenantActions(initialRegistry: registry)
      ..tenantsWithData.add(custom.id)
      ..onChanged = () => refresh(() {});

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          refresh = setState;
          return buildLocalizedTestApp(
            home: const TenantManagementDialog(),
            providerOverrides: <Override>[
              appTenantRegistryProvider.overrideWithValue(actions.registry),
              activeAppTenantProvider.overrideWithValue(
                actions.registry.activeTenant,
              ),
              appTenantActionsProvider.overrideWithValue(actions),
            ],
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TenantManagementDialog), findsOneWidget);
    expect(find.byTooltip('默认 AWiki 租户不能编辑。接入其他后端请添加租户配置。'), findsOneWidget);
    expect(find.byTooltip('默认 AWiki 租户不能删除。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tenant-management-create-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('tenant-name-field')),
        matching: find.byType(CupertinoTextField),
      ),
      '东京测试',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('tenant-backend-field')),
        matching: find.byType(CupertinoTextField),
      ),
      'https://tokyo.example.com/',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('tenant-did-host-field')),
        matching: find.byType(CupertinoTextField),
      ),
      'tokyo.example.com',
    );
    await tester.tap(find.byKey(const Key('tenant-form-submit-button')));
    await tester.pumpAndSettle();

    expect(actions.createTenantCalls, 1);
    expect(actions.useTenantCalls, 0);
    expect(actions.registry.activeTenant.id, primary.id);
    expect(find.text('东京测试'), findsOneWidget);

    final customRow = find.byKey(Key('settings-tenant-option:${custom.id}'));
    await tester.tap(
      find.descendant(of: customRow, matching: find.byTooltip('编辑租户')),
    );
    await tester.pumpAndSettle();

    expect(find.text('这个租户已经有本地数据，只能修改名称，不能修改后端地址或 DID Host。'), findsOneWidget);
    final nameField = find.descendant(
      of: find.byKey(const Key('tenant-name-field')),
      matching: find.byType(CupertinoTextField),
    );
    final backendField = find.descendant(
      of: find.byKey(const Key('tenant-backend-field')),
      matching: find.byType(CupertinoTextField),
    );
    final didHostField = find.descendant(
      of: find.byKey(const Key('tenant-did-host-field')),
      matching: find.byType(CupertinoTextField),
    );
    expect(tester.widget<CupertinoTextField>(nameField).enabled, isTrue);
    expect(tester.widget<CupertinoTextField>(backendField).enabled, isFalse);
    expect(tester.widget<CupertinoTextField>(didHostField).enabled, isFalse);

    await tester.enterText(nameField, '新加坡归档');
    await tester.tap(find.byKey(const Key('tenant-form-submit-button')));
    await tester.pumpAndSettle();

    expect(actions.updateTenantCalls, 1);
    expect(find.text('新加坡归档'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(Key('settings-tenant-option:${custom.id}')),
        matching: find.byTooltip('删除'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('删除 新加坡归档？'), findsOneWidget);
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();

    expect(actions.deleteTenantCalls, 1);
    expect(
      actions.registry.visibleTenants.any((tenant) => tenant.id == custom.id),
      isFalse,
    );
    expect(find.text('新加坡归档'), findsNothing);
  });

  testWidgets('租户管理组件不允许删除当前自定义租户', (tester) async {
    final primary = defaultTenantProfile(now: DateTime.utc(2026, 7, 1));
    final custom = AppTenantProfile(
      tenantProfileId: TenantProfileId.generate(),
      storageScopeId: StorageScopeId.generate(),
      kind: AppTenantKind.custom,
      name: '当前测试租户',
      backendBaseUrl: 'https://current.example.com',
      didHost: 'current.example.com',
      lifecycle: AppTenantLifecycle.active,
      createdAt: DateTime.utc(2026, 7, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 7, 1).toIso8601String(),
    );
    final actions = FakeAppTenantActions(
      initialRegistry: AppTenantRegistry(
        revision: 1,
        activeTenantProfileId: custom.tenantProfileId,
        tenants: <AppTenantProfile>[primary, custom],
      ),
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const TenantManagementDialog(),
        providerOverrides: <Override>[
          appTenantRegistryProvider.overrideWithValue(actions.registry),
          activeAppTenantProvider.overrideWithValue(
            actions.registry.activeTenant,
          ),
          appTenantActionsProvider.overrideWithValue(actions),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final activeRow = find.byKey(Key('settings-tenant-option:${custom.id}'));
    expect(
      find.descendant(
        of: activeRow,
        matching: find.byTooltip('请先切换到其他租户，再删除当前租户。'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: activeRow, matching: find.byTooltip('删除')),
      findsNothing,
    );
    expect(actions.deleteTenantCalls, 0);
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
