import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_locale.dart';
import '../../app/app_services.dart';
import '../../app/app_router.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/widgets/app_widgets.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(sessionProvider).session;
    final runtime = ref.read(appRuntimeProvider.notifier);
    final localeMode = ref.watch(appLocaleModeProvider);
    final theme = context.awikiTheme;
    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: <Widget>[
            AwikiMeTopBar(
              title: l10n.settingsTitle,
              padding: EdgeInsets.zero,
              leading: TopBarActionButton(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(
                  Icons.arrow_back,
                  color: AwikiMeColors.primaryDark,
                  size: 22,
                ),
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
                    leading: const _SettingsIconBadge(icon: Icons.language),
                    onTap: () => _showLanguageSheet(context, ref, localeMode),
                  ),
                  const AppSectionDivider(),
                  AppListTile(
                    title: l10n.settingsPushNotification,
                    leading: const _SettingsIconBadge(
                      icon: Icons.notifications_none,
                    ),
                    trailing: Transform.scale(
                      scale: 0.88,
                      child: CupertinoSwitch(
                        value: true,
                        activeColor: theme.success,
                        onChanged: null,
                      ),
                    ),
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
                    leading: const _SettingsIconBadge(icon: Icons.ios_share),
                    onTap: session == null
                        ? null
                        : runtime.exportCurrentCredential,
                  ),
                  const AppSectionDivider(),
                  AppListTile(
                    title: l10n.settingsLogout,
                    subtitle: l10n.settingsLogoutSubtitle,
                    destructive: true,
                    leading: const _SettingsIconBadge(
                      icon: Icons.logout,
                      destructive: true,
                    ),
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
                    leading: const _SettingsIconBadge(
                      icon: Icons.delete_outline,
                      destructive: true,
                    ),
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

  void _showLogoutDialog(
    BuildContext context,
    AppRuntimeController runtime,
  ) {
    AppNavigator.showDialog<void>(
      context,
      (ctx) => CupertinoAlertDialog(
        title: Text(context.l10n.settingsLogoutConfirmTitle),
        content: Text(context.l10n.settingsLogoutConfirmContent),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.l10n.commonCancel),
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

class _SettingsIconBadge extends StatelessWidget {
  const _SettingsIconBadge({
    required this.icon,
    this.destructive = false,
  });

  final IconData icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return AppSurface(
      padding: EdgeInsets.zero,
      color: destructive ? const Color(0xFFFFEBEB) : theme.subtleSurface,
      radius: 12,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      child: Icon(
        icon,
        size: 20,
        color: destructive ? theme.danger : theme.primaryDark,
      ),
    );
  }
}
