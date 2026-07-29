import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_locale.dart';
import '../../app/app_router.dart';
import '../../domain/entities/session_identity.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/app_update_provider.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/message_sync_coordinator_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../profile/profile_page.dart';
import '../agents/agents_page.dart';
import '../agents/agents_provider.dart';
import '../devices/devices_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/app_dialog.dart';
import '../shared/awiki_me_semantic_icon.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/app_language_menu.dart';
import '../shared/avatar_badge.dart';
import '../shared/responsive_layout.dart';
import '../shared/sidebar_workspace.dart';
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
    final messageSync = ref.watch(messageSyncCoordinatorProvider);
    final updateState = ref.watch(appUpdateProvider);
    final localeMode = ref.watch(appLocaleModeProvider);
    final personalAgentEnabled = ref.watch(agentImEnabledProvider);
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    Widget? leading(Widget icon) => responsive.usesDesktopLayout ? null : icon;
    final sections = <Widget>[
      if (!embedded && responsive.isCompact && session != null) ...<Widget>[
        _SettingsSection(
          key: const Key('settings-profile-section'),
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
                    (_) =>
                        ProfilePage(onBack: () => Navigator.of(context).pop()),
                  ),
            ),
          ],
        ),
        SizedBox(height: responsive.spacing(14)),
      ],
      if (session != null) ...<Widget>[
        _SettingsSection(
          key: const Key('settings-devices-section'),
          children: <Widget>[
            AppListTile(
              title: l10n.settingsDevices,
              subtitle: l10n.settingsDevicesSubtitle,
              leading: leading(
                const _SettingsIcon(icon: CupertinoIcons.device_phone_portrait),
              ),
              onTap: () =>
                  AppNavigator.push<void>(context, (_) => const DevicesPage()),
            ),
          ],
        ),
        SizedBox(height: responsive.spacing(14)),
      ],
      if (messageSync.status != MessageSyncCoordinatorStatus.idle) ...<Widget>[
        _SettingsSection(
          key: const Key('settings-message-sync-section'),
          children: <Widget>[
            AppListTile(
              title: l10n.messageSyncStatusTitle,
              titleKey: const ValueKey<String>('message-sync-status'),
              subtitle: _messageSyncStatusLabel(context, messageSync),
              leading: leading(
                const _SettingsIcon(role: AwikiMeIconRole.refresh),
              ),
              trailing: _messageSyncTrailing(context, messageSync),
              onTap: _messageSyncAction(
                runtime: runtime,
                sync: messageSync,
                coordinator: ref.read(
                  messageSyncCoordinatorProvider.notifier,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: responsive.spacing(14)),
      ],
      _SettingsSection(
        key: const Key('settings-personal-agent-section'),
        children: <Widget>[
          AppListTile(
            title: personalAgentEnabled
                ? l10n.personalAgentTitle
                : l10n.personalAgentExperimentDisabled,
            subtitle: personalAgentEnabled
                ? l10n.personalAgentSettingsSubtitle
                : l10n.personalAgentSettingsDisabledSubtitle,
            leading: leading(
              const _SettingsIcon(
                icon: CupertinoIcons.person_crop_circle_badge_checkmark,
              ),
            ),
            onTap: personalAgentEnabled
                ? () => AppNavigator.push<void>(
                    context,
                    (_) => const PersonalAgentSettingsPage(),
                  )
                : null,
          ),
        ],
      ),
      SizedBox(height: responsive.spacing(14)),
      _SettingsSection(
        key: const Key('settings-general-section'),
        children: <Widget>[
          AppListTile(
            title: l10n.settingsCurrentVersion,
            subtitle: _currentVersionLabel(context, updateState),
            leading: leading(
              const _SettingsIcon(icon: CupertinoIcons.info_circle),
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
            leading: leading(
              const _SettingsIcon(role: AwikiMeIconRole.refresh),
            ),
            onTap: updateState.status == AppUpdateStatus.checking
                ? null
                : () => ref
                      .read(appUpdateProvider.notifier)
                      .checkForUpdates(force: true),
          ),
          const AppSectionDivider(),
          AppListTile(
            title: l10n.settingsLanguage,
            subtitle: appLocaleModeLabel(context, localeMode),
            leading: leading(
              const _SettingsIcon(role: AwikiMeIconRole.language),
            ),
            onTap: () => showAppLanguageSheet(context, ref, localeMode),
          ),
        ],
      ),
      SizedBox(height: responsive.spacing(14)),
      _SettingsSection(
        key: const Key('settings-session-section'),
        children: <Widget>[
          AppListTile(
            title: l10n.settingsExportCredential,
            subtitle: session?.credentialName != null
                ? l10n.settingsExportCurrentCredential(session!.credentialName)
                : l10n.settingsNoCredentialToExport,
            leading: leading(
              const _SettingsIcon(icon: CupertinoIcons.archivebox),
            ),
            onTap: session == null ? null : runtime.exportCurrentCredential,
          ),
          const AppSectionDivider(),
          AppListTile(
            title: l10n.settingsLogout,
            subtitle: l10n.settingsLogoutSubtitle,
            leading: leading(const _SettingsIcon(role: AwikiMeIconRole.logout)),
            onTap: () => _showLogoutDialog(context, runtime),
          ),
          const AppSectionDivider(),
          AppListTile(
            title: l10n.settingsDeleteCredential,
            subtitle: session?.credentialName != null
                ? l10n.settingsDeleteCurrentCredential(session!.credentialName)
                : l10n.settingsDeleteCredentialFallback,
            destructive: true,
            leading: leading(
              const _SettingsIcon(
                role: AwikiMeIconRole.delete,
                destructive: true,
              ),
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
    ];

    if (embedded && responsive.usesDesktopLayout) {
      return CupertinoPageScaffold(
        key: const Key('settings-expanded-page-surface'),
        backgroundColor: theme.surface,
        child: Column(
          children: <Widget>[
            AwikiSidebarHeader(
              key: const Key('settings-expanded-list-header'),
              title: l10n.settingsTitle,
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  0,
                  responsive.spacing(10),
                  0,
                  responsive.spacing(24),
                ),
                children: sections,
              ),
            ),
          ],
        ),
      );
    }

    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: AwikiAdaptiveScaffold(
        maxWidth: 820,
        padding: EdgeInsets.zero,
        includeBottomSafeArea: true,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            0,
            responsive.spacing(14),
            0,
            responsive.spacing(24),
          ),
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.spacing(8)),
              child: AwikiMeTopBar(
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
                trailing: embedded
                    ? const SizedBox(width: 40, height: 40)
                    : null,
              ),
            ),
            SizedBox(height: responsive.spacing(10)),
            ...sections,
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

  String _messageSyncStatusLabel(
    BuildContext context,
    MessageSyncCoordinatorState state,
  ) {
    return switch (state.status) {
      MessageSyncCoordinatorStatus.idle => context.l10n.messageSyncStatusIdle,
      MessageSyncCoordinatorStatus.syncing =>
        context.l10n.messageSyncStatusSyncing,
      MessageSyncCoordinatorStatus.recoveryRequired =>
        context.l10n.messageSyncStatusRecoveryRequired,
      MessageSyncCoordinatorStatus.recovering =>
        context.l10n.messageSyncStatusRecovering,
      MessageSyncCoordinatorStatus.retryableFailure =>
        context.l10n.messageSyncStatusRetryableFailure,
      MessageSyncCoordinatorStatus.authRevoked =>
        context.l10n.messageSyncStatusAuthRevoked,
    };
  }

  Widget? _messageSyncTrailing(
    BuildContext context,
    MessageSyncCoordinatorState state,
  ) {
    return switch (state.status) {
      MessageSyncCoordinatorStatus.syncing ||
      MessageSyncCoordinatorStatus.recoveryRequired ||
      MessageSyncCoordinatorStatus.recovering =>
        const CupertinoActivityIndicator(radius: 9),
      MessageSyncCoordinatorStatus.retryableFailure => Text(
        context.l10n.messageSyncRetryAction,
        style: const TextStyle(
          color: AwikiMeColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      MessageSyncCoordinatorStatus.authRevoked => Text(
        context.l10n.messageSyncReauthenticateAction,
        style: TextStyle(
          color: context.awikiTheme.danger,
          fontWeight: FontWeight.w600,
        ),
      ),
      MessageSyncCoordinatorStatus.idle => null,
    };
  }

  VoidCallback? _messageSyncAction({
    required AppRuntimeController runtime,
    required MessageSyncCoordinatorState sync,
    required MessageSyncCoordinator coordinator,
  }) {
    return switch (sync.status) {
      MessageSyncCoordinatorStatus.retryableFailure =>
        () => coordinator.requestSync('manual_refresh', immediate: true),
      MessageSyncCoordinatorStatus.authRevoked =>
        runtime.reauthenticateAfterAuthRevoked,
      MessageSyncCoordinatorStatus.idle ||
      MessageSyncCoordinatorStatus.syncing ||
      MessageSyncCoordinatorStatus.recoveryRequired ||
      MessageSyncCoordinatorStatus.recovering => null,
    };
  }

  void _showLogoutDialog(BuildContext context, AppRuntimeController runtime) {
    AppNavigator.showDialog<void>(
      context,
      (ctx) => AppConfirmationDialog(
        title: context.l10n.settingsLogoutConfirmTitle,
        message: context.l10n.settingsLogoutConfirmContent,
        confirmLabel: context.l10n.settingsLogout,
        destructive: true,
        onConfirm: () async {
          Navigator.of(ctx).pop();
          await runtime.logout();
          if (!embedded && context.mounted) {
            Navigator.of(context).pop();
          }
        },
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
      (ctx) => AppConfirmationDialog(
        title: context.l10n.settingsDeleteCredentialConfirmTitle,
        message: context.l10n.settingsDeleteCredentialConfirmContent(
          credentialName,
        ),
        confirmLabel: context.l10n.settingsDeleteCredentialConfirmAction,
        destructive: true,
        onConfirm: () async {
          Navigator.of(ctx).pop();
          await runtime.deleteCurrentCredential();
          if (!embedded && context.mounted) {
            Navigator.of(context).pop();
          }
        },
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
  const _SettingsSection({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final radius = responsive.radius(responsive.isCompact ? 14 : 8);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.spacing(responsive.isCompact ? 10 : 8),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: theme.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Column(children: children),
        ),
      ),
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
