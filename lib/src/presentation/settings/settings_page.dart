import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_locale.dart';
import '../../app/app_router.dart';
import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/app_update_provider.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../agents/agents_page.dart';
import '../agents/agents_provider.dart';
import '../devices/devices_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/app_language_menu.dart';
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
    final personalAgentEnabled = ref.watch(agentImEnabledProvider);
    final multiDeviceEnabled = ref.watch(multiDeviceJoinEnabledProvider);
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
            if (multiDeviceEnabled && session != null) ...<Widget>[
              AppCardSection(
                padding: EdgeInsets.zero,
                child: AppListTile(
                  title: l10n.settingsDevices,
                  subtitle: l10n.settingsDevicesSubtitle,
                  onTap: () => AppNavigator.push<void>(
                    context,
                    (_) => const DevicesPage(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
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
                    subtitle: appLocaleModeLabel(context, localeMode),
                    onTap: () => showAppLanguageSheet(context, ref, localeMode),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCardSection(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  if (personalAgentEnabled)
                    AppListTile(
                      title: l10n.personalAgentTitle,
                      subtitle: l10n.personalAgentSettingsSubtitle,
                      onTap: () => AppNavigator.push<void>(
                        context,
                        (_) => const PersonalAgentSettingsPage(),
                      ),
                    )
                  else
                    AppListTile(
                      title: l10n.personalAgentExperimentDisabled,
                      subtitle: l10n.personalAgentSettingsDisabledSubtitle,
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
              if (!embedded && context.mounted) {
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
              if (!embedded && context.mounted) {
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
