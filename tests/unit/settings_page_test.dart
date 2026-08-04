import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/agents/agents_page.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/settings/language_selection_page.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_me/src/presentation/shared/display_scale.dart';
import 'package:awiki_me/src/presentation/shared/tenant_management_dialog.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea;
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

    expect(find.text('当前暂无可导出的登录凭证'), findsNothing);
    expect(find.text('退出并删除当前登录凭证'), findsNothing);

    await tester.tap(find.text('导出身份凭证'));
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
      closeTo(56 * AwikiDisplayScale.layoutBaseline, 0.01),
    );
    final pageSurface = tester.widget<CupertinoPageScaffold>(
      find.byKey(const Key('settings-expanded-page-surface')),
    );
    expect(pageSurface.backgroundColor, AwikiMeColors.surface);
    final sectionSurface = find
        .descendant(
          of: find.byKey(const Key('settings-general-section')),
          matching: find.byType(DecoratedBox),
        )
        .first;
    expect(tester.getSize(sectionSurface).width, greaterThanOrEqualTo(256));
  });

  testWidgets('紧凑设置页按图1使用连续全宽列表并在首屏展示全部安全操作', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const session = SessionIdentity(
      did: 'did:test:compact-settings',
      credentialName: 'compact-settings',
      displayName: 'newhandle2',
      handle: 'newhandle2.agent-connect.cn',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const SettingsPage(), session: session),
    );
    await tester.pumpAndSettle();

    final headerRect = tester.getRect(
      find.byKey(const Key('settings-compact-header')),
    );
    final avatarRect = tester.getRect(
      find.byKey(const Key('settings-profile-avatar')),
    );
    final accountFinder = find.byKey(const Key('settings-account-group'));
    final appFinder = find.byKey(const Key('settings-app-group'));
    final securityFinder = find.byKey(const Key('settings-security-group'));
    final accountRect = tester.getRect(accountFinder);
    final appRect = tester.getRect(appFinder);
    final securityRect = tester.getRect(securityFinder);
    final profileRect = tester.getRect(
      find.byKey(const Key('settings-profile-row')),
    );
    final compactScaffold = tester.widget<CupertinoPageScaffold>(
      find.byType(CupertinoPageScaffold),
    );

    expect(compactScaffold.backgroundColor, AwikiMeColors.background);
    expect(headerRect, const Rect.fromLTWH(0, 0, 390, 64));
    expect(
      tester.getRect(find.byKey(const Key('settings-back-button'))),
      const Rect.fromLTWH(8, 10, 44, 44),
    );
    expect(profileRect, const Rect.fromLTWH(0, 64, 390, 104));
    expect(avatarRect, const Rect.fromLTWH(20, 87, 58, 58));
    expect(accountRect, const Rect.fromLTWH(0, 208, 390, 61));
    expect(appRect, const Rect.fromLTWH(0, 309, 390, 183));
    expect(securityRect, const Rect.fromLTWH(0, 532, 390, 183));

    for (final titleKey in <String>[
      'settings-account-section-title',
      'settings-app-section-title',
      'settings-security-section-title',
    ]) {
      final title = tester.widget<Text>(
        find.descendant(
          of: find.byKey(Key(titleKey)),
          matching: find.byType(Text),
        ),
      );
      expect(title.style?.fontSize, 13);
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    }
    final versionRow = find.byKey(const Key('settings-current-version-row'));
    expect(
      tester.getRect(find.byKey(const Key('settings-current-version-icon'))),
      const Rect.fromLTWH(28, 327, 24, 24),
    );
    expect(tester.getRect(find.text('当前版本')).left, closeTo(68, 0.1));
    expect(tester.getSize(versionRow).height, 60);
    expect(
      find.descendant(
        of: versionRow,
        matching: find.byIcon(CupertinoIcons.chevron_right),
      ),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const Key('settings-devices-row'))).height,
      60,
    );
    expect(find.byKey(const Key('settings-personal-agent-row')), findsNothing);
    expect(find.text('个人助理'), findsNothing);
    expect(find.text('配置个人助理的启用、暂停和 Daemon 管理'), findsNothing);
    expect(find.text('查看已授权设备并审批新设备'), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const Key('settings-check-updates-row')))
          .height,
      60,
    );
    expect(
      tester.getSize(find.byKey(const Key('settings-language-row'))).height,
      60,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('settings-export-credential-row')))
          .height,
      60,
    );
    expect(
      tester.getSize(find.byKey(const Key('settings-logout-row'))).height,
      60,
    );
    expect(
      tester.getSize(find.byKey(const Key('settings-profile-row'))).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      find.byKey(const Key('settings-danger-section-title')),
      findsNothing,
    );
    expect(find.text('导出身份凭证'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('退出并删除当前凭证'), findsOneWidget);
    expect(tester.getRect(find.text('退出并删除当前凭证')).bottom, lessThan(844));
    final securitySurface = tester.widget<ColoredBox>(
      find
          .descendant(of: securityFinder, matching: find.byType(ColoredBox))
          .first,
    );
    expect(securitySurface.color, AwikiMeColors.surface);
    expect(
      tester
          .getSize(find.byKey(const Key('settings-delete-credential-row')))
          .height,
      60,
    );
    expect(
      tester.getSize(find.byKey(const Key('settings-delete-credential-icon'))),
      const Size.square(24),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('紧凑设置页仅保留身份信息和右侧状态且不溢出', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(320, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const longCredential =
        'credential-with-an-extremely-long-name-that-must-not-overflow';
    const session = SessionIdentity(
      did: 'did:test:compact-settings-long-values',
      credentialName: longCredential,
      displayName: 'A Very Long Settings Display Name For Narrow Screens',
      handle: 'a-very-long-handle.very-long-tenant.example',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const SettingsPage(), session: session),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final profileTexts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('settings-profile-row')),
            matching: find.byType(Text),
          ),
        )
        .where((text) => text.maxLines == 1);
    expect(profileTexts, hasLength(2));
    for (final text in profileTexts) {
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    }
    final languageValue = tester.widget<Text>(
      find.byKey(const Key('settings-language-value')),
    );
    expect(languageValue.maxLines, 1);
    expect(languageValue.softWrap, isFalse);
    expect(languageValue.overflow, TextOverflow.ellipsis);

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-export-credential-row')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final exportTexts = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('settings-export-credential-row')),
        matching: find.byType(Text),
      ),
    );
    expect(exportTexts, hasLength(1));
    expect(exportTexts.single.data, '导出身份凭证');
    expect(find.textContaining(longCredential), findsNothing);
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
    expect(find.text('删除本地凭证：default'), findsNothing);

    await tester.ensureVisible(find.text('退出并删除当前凭证'));
    await tester.tap(find.text('退出并删除当前凭证'));
    await tester.pumpAndSettle();

    expect(find.text('退出 default 并删除本机凭证'), findsOneWidget);
    expect(find.text('不会注销身份或影响其他设备'), findsOneWidget);

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

    await tester.ensureVisible(find.text('退出并删除当前凭证'));
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

  testWidgets('设置页展示撤权同步状态并进入重新登录', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:revoked',
      credentialName: 'revoked',
      displayName: 'Revoked',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messageSyncCoordinatorProvider.overrideWith(
            (ref) => _FixedMessageSyncCoordinator(
              ref,
              const MessageSyncCoordinatorState(
                status: MessageSyncCoordinatorStatus.authRevoked,
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('消息同步'), findsOneWidget);
    expect(find.text('登录状态已失效或此设备已被取消授权，请重新登录。'), findsNothing);
    expect(find.text('重新登录'), findsOneWidget);

    await tester.tap(find.text('重新登录'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    expect(container.read(sessionProvider).session, isNull);
    expect(gateway.logoutCalls, 1);
  });

  testWidgets('设置页展示消息恢复进度且恢复期间不可重复触发', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        session: const SessionIdentity(
          did: 'did:test:recovering',
          credentialName: 'recovering',
          displayName: 'Recovering',
        ),
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

    expect(find.text('消息同步'), findsOneWidget);
    expect(find.text('正在恢复近期消息和当前已读状态…'), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('设置页展示可重试同步失败并调度手动重试', (tester) async {
    late _FixedMessageSyncCoordinator coordinator;
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        session: const SessionIdentity(
          did: 'did:test:retryable',
          credentialName: 'retryable',
          displayName: 'Retryable',
        ),
        providerOverrides: <Override>[
          messageSyncCoordinatorProvider.overrideWith((ref) {
            return coordinator = _FixedMessageSyncCoordinator(
              ref,
              const MessageSyncCoordinatorState(
                status: MessageSyncCoordinatorStatus.retryableFailure,
                retryableFailureVisible: true,
              ),
            );
          }),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('暂时无法同步新消息，请检查网络后重试。'), findsNothing);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();

    expect(coordinator.requestReasons, ['manual_refresh']);
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

  testWidgets('移动端租户卡片使用扁平操作按钮且无数据租户只锁定 DID Host', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
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

    final primaryCard = find.byKey(Key('settings-tenant-option:${primary.id}'));
    final customCard = find.byKey(Key('settings-tenant-option:${custom.id}'));
    expect(
      find.descendant(
        of: primaryCard,
        matching: find.byKey(Key('tenant-primary-managed:${primary.id}')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: primaryCard, matching: find.byTooltip('编辑租户')),
      findsNothing,
    );
    expect(
      find.descendant(of: primaryCard, matching: find.byTooltip('删除')),
      findsNothing,
    );
    final editVisual = find.byKey(
      Key('tenant-action-visual-edit:${custom.id}'),
    );
    final editVisualSize = tester.getSize(editVisual);
    expect(editVisualSize.width, greaterThanOrEqualTo(44));
    expect(editVisualSize.height, lessThan(40));
    expect(editVisualSize.height, lessThan(editVisualSize.width));
    expect(tester.getSize(customCard).height, lessThan(128));
    expect(
      tester.getRect(customCard).bottom - tester.getRect(editVisual).bottom,
      lessThanOrEqualTo(9),
    );

    await tester.tap(
      find.descendant(of: customCard, matching: find.byTooltip('编辑租户')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('DID Host 与租户的本地身份和存储作用域绑定，已有租户不能修改；如需更换，请添加新的租户配置。'),
      findsOneWidget,
    );
    final nameField = find.descendant(
      of: find.byKey(const Key('tenant-name-field')),
      matching: find.byType(CupertinoTextField),
    );
    final backendField = find.descendant(
      of: find.byKey(const Key('tenant-backend-field')),
      matching: find.byType(CupertinoTextField),
    );
    expect(tester.widget<CupertinoTextField>(nameField).enabled, isTrue);
    expect(tester.widget<CupertinoTextField>(backendField).enabled, isTrue);
    expect(find.byKey(const Key('tenant-did-host-field')), findsNothing);
    final didHostReadonly = find.byKey(const Key('tenant-did-host-readonly'));
    expect(didHostReadonly, findsOneWidget);
    expect(
      find.descendant(
        of: didHostReadonly,
        matching: find.text('sg.example.com'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: didHostReadonly,
        matching: find.byType(SelectionArea),
      ),
      findsOneWidget,
    );

    await tester.enterText(backendField, 'https://sg-new.example.com');
    await tester.tap(find.byKey(const Key('tenant-form-submit-button')));
    await tester.pumpAndSettle();

    expect(actions.updateTenantCalls, 1);
    final updated = actions.registry.visibleTenants.firstWhere(
      (tenant) => tenant.id == custom.id,
    );
    expect(updated.backendBaseUrl, 'https://sg-new.example.com');
    expect(updated.didHost, 'sg.example.com');
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
    final primaryRow = find.byKey(Key('settings-tenant-option:${primary.id}'));
    expect(
      find.descendant(
        of: primaryRow,
        matching: find.byKey(Key('tenant-primary-managed:${primary.id}')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: primaryRow, matching: find.byTooltip('编辑租户')),
      findsNothing,
    );
    expect(
      find.descendant(of: primaryRow, matching: find.byTooltip('删除')),
      findsNothing,
    );

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
    expect(find.text('重命名租户'), findsOneWidget);
    expect(find.text('保存名称'), findsOneWidget);
    final nameField = find.descendant(
      of: find.byKey(const Key('tenant-name-field')),
      matching: find.byType(CupertinoTextField),
    );
    expect(tester.widget<CupertinoTextField>(nameField).enabled, isTrue);
    expect(find.byKey(const Key('tenant-backend-field')), findsNothing);
    expect(find.byKey(const Key('tenant-did-host-field')), findsNothing);
    final backendReadonly = find.byKey(const Key('tenant-backend-readonly'));
    final didHostReadonly = find.byKey(const Key('tenant-did-host-readonly'));
    expect(backendReadonly, findsOneWidget);
    expect(didHostReadonly, findsOneWidget);
    expect(
      find.descendant(
        of: backendReadonly,
        matching: find.text('https://sg.example.com'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: didHostReadonly,
        matching: find.text('sg.example.com'),
      ),
      findsOneWidget,
    );

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

  testWidgets('租户数据状态检查失败时明确降级为仅重命名', (tester) async {
    final primary = defaultTenantProfile(now: DateTime.utc(2026, 7, 1));
    final custom = AppTenantProfile(
      tenantProfileId: TenantProfileId.generate(),
      storageScopeId: StorageScopeId.generate(),
      kind: AppTenantKind.custom,
      name: '待检查租户',
      backendBaseUrl: 'https://check.example.com',
      didHost: 'check.example.com',
      lifecycle: AppTenantLifecycle.active,
      createdAt: DateTime.utc(2026, 7, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 7, 1).toIso8601String(),
    );
    final actions = FakeAppTenantActions(
      initialRegistry: AppTenantRegistry(
        revision: 1,
        activeTenantProfileId: primary.tenantProfileId,
        tenants: <AppTenantProfile>[primary, custom],
      ),
    )..nextTenantHasDataError = StateError('scope check unavailable');

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

    final customRow = find.byKey(Key('settings-tenant-option:${custom.id}'));
    await tester.tap(
      find.descendant(of: customRow, matching: find.byTooltip('编辑租户')),
    );
    await tester.pumpAndSettle();

    expect(find.text('重命名租户'), findsOneWidget);
    expect(find.text('保存名称'), findsOneWidget);
    expect(
      find.text('无法确认这个租户的本地数据状态。为保护现有数据，当前只能修改名称，请稍后重试。'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tenant-name-field')), findsOneWidget);
    expect(find.byKey(const Key('tenant-backend-field')), findsNothing);
    expect(find.byKey(const Key('tenant-did-host-field')), findsNothing);
    expect(find.byKey(const Key('tenant-backend-readonly')), findsOneWidget);
    expect(find.byKey(const Key('tenant-did-host-readonly')), findsOneWidget);
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

    final primaryRow = find.byKey(Key('settings-tenant-option:${primary.id}'));
    expect(
      find.descendant(of: primaryRow, matching: find.byTooltip('使用')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: primaryRow, matching: find.byTooltip('编辑租户')),
      findsNothing,
    );
    expect(
      find.descendant(of: primaryRow, matching: find.byTooltip('删除')),
      findsNothing,
    );
    final activeRow = find.byKey(Key('settings-tenant-option:${custom.id}'));
    expect(
      find.descendant(of: activeRow, matching: find.byTooltip('编辑租户')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: activeRow, matching: find.byTooltip('删除')),
      findsNothing,
    );
    expect(actions.deleteTenantCalls, 0);
  });

  testWidgets('设置页进入独立语言页并即时保存选项', (tester) async {
    final localePreferenceService = FakeLocalePreferenceService();

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        localeMode: AppLocaleMode.system,
        localePreferenceService: localePreferenceService,
      ),
    );

    expect(find.text('语言'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-language-row')));
    await tester.pumpAndSettle();

    expect(find.byType(LanguageSelectionPage), findsOneWidget);
    expect(find.byKey(const Key('language-selection-page')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('language-selection-header'))),
      const Rect.fromLTWH(0, 0, 390, 64),
    );
    expect(
      tester.getRect(find.byKey(const Key('language-selection-back-button'))),
      const Rect.fromLTWH(8, 10, 44, 44),
    );
    expect(
      tester.getRect(find.byKey(const Key('language-selection-options'))),
      const Rect.fromLTWH(16, 88, 358, 208),
    );
    expect(
      tester.getSize(find.byKey(const Key('language-option-system'))).height,
      78,
    );
    expect(
      tester.getSize(find.byKey(const Key('language-option-zh-hans'))).height,
      64,
    );
    expect(
      tester.getSize(find.byKey(const Key('language-option-english'))).height,
      64,
    );
    expect(find.text('使用设备语言'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('取消'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('language-option-system')),
        matching: find.byKey(const Key('language-option-selected-check')),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('language-option-english')));
    await tester.pumpAndSettle();

    expect(find.text('English'), findsWidgets);
    expect(find.text('Language'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('language-option-english')),
        matching: find.byKey(const Key('language-option-selected-check')),
      ),
      findsOneWidget,
    );
    expect(localePreferenceService.saveCalls, 1);
    expect(await localePreferenceService.loadMode(), AppLocaleMode.english);

    await tester.tap(find.byKey(const Key('language-selection-back-button')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byType(LanguageSelectionPage), findsNothing);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('语言页在小屏横向和放大字体下保持可滚动且无溢出', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: LanguageSelectionPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('language-option-system'))).height,
      117,
    );
    expect(
      tester.getSize(find.byKey(const Key('language-option-english'))).height,
      96,
    );

    tester.view.physicalSize = const Size(568, 320);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('language-option-english')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('language-option-english')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Personal Agent 独立设置页可启用', (tester) async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-test',
          displayName: '运行 Daemon 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'ready',
            version: '0.5.26',
            platform: 'linux-amd64',
            diagnosticsSummary: <String, Object?>{
              'bootstrap_key_id': 'did:agent:daemon#key-3',
              'bootstrap_public_key_b64u':
                  'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
              'bootstrap_key_algorithm': 'x25519',
            },
          ),
        ),
      ];
    final identities = FakeIdentityCorePort();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const PersonalAgentSettingsPage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
          handle: 'me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          identityCorePortProvider.overrideWithValue(identities),
          agentImEnabledProvider.overrideWithValue(true),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('personal-agent-settings-page')),
      findsOneWidget,
    );
    expect(find.text('个人助理'), findsWidgets);
    expect(find.text('运行 Daemon 1'), findsWidgets);
    expect(find.text('已上报公钥'), findsOneWidget);
    expect(find.text('可启用'), findsWidgets);
    expect(find.textContaining('不会自动发送消息'), findsWidgets);
    expect(find.textContaining('不处理 E2EE 明文'), findsWidgets);

    await tester.tap(find.text('启用个人助理'));
    await tester.pumpAndSettle();

    expect(identities.lastEnsuredDaemonSubkeySelector, 'default');
    expect(control.lastBootstrapDaemonDid, 'did:agent:daemon');
    expect(control.lastBootstrapControllerDid, 'did:human:me');
    expect(
      control.lastBootstrapDaemonPublicKey?.keyId,
      'did:agent:daemon#key-3',
    );
    expect(find.textContaining('自动回复'), findsNothing);
    expect(find.textContaining('代发'), findsNothing);
  });

  testWidgets('设置页不再显示 Personal Agent 入口', (tester) async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-test',
          displayName: '运行 Daemon 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'ready',
            platform: 'linux-amd64',
            diagnosticsSummary: <String, Object?>{
              'bootstrap_key_id': 'did:agent:daemon#key-3',
              'bootstrap_public_key_b64u':
                  'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
              'bootstrap_key_algorithm': 'x25519',
            },
          ),
        ),
      ];
    final identities = FakeIdentityCorePort();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          identityCorePortProvider.overrideWithValue(identities),
          agentImEnabledProvider.overrideWithValue(false),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Personal Agent'), findsNothing);
    expect(find.text('实验功能关闭'), findsNothing);
    expect(find.text('个人助理'), findsNothing);
    expect(identities.lastEnsuredDaemonSubkeySelector, isNull);
    expect(control.lastBootstrapDaemonDid, isNull);
  });

  testWidgets('Personal Agent 设置页缺 bootstrap key 时禁用启用并提示刷新', (tester) async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-test',
          displayName: '运行 Daemon 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready', platform: 'linux-amd64'),
        ),
      ];
    final identities = FakeIdentityCorePort();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const PersonalAgentSettingsPage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          identityCorePortProvider.overrideWithValue(identities),
          agentImEnabledProvider.overrideWithValue(true),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('personal-agent-settings-page')),
      findsOneWidget,
    );
    expect(find.text('未就绪'), findsOneWidget);
    expect(find.text('等待刷新状态'), findsOneWidget);
    expect(find.textContaining('尚未上报安全 bootstrap 公钥'), findsOneWidget);

    await tester.tap(find.text('启用个人助理'));
    await tester.pumpAndSettle();

    expect(identities.lastEnsuredDaemonSubkeySelector, isNull);
    expect(control.lastBootstrapDaemonDid, isNull);
  });

  testWidgets('Personal Agent 设置页按当前 Daemon 执行撤销授权', (tester) async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon:one',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-one',
          displayName: '运行 Daemon 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'ready',
            platform: 'linux-amd64',
            diagnosticsSummary: <String, Object?>{
              'bootstrap_key_id': 'did:agent:daemon:one#key-3',
              'bootstrap_public_key_b64u':
                  'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
              'bootstrap_key_algorithm': 'x25519',
            },
          ),
        ),
        AgentSummary(
          agentDid: 'did:agent:message:one',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon:one',
          runtime: 'hermes',
          handle: 'hermes-msg-one',
          displayName: 'Hermes Personal Agent',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:daemon:two',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-two',
          displayName: '运行 Daemon 2',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'ready',
            platform: 'linux-amd64',
            diagnosticsSummary: <String, Object?>{
              'bootstrap_key_id': 'did:agent:daemon:two#key-3',
              'bootstrap_public_key_b64u':
                  'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
              'bootstrap_key_algorithm': 'x25519',
            },
          ),
        ),
        AgentSummary(
          agentDid: 'did:agent:message:two',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon:two',
          runtime: 'hermes',
          handle: 'hermes-msg-two',
          displayName: 'Hermes Personal Agent',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    final identities = FakeIdentityCorePort();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const PersonalAgentSettingsPage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
          handle: 'me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          identityCorePortProvider.overrideWithValue(identities),
          agentImEnabledProvider.overrideWithValue(true),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前运行 Daemon：运行 Daemon 1'), findsOneWidget);

    await tester.tap(find.text('运行 Daemon 2').first);
    await tester.pumpAndSettle();
    expect(find.text('当前运行 Daemon：运行 Daemon 2'), findsOneWidget);

    await tester.tap(find.text('撤销 Daemon 消息授权'));
    await tester.pumpAndSettle();
    expect(find.textContaining('签名 DID Document 更新'), findsOneWidget);

    await tester.tap(find.text('撤销授权'));
    await tester.pumpAndSettle();

    expect(control.lastRevokedPersonalAgentDaemonDid, 'did:agent:daemon:two');
    expect(control.lastRevokedPersonalAgentDid, 'did:agent:message:two');
    expect(identities.lastRevokedDaemonSubkeySelector, isNull);
  });
}

class _FixedMessageSyncCoordinator extends MessageSyncCoordinator {
  _FixedMessageSyncCoordinator(
    super.ref,
    MessageSyncCoordinatorState initialState,
  ) {
    state = initialState;
  }

  final List<String> requestReasons = <String>[];

  @override
  Future<void> requestSync(String reason, {bool immediate = false}) {
    requestReasons.add(reason);
    return Future<void>.value();
  }
}
