import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_locale.dart';
import '../../app/app_services.dart';
import '../../app/app_router.dart';
import '../../app/ui_feedback.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/app_update_provider.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../agents/agents_page.dart';
import '../agents/agents_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(sessionProvider).session;
    final runtime = ref.read(appRuntimeProvider.notifier);
    final updateState = ref.watch(appUpdateProvider);
    final localeMode = ref.watch(appLocaleModeProvider);
    final messageAgentEnabled = ref.watch(agentImEnabledProvider);
    final theme = context.awikiTheme;
    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: AwikiAdaptiveScaffold(
        maxWidth: 820,
        includeBottomSafeArea: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
          children: <Widget>[
            AwikiMeTopBar(
              title: l10n.settingsTitle,
              padding: EdgeInsets.zero,
              leading: embedded
                  ? const SizedBox.shrink()
                  : TopBarActionButton(
                      onTap: () => Navigator.of(context).pop(),
                      child: const AwikiAssetIcon(
                        assetName: 'assets/icons/icon_left.svg',
                        color: AwikiMeColors.primaryDark,
                        size: 22,
                      ),
                    ),
              trailing: embedded ? const SizedBox(width: 40, height: 40) : null,
            ),
            const SizedBox(height: 16),
            AppCardSection(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  AppListTile(
                    title: l10n.settingsCurrentVersion,
                    subtitle: _currentVersionLabel(context, updateState),
                    trailing: Text(
                      updateState.currentVersion?.version ?? '--',
                      style: TextStyle(
                        color: theme.secondaryText,
                        fontSize: context.awikiResponsive.bodySm,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const AppSectionDivider(),
                  AppListTile(
                    title: l10n.settingsCheckForUpdates,
                    subtitle: _updateStatusLabel(context, updateState),
                    onTap: () => ref
                        .read(uiFeedbackProvider.notifier)
                        .showInfo(AppMessage.featureNotImplemented()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCardSection(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  AppListTile(
                    title: l10n.settingsLanguage,
                    subtitle: _languageLabel(context, localeMode),
                    onTap: () => _showLanguageSheet(context, ref, localeMode),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCardSection(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  if (messageAgentEnabled)
                    AppListTile(
                      title: 'Message Agent',
                      subtitle: '配置消息处理 Agent：启用、暂停和撤销 Daemon 消息授权',
                      onTap: () => AppNavigator.push<void>(
                        context,
                        (_) => const MessageAgentSettingsPage(),
                      ),
                    )
                  else
                    const AppListTile(
                      title: '实验功能未开启',
                      subtitle: 'Message Agent 已关闭，不会发送 bootstrap 或授权请求',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCardSection(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  AppListTile(
                    title: l10n.settingsExportCredential,
                    subtitle: session?.credentialName != null
                        ? l10n.settingsExportCurrentCredential(
                            session!.credentialName,
                          )
                        : l10n.settingsNoCredentialToExport,
                    onTap: session == null
                        ? null
                        : runtime.exportCurrentCredential,
                  ),
                  const AppSectionDivider(),
                  AppListTile(
                    title: l10n.settingsLogout,
                    subtitle: l10n.settingsLogoutSubtitle,
                    onTap: () => _showLogoutDialog(context, runtime),
                  ),
                  const AppSectionDivider(),
                  AppListTile(
                    title: l10n.settingsDeleteCredential,
                    subtitle: session?.credentialName != null
                        ? l10n.settingsDeleteCurrentCredential(
                            session!.credentialName,
                          )
                        : l10n.settingsDeleteCredentialFallback,
                    destructive: true,
                    onTap: session == null
                        ? null
                        : () => _showDeleteCredentialDialog(
                            context,
                            runtime,
                            session.credentialName,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _languageLabel(BuildContext context, AppLocaleMode mode) {
    final l10n = context.l10n;
    switch (mode) {
      case AppLocaleMode.system:
        return l10n.settingsLanguageSystem;
      case AppLocaleMode.zhHans:
        return l10n.settingsLanguageZhHans;
      case AppLocaleMode.english:
        return l10n.settingsLanguageEnglish;
    }
  }

  String _currentVersionLabel(BuildContext context, AppUpdateState state) {
    final l10n = context.l10n;
    final current = state.currentVersion;
    if (current == null) {
      return l10n.settingsUpdateStatusLoading;
    }
    return l10n.settingsCurrentVersionValue(current.displayLabel);
  }

  String _updateStatusLabel(BuildContext context, AppUpdateState state) {
    final l10n = context.l10n;
    if (state.status == AppUpdateStatus.checking) {
      return l10n.settingsUpdateStatusChecking;
    }
    if (state.hasUpdate) {
      return l10n.settingsUpdateAvailable(state.latestManifest!.version);
    }
    if (state.status == AppUpdateStatus.error) {
      return l10n.settingsUpdateStatusFailed;
    }
    return l10n.settingsAlreadyLatestVersion;
  }

  Future<void> _showLanguageSheet(
    BuildContext context,
    WidgetRef ref,
    AppLocaleMode currentMode,
  ) {
    final l10n = context.l10n;
    return AppNavigator.showSheet<void>(
      context,
      (sheetContext) => AppDropMenu(
        title: l10n.settingsLanguage.toUpperCase(),
        items: <AppDropMenuItem>[
          _buildLanguageAction(
            ref: ref,
            mode: AppLocaleMode.system,
            currentMode: currentMode,
            label: l10n.settingsLanguageSystem,
          ),
          _buildLanguageAction(
            ref: ref,
            mode: AppLocaleMode.zhHans,
            currentMode: currentMode,
            label: l10n.settingsLanguageZhHans,
          ),
          _buildLanguageAction(
            ref: ref,
            mode: AppLocaleMode.english,
            currentMode: currentMode,
            label: l10n.settingsLanguageEnglish,
          ),
        ],
      ),
    );
  }

  AppDropMenuItem _buildLanguageAction({
    required WidgetRef ref,
    required AppLocaleMode mode,
    required AppLocaleMode currentMode,
    required String label,
  }) {
    final isSelected = currentMode == mode;
    return AppDropMenuItem(
      label: label,
      highlighted: isSelected,
      onTap: () async {
        await ref.read(localePreferenceServiceProvider).saveMode(mode);
        ref.read(appLocaleModeProvider.notifier).state = mode;
      },
    );
  }

  void _showLogoutDialog(BuildContext context, AppRuntimeController runtime) {
    AppNavigator.showDialog<void>(
      context,
      (ctx) => CupertinoAlertDialog(
        title: Text(context.l10n.settingsLogoutConfirmTitle),
        content: Text(context.l10n.settingsLogoutConfirmContent),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              context.l10n.commonCancel,
              style: TextStyle(color: context.awikiTheme.title),
            ),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(ctx).pop();
              await runtime.logout();
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Text(context.l10n.settingsLogout),
          ),
        ],
      ),
    );
  }

  void _showDeleteCredentialDialog(
    BuildContext context,
    AppRuntimeController runtime,
    String credentialName,
  ) {
    AppNavigator.showDialog<void>(
      context,
      (ctx) => CupertinoAlertDialog(
        title: Text(context.l10n.settingsDeleteCredentialConfirmTitle),
        content: Text(
          context.l10n.settingsDeleteCredentialConfirmContent(credentialName),
        ),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(ctx).pop();
              await runtime.deleteCurrentCredential();
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Text(context.l10n.settingsDeleteCredentialConfirmAction),
          ),
        ],
      ),
    );
  }
}
