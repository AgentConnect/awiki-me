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
                coordinator: ref.read(messageSyncCoordinatorProvider.notifier),
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

    if (responsive.isCompact) {
      final compactContentHeight =
          MediaQuery.sizeOf(context).height -
          MediaQuery.paddingOf(context).vertical;
      final useShortViewportMetrics = compactContentHeight < 820;
      final profileHeight = useShortViewportMetrics ? 88.0 : 104.0;
      final profileAvatarSize = useShortViewportMetrics ? 52.0 : 58.0;
      final sectionTitleHeight = useShortViewportMetrics ? 32.0 : 40.0;
      final accountRowHeight = useShortViewportMetrics ? 64.0 : 72.0;
      final appRowHeight = useShortViewportMetrics ? 52.0 : 60.0;
      final securityRowHeight = useShortViewportMetrics ? 60.0 : 68.0;
      final deleteRowHeight = useShortViewportMetrics ? 68.0 : 84.0;
      final accountRows = <Widget>[
        if (session != null)
          _QuietSettingsRow(
            key: const Key('settings-devices-row'),
            icon: CupertinoIcons.device_phone_portrait,
            iconKey: const Key('settings-devices-icon'),
            title: l10n.settingsDevices,
            subtitle: l10n.settingsDevicesSubtitle,
            height: accountRowHeight,
            onTap: () =>
                AppNavigator.push<void>(context, (_) => const DevicesPage()),
          ),
        _QuietSettingsRow(
          key: const Key('settings-personal-agent-row'),
          icon: CupertinoIcons.gear_alt,
          iconKey: const Key('settings-personal-agent-icon'),
          title: personalAgentEnabled
              ? l10n.personalAgentTitle
              : l10n.personalAgentExperimentDisabled,
          subtitle: personalAgentEnabled
              ? l10n.personalAgentSettingsSubtitle
              : l10n.personalAgentSettingsDisabledSubtitle,
          height: accountRowHeight,
          subtitleMaxLines: 1,
          onTap: personalAgentEnabled
              ? () => AppNavigator.push<void>(
                  context,
                  (_) => const PersonalAgentSettingsPage(),
                )
              : null,
        ),
        if (messageSync.status != MessageSyncCoordinatorStatus.idle)
          _QuietSettingsRow(
            key: const ValueKey<String>('message-sync-status'),
            icon: CupertinoIcons.arrow_clockwise,
            title: l10n.messageSyncStatusTitle,
            subtitle: _messageSyncStatusLabel(context, messageSync),
            trailing: _messageSyncTrailing(context, messageSync),
            height: 74,
            onTap: _messageSyncAction(
              runtime: runtime,
              sync: messageSync,
              coordinator: ref.read(messageSyncCoordinatorProvider.notifier),
            ),
          ),
      ];
      final compactRows = <Widget>[
        if (session != null) ...<Widget>[
          _QuietSettingsProfileRow(
            session: session,
            height: profileHeight,
            avatarSize: profileAvatarSize,
            onTap:
                onProfileTap ??
                () => AppNavigator.push(
                  context,
                  (_) => ProfilePage(onBack: () => Navigator.of(context).pop()),
                ),
          ),
        ],
        _QuietSettingsSectionTitle(
          l10n.settingsAccountDevicesSection,
          key: const Key('settings-account-section-title'),
          height: sectionTitleHeight,
        ),
        _FlatSettingsGroup(
          key: const Key('settings-account-group'),
          children: accountRows,
        ),
        _QuietSettingsSectionTitle(
          l10n.settingsAppSection,
          key: const Key('settings-app-section-title'),
          height: sectionTitleHeight,
        ),
        _FlatSettingsGroup(
          key: const Key('settings-app-group'),
          children: <Widget>[
            _QuietSettingsRow(
              key: const Key('settings-current-version-row'),
              icon: CupertinoIcons.info_circle,
              iconKey: const Key('settings-current-version-icon'),
              title: l10n.settingsCurrentVersion,
              trailingText: updateState.currentVersion?.version ?? '--',
              height: appRowHeight,
            ),
            _QuietSettingsRow(
              key: const Key('settings-check-updates-row'),
              icon: CupertinoIcons.arrow_up_circle,
              iconKey: const Key('settings-check-updates-icon'),
              title: l10n.settingsCheckForUpdates,
              trailingText: _updateStatusLabel(context, updateState),
              height: appRowHeight,
              onTap: updateState.status == AppUpdateStatus.checking
                  ? null
                  : () => ref
                        .read(appUpdateProvider.notifier)
                        .checkForUpdates(force: true),
            ),
            _QuietSettingsRow(
              key: const Key('settings-language-row'),
              icon: CupertinoIcons.globe,
              iconKey: const Key('settings-language-icon'),
              title: l10n.settingsLanguage,
              trailingText: appLocaleModeLabel(context, localeMode),
              height: appRowHeight,
              onTap: () => showAppLanguageSheet(context, ref, localeMode),
            ),
          ],
        ),
        _QuietSettingsSectionTitle(
          l10n.settingsSecuritySection,
          key: const Key('settings-security-section-title'),
          height: sectionTitleHeight,
        ),
        _FlatSettingsGroup(
          key: const Key('settings-security-group'),
          children: <Widget>[
            _QuietSettingsRow(
              key: const Key('settings-export-credential-row'),
              icon: CupertinoIcons.arrow_down_to_line,
              iconKey: const Key('settings-export-credential-icon'),
              title: l10n.settingsExportCredential,
              subtitle: session?.credentialName != null
                  ? l10n.settingsExportCurrentCredential(
                      session!.credentialName,
                    )
                  : l10n.settingsNoCredentialToExport,
              height: securityRowHeight,
              onTap: session == null ? null : runtime.exportCurrentCredential,
            ),
            _QuietSettingsRow(
              key: const Key('settings-logout-row'),
              icon: CupertinoIcons.square_arrow_right,
              iconKey: const Key('settings-logout-icon'),
              title: l10n.settingsLogout,
              subtitle: l10n.settingsLogoutSubtitle,
              destructive: true,
              height: securityRowHeight,
              onTap: () => _showLogoutDialog(context, runtime),
            ),
            _QuietSettingsRow(
              key: const Key('settings-delete-credential-row'),
              icon: CupertinoIcons.delete,
              iconKey: const Key('settings-delete-credential-icon'),
              title: l10n.settingsDeleteCredential,
              subtitle: session?.credentialName != null
                  ? l10n.settingsDeleteCurrentCredential(
                      session!.credentialName,
                    )
                  : l10n.settingsDeleteCredentialFallback,
              destructive: true,
              height: deleteRowHeight,
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
      return CupertinoPageScaffold(
        backgroundColor: theme.background,
        child: Column(
          children: <Widget>[
            Padding(
              key: const Key('settings-compact-header'),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: AwikiMeTopBar(
                title: l10n.settingsTitle,
                padding: const EdgeInsets.symmetric(vertical: 6),
                titleFontSize: 16,
                titleFontWeight: FontWeight.w600,
                leading: TopBarActionButton(
                  key: const Key('settings-back-button'),
                  onTap: onBack ?? () => Navigator.of(context).pop(),
                  semanticsLabel: l10n.commonBack,
                  child: Icon(
                    CupertinoIcons.chevron_left,
                    size: responsive.iconMd,
                    color: AwikiMePalette.actionBlue,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  0,
                  0,
                  0,
                  useShortViewportMetrics ? 0 : 4,
                ),
                children: compactRows,
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
        state.shouldSurfaceRetryableFailure
            ? context.l10n.messageSyncStatusRetryableFailure
            : context.l10n.messageSyncStatusRetrying,
      MessageSyncCoordinatorStatus.projectionRefreshFailed =>
        context.l10n.messageSyncStatusProjectionRefreshFailed,
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
      MessageSyncCoordinatorStatus.projectionRefreshFailed => Text(
        context.l10n.messageSyncReloadAction,
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
      MessageSyncCoordinatorStatus.projectionRefreshFailed =>
        () => coordinator.requestSync('projection_reload', immediate: true),
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
        helperMessage: context.l10n.settingsDeleteCredentialConfirmHint,
        compactTitleTextAlign: TextAlign.center,
        compactMessageTextAlign: TextAlign.center,
        compactHorizontalPadding: 24,
        compactSpacious: true,
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

class _QuietSettingsProfileRow extends StatelessWidget {
  const _QuietSettingsProfileRow({
    required this.session,
    required this.height,
    required this.avatarSize,
    required this.onTap,
  });

  final SessionIdentity session;
  final double height;
  final double avatarSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final title = _sessionProfileTitle(session);
    return AppPressable(
      key: const Key('settings-profile-row'),
      onTap: onTap,
      semanticLabel: title,
      borderRadius: BorderRadius.zero,
      child: SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: <Widget>[
                  AvatarBadge(
                    key: const Key('settings-profile-avatar'),
                    seed: title,
                    size: avatarSize,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.title,
                            fontSize: responsive.bodyMd + 1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _sessionProfileSubtitle(session),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.secondaryText,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: responsive.iconSm,
                    color: theme.tertiaryText,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 0,
              child: Container(height: 1, color: theme.border),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuietSettingsSectionTitle extends StatelessWidget {
  const _QuietSettingsSectionTitle(this.label, {super.key, this.height = 40});

  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.awikiTheme.secondaryText,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _FlatSettingsGroup extends StatelessWidget {
  const _FlatSettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index += 1) {
      rows.add(children[index]);
      rows.add(
        Container(
          key: index == children.length - 1
              ? null
              : ValueKey<String>('settings-row-divider-$index'),
          height: 1,
          margin: EdgeInsets.only(
            left: index == children.length - 1 ? 20 : 68,
            right: 20,
          ),
          color: theme.border,
        ),
      );
    }
    return ColoredBox(
      color: theme.surface,
      child: Column(children: rows),
    );
  }
}

class _QuietSettingsRow extends StatelessWidget {
  const _QuietSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.height,
    this.iconKey,
    this.subtitle,
    this.trailing,
    this.trailingText,
    this.onTap,
    this.destructive = false,
    this.subtitleMaxLines = 1,
  });

  final IconData icon;
  final Key? iconKey;
  final String title;
  final double height;
  final String? subtitle;
  final Widget? trailing;
  final String? trailingText;
  final VoidCallback? onTap;
  final bool destructive;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final subtitleValue = subtitle?.trim() ?? '';
    final trailingValue = trailingText?.trim() ?? '';
    final foreground = destructive ? theme.danger : AwikiMePalette.actionBlue;
    return AppPressable(
      onTap: onTap,
      semanticLabel: title,
      borderRadius: BorderRadius.zero,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        color: theme.surface,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox.square(
              dimension: 24,
              child: Icon(icon, key: iconKey, size: 24, color: foreground),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: destructive ? theme.danger : theme.title,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitleValue.isNotEmpty) ...<Widget>[
                    SizedBox(height: responsive.spacing(3)),
                    Text(
                      subtitleValue,
                      maxLines: subtitleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.secondaryText,
                        fontSize: 12,
                        height: 18 / 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Center(child: trailing),
              )
            else if (trailingValue.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Text(
                  trailingValue,
                  key: title == context.l10n.settingsLanguage
                      ? const Key('settings-language-value')
                      : null,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.secondaryText, fontSize: 13),
                ),
              ),
            if (onTap != null) ...<Widget>[
              SizedBox(width: responsive.spacing(5)),
              Icon(
                CupertinoIcons.chevron_right,
                size: responsive.iconSm,
                color: theme.tertiaryText,
              ),
            ],
          ],
        ),
      ),
    );
  }
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
