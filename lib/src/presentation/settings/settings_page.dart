import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_locale.dart';
import '../../app/app_router.dart';
import '../../domain/entities/session_identity.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/app_update_provider.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../profile/profile_page.dart';
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
import 'language_selection_page.dart';
import 'display_settings_page.dart';
import 'font_size_setting_row.dart';
import '../shared/display_scale.dart';
import '../shared/local_credential_delete_dialog.dart';

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
    final displayScale = ref.watch(displayScaleProvider);
    final isDesktopPlatform =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
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
      _SettingsSection(
        key: const Key('settings-general-section'),
        children: <Widget>[
          AppListTile(
            title: l10n.settingsCurrentVersion,
            leading: leading(
              const _SettingsIcon(icon: CupertinoIcons.info_circle),
            ),
            trailing: Text(
              updateState.currentVersion?.version ?? '--',
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: context.awikiResponsive.bodySm,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const AppSectionDivider(),
          AppListTile(
            key: const Key('settings-check-updates-row'),
            title: l10n.settingsCheckForUpdates,
            leading: leading(
              const _SettingsIcon(role: AwikiMeIconRole.refresh),
            ),
            trailing: Text(
              _updateStatusLabel(context, updateState),
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: context.awikiResponsive.bodySm,
                fontWeight: FontWeight.w400,
              ),
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
            leading: leading(
              const _SettingsIcon(role: AwikiMeIconRole.language),
            ),
            trailing: Text(
              appLocaleModeLabel(context, localeMode),
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: context.awikiResponsive.bodySm,
                fontWeight: FontWeight.w400,
              ),
            ),
            onTap: () => AppNavigator.push<void>(
              context,
              (_) => const LanguageSelectionPage(),
            ),
          ),
          const AppSectionDivider(),
          const FontSizeSettingRow(),
          if (isDesktopPlatform) ...<Widget>[
            const AppSectionDivider(),
            AppListTile(
              key: const Key('settings-display-row'),
              title: l10n.settingsDisplayAndWindow,
              leading: leading(
                const _SettingsIcon(icon: CupertinoIcons.textformat_size),
              ),
              trailing: Text(
                '${(displayScale * 100).round()}%',
                key: const Key('settings-display-value'),
                style: TextStyle(
                  color: theme.secondaryText,
                  fontSize: context.awikiResponsive.bodySm,
                  fontWeight: FontWeight.w400,
                ),
              ),
              onTap: () => AppNavigator.push<void>(
                context,
                (_) => const DisplaySettingsPage(),
              ),
            ),
          ],
        ],
      ),
      SizedBox(height: responsive.spacing(14)),
      _SettingsSection(
        key: const Key('settings-session-section'),
        children: <Widget>[
          AppListTile(
            title: l10n.settingsExportCredential,
            leading: leading(
              const _SettingsIcon(icon: CupertinoIcons.archivebox),
            ),
            onTap: session == null ? null : runtime.exportCurrentCredential,
          ),
          const AppSectionDivider(),
          AppListTile(
            title: l10n.settingsLogout,
            leading: leading(const _SettingsIcon(role: AwikiMeIconRole.logout)),
            onTap: () => _showLogoutDialog(context, runtime),
          ),
          const AppSectionDivider(),
          AppListTile(
            title: l10n.settingsDeleteCredential,
            destructive: true,
            leading: leading(
              const _SettingsIcon(
                role: AwikiMeIconRole.delete,
                destructive: true,
              ),
            ),
            onTap: session == null
                ? null
                : () => _showDeleteCredentialDialog(context, runtime, session),
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
      final optionRowHeight = useShortViewportMetrics ? 52.0 : 60.0;
      final accountRows = <Widget>[
        if (session != null)
          _QuietSettingsRow(
            key: const Key('settings-devices-row'),
            icon: CupertinoIcons.device_phone_portrait,
            iconKey: const Key('settings-devices-icon'),
            title: l10n.settingsDevices,
            height: optionRowHeight,
            onTap: () =>
                AppNavigator.push<void>(context, (_) => const DevicesPage()),
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
              height: optionRowHeight,
            ),
            _QuietSettingsRow(
              key: const Key('settings-check-updates-row'),
              icon: CupertinoIcons.arrow_up_circle,
              iconKey: const Key('settings-check-updates-icon'),
              title: l10n.settingsCheckForUpdates,
              trailingText: _updateStatusLabel(context, updateState),
              height: optionRowHeight,
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
              height: optionRowHeight,
              onTap: () => AppNavigator.push<void>(
                context,
                (_) => const LanguageSelectionPage(),
              ),
            ),
            FontSizeSettingRow(compact: true, height: optionRowHeight),
            if (isDesktopPlatform)
              _QuietSettingsRow(
                key: const Key('settings-display-row'),
                icon: CupertinoIcons.textformat_size,
                iconKey: const Key('settings-display-icon'),
                title: l10n.settingsDisplayAndWindow,
                trailingText: '${(displayScale * 100).round()}%',
                height: optionRowHeight,
                onTap: () => AppNavigator.push<void>(
                  context,
                  (_) => const DisplaySettingsPage(),
                ),
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
              height: optionRowHeight,
              onTap: session == null ? null : runtime.exportCurrentCredential,
            ),
            _QuietSettingsRow(
              key: const Key('settings-logout-row'),
              icon: CupertinoIcons.square_arrow_right,
              iconKey: const Key('settings-logout-icon'),
              title: l10n.settingsLogout,
              destructive: true,
              height: optionRowHeight,
              onTap: () => _showLogoutDialog(context, runtime),
            ),
            _QuietSettingsRow(
              key: const Key('settings-delete-credential-row'),
              icon: CupertinoIcons.delete,
              iconKey: const Key('settings-delete-credential-icon'),
              title: l10n.settingsDeleteCredential,
              destructive: true,
              height: optionRowHeight,
              onTap: session == null
                  ? null
                  : () =>
                        _showDeleteCredentialDialog(context, runtime, session),
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
                titleFontWeight: FontWeight.w400,
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
    SessionIdentity identity,
  ) {
    AppNavigator.showDialog<void>(
      context,
      (ctx) => LocalCredentialDeleteDialog(
        identity: identity,
        signsOut: true,
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
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _sessionProfileSubtitle(session),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.secondaryText,
                            fontSize: 12,
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
              fontSize: 12,
              fontWeight: FontWeight.w400,
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
    this.trailingText,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final Key? iconKey;
  final String title;
  final double height;
  final String? trailingText;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
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
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: destructive ? theme.danger : theme.title,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (trailingValue.isNotEmpty)
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
                  style: TextStyle(color: theme.secondaryText, fontSize: 12),
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
