import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_locale.dart';
import '../../app/app_router.dart';
import '../../application/tenant/app_tenant.dart';
import '../../domain/entities/session_identity.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/app_update_provider.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../profile/profile_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_semantic_icon.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/app_language_menu.dart';
import '../shared/avatar_badge.dart';
import '../shared/responsive_layout.dart';
import '../shared/tenant_management_dialog.dart';
import '../shared/widgets/app_widgets.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({
    super.key,
    this.embedded = false,
    this.onBack,
    this.onProfileTap,
  });

  final bool embedded;
  final VoidCallback? onBack;
  final VoidCallback? onProfileTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(sessionProvider).session;
    final runtime = ref.read(appRuntimeProvider.notifier);
    final updateState = ref.watch(appUpdateProvider);
    final localeMode = ref.watch(appLocaleModeProvider);
    final activeTenant = ref.watch(activeAppTenantProvider);
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: AwikiAdaptiveScaffold(
        maxWidth: 820,
        includeBottomSafeArea: true,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            0,
            responsive.spacing(14),
            0,
            responsive.spacing(24),
          ),
          children: <Widget>[
            AwikiMeTopBar(
              title: l10n.settingsTitle,
              padding: EdgeInsets.zero,
              leading: embedded
                  ? const SizedBox.shrink()
                  : TopBarActionButton(
                      key: const Key('settings-back-button'),
                      onTap: onBack ?? () => Navigator.of(context).pop(),
                      child: const AwikiAssetIcon(
                        assetName: 'assets/icons/icon_left.svg',
                        color: AwikiMeColors.primaryDark,
                        size: 22,
                      ),
                    ),
              trailing: embedded ? const SizedBox(width: 40, height: 40) : null,
            ),
            SizedBox(height: responsive.spacing(10)),
            if (!embedded &&
                responsive.isCompact &&
                session != null) ...<Widget>[
              _SettingsSection(
                children: <Widget>[
                  AppListTile(
                    key: const Key('settings-profile-row'),
                    title: _sessionProfileTitle(session),
                    subtitle: _sessionProfileSubtitle(session),
                    leading: AvatarBadge(
                      seed: _sessionProfileTitle(session),
                      size: responsive.displayScaled(36),
                    ),
                    onTap:
                        onProfileTap ??
                        () => AppNavigator.push(
                          context,
                          (_) => ProfilePage(
                            onBack: () => Navigator.of(context).pop(),
                          ),
                        ),
                  ),
                ],
              ),
              SizedBox(height: responsive.spacing(14)),
            ],
            _SettingsSection(
              children: <Widget>[
                AppListTile(
                  key: const Key('settings-tenant-row'),
                  title: l10n.tenantManagementTitle,
                  subtitle:
                      '${activeTenant.name} · ${activeTenant.backendBaseUrl}',
                  leading: const _SettingsIcon(icon: CupertinoIcons.globe),
                  onTap: () => _showTenantDialog(context),
                ),
                const AppSectionDivider(),
                AppListTile(
                  title: l10n.settingsCurrentVersion,
                  subtitle: _currentVersionLabel(context, updateState),
                  leading: const _SettingsIcon(
                    icon: CupertinoIcons.info_circle,
                  ),
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
                  leading: const _SettingsIcon(role: AwikiMeIconRole.refresh),
                  onTap: updateState.status == AppUpdateStatus.checking
                      ? null
                      : () => ref
                            .read(appUpdateProvider.notifier)
                            .checkForUpdates(force: true),
                ),
              ],
            ),
            SizedBox(height: responsive.spacing(14)),
            _SettingsSection(
              children: <Widget>[
                AppListTile(
                  title: l10n.settingsLanguage,
                  subtitle: appLocaleModeLabel(context, localeMode),
                  leading: const _SettingsIcon(role: AwikiMeIconRole.language),
                  onTap: () => showAppLanguageSheet(context, ref, localeMode),
                ),
              ],
            ),
            SizedBox(height: responsive.spacing(14)),
            _SettingsSection(
              children: <Widget>[
                AppListTile(
                  title: l10n.settingsLogout,
                  subtitle: l10n.settingsLogoutSubtitle,
                  leading: const _SettingsIcon(role: AwikiMeIconRole.logout),
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
                  leading: const _SettingsIcon(
                    role: AwikiMeIconRole.delete,
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

  Future<void> _showTenantDialog(BuildContext context) {
    return showTenantManagementDialog(context);
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

String _sessionProfileTitle(SessionIdentity session) {
  final displayName = session.displayName.trim();
  if (displayName.isNotEmpty) {
    return displayName;
  }
  final handle = session.handle?.trim() ?? '';
  if (handle.isNotEmpty) {
    return handle.startsWith('@') ? handle.substring(1) : handle;
  }
  return session.credentialName.trim();
}

String _sessionProfileSubtitle(SessionIdentity session) {
  final handle = session.handle?.trim() ?? '';
  if (handle.isNotEmpty) {
    return handle.startsWith('@') ? handle : '@$handle';
  }
  return session.did;
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border.symmetric(horizontal: BorderSide(color: theme.border)),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({this.role, this.icon, this.destructive = false})
    : assert(role != null || icon != null);

  final AwikiMeIconRole? role;
  final IconData? icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final color = destructive ? theme.danger : theme.secondaryText;
    return Container(
      width: responsive.displayScaled(32),
      height: responsive.displayScaled(32),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: destructive ? theme.dangerContainer : theme.subtleSurface,
        borderRadius: BorderRadius.circular(responsive.radius(8)),
      ),
      child: role == null
          ? Icon(icon, size: responsive.iconSm, color: color)
          : AwikiMeSemanticIcon(
              role: role!,
              size: responsive.iconSm,
              color: color,
            ),
    );
  }
}
