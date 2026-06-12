import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/e2e_semantics.dart';
import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../domain/entities/session_identity.dart';
import '../../domain/services/realtime_gateway.dart';
import '../../l10n/l10n.dart';
import '../conversation_list/conversation_workspace_page.dart';
import '../conversation_list/conversation_provider.dart';
import '../agents/agents_page.dart';
import '../friends/friends_workspace_page.dart';
import '../onboarding/onboarding_page.dart';
import '../profile/profile_workspace_page.dart';
import '../settings/settings_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/avatar_badge.dart';
import '../shared/responsive_layout.dart';
import '../shared/sidebar_workspace.dart';
import '../shared/widgets/app_widgets.dart';
import 'providers/app_update_provider.dart';
import 'providers/app_runtime_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/session_provider.dart';

const int _macSettingsTabIndex = 6;
const _macRailActiveColor = Color(0xFF0B65F8);
const _macRailInactiveColor = Color(0xFF7A879C);
const _macRailActiveBackground = Color(0xFFEAF2FF);

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int? _lastFeedbackId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appRuntimeProvider.notifier).initialize();
      ref.read(appUpdateProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UiFeedbackEvent?>(uiFeedbackProvider, (previous, next) {
      if (next == null || next.id == _lastFeedbackId || !mounted) {
        return;
      }
      _lastFeedbackId = next.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        AwikiMeToast.show(
          context,
          next.message.resolve(context.l10n),
          danger: next.danger,
        );
      });
    });

    final runtime = ref.watch(appRuntimeProvider);
    final session = ref.watch(sessionProvider);
    final realtimeStatus = ref
        .watch(realtimeConnectionStatusProvider)
        .maybeWhen(
          data: (status) => status,
          orElse: () => RealtimeConnectionStatus.idle,
        );
    final responsive = context.awikiResponsive;
    final tabIndex = ref.watch(shellTabProvider);
    final unreadCount = ref.watch(
      conversationListProvider.select((state) => state.unreadCount),
    );

    if (!session.isLoggedIn) {
      return Stack(
        children: <Widget>[
          const OnboardingPage(),
          if (runtime.isBusy) const AwikiMeLoadingMask(),
        ],
      );
    }

    final bottomNav = _BottomNavBar(
      currentIndex: tabIndex,
      onTap: (index) {
        ref.read(shellTabProvider.notifier).setTab(index);
      },
    );
    final embeddedBottomNav = _BottomNavBar(
      currentIndex: tabIndex,
      embedded: true,
      onTap: (index) {
        ref.read(shellTabProvider.notifier).setTab(index);
      },
    );

    final page = _buildCurrentPage(tabIndex, responsive, embeddedBottomNav);
    final showsGlobalBottomNav = responsive.isPhone;
    final content = responsive.isMacDesktop
        ? _MacDesktopShell(
            currentIndex: tabIndex,
            unreadCount: unreadCount,
            session: session.session,
            onTap: (index) {
              ref.read(shellTabProvider.notifier).setTab(index);
            },
            onOpenSettings: () {
              ref.read(shellTabProvider.notifier).setTab(_macSettingsTabIndex);
            },
            child: page,
          )
        : Column(
            children: <Widget>[
              Expanded(child: page),
              if (showsGlobalBottomNav) bottomNav,
            ],
          );

    return Stack(
      children: <Widget>[
        e2eSemantics(
          identifier: 'e2e-authenticated',
          child: AwikiMeWidgets.pageBackground(
            child: SafeArea(bottom: false, child: content),
          ),
        ),
        if (runtime.isBusy)
          AwikiMeLoadingMask(label: context.l10n.commonPleaseWait),
        if (_shouldShowRealtimeToast(realtimeStatus))
          AwikiMePersistentToast(
            message: _realtimeToastMessage(context, realtimeStatus),
            danger:
                realtimeStatus == RealtimeConnectionStatus.disconnected ||
                realtimeStatus == RealtimeConnectionStatus.failed,
            showSpinner:
                realtimeStatus == RealtimeConnectionStatus.connecting ||
                realtimeStatus == RealtimeConnectionStatus.reconnecting,
            bottom: responsive.isPhone ? 96 : 32,
          ),
      ],
    );
  }

  bool _shouldShowRealtimeToast(RealtimeConnectionStatus status) {
    return status == RealtimeConnectionStatus.connecting ||
        status == RealtimeConnectionStatus.reconnecting;
  }

  String _realtimeToastMessage(
    BuildContext context,
    RealtimeConnectionStatus status,
  ) {
    switch (status) {
      case RealtimeConnectionStatus.connecting:
        return context.l10n.realtimeStatusConnecting;
      case RealtimeConnectionStatus.reconnecting:
        return context.l10n.realtimeStatusReconnecting;
      case RealtimeConnectionStatus.disconnected:
      case RealtimeConnectionStatus.failed:
        return context.l10n.realtimeStatusDisconnected;
      case RealtimeConnectionStatus.idle:
      case RealtimeConnectionStatus.connected:
        return '';
    }
  }

  Widget _buildCurrentPage(
    int tabIndex,
    AwikiResponsiveInfo responsive,
    Widget embeddedBottomNav,
  ) {
    final desktopFooter = responsive.supportsTwoPane && !responsive.isMacDesktop
        ? embeddedBottomNav
        : null;
    if (responsive.isMacDesktop) {
      switch (tabIndex) {
        case 0:
          return const ConversationWorkspacePage();
        case 1:
          return const AgentsWorkspacePage();
        case 2:
          return const FriendsWorkspacePage();
        case 3:
          return const _MacDesktopPlaceholderPage(
            title: '任务',
            subtitle: '任务视图即将接入。当前任务状态会在会话与身份卡中展示。',
            icon: CupertinoIcons.checkmark_square,
          );
        case 4:
          return const _MacDesktopPlaceholderPage(
            title: '工作台',
            subtitle: '工作台模块即将接入。',
            icon: CupertinoIcons.square_grid_2x2,
          );
        case 5:
          return const ProfileWorkspacePage();
        case _macSettingsTabIndex:
          return const _MacEmbeddedSettingsPage();
      }
      return const ConversationWorkspacePage();
    }
    switch (tabIndex) {
      case 0:
        return ConversationWorkspacePage(listFooter: desktopFooter);
      case 1:
        return AgentsWorkspacePage(listFooter: desktopFooter);
      case 2:
        return FriendsWorkspacePage(listFooter: desktopFooter);
      case 3:
        return ProfileWorkspacePage(listFooter: desktopFooter);
    }
    return ConversationWorkspacePage(listFooter: desktopFooter);
  }
}

class _MacDesktopShell extends StatelessWidget {
  const _MacDesktopShell({
    required this.currentIndex,
    required this.unreadCount,
    required this.session,
    required this.onTap,
    required this.onOpenSettings,
    required this.child,
  });

  final int currentIndex;
  final int unreadCount;
  final SessionIdentity? session;
  final ValueChanged<int> onTap;
  final VoidCallback onOpenSettings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Row(
      children: <Widget>[
        SizedBox(
          key: const Key('mac-desktop-rail-slot'),
          width: responsive.displayScaled(72),
          child: _MacDesktopRail(
            currentIndex: currentIndex,
            unreadCount: unreadCount,
            session: session,
            onTap: onTap,
            onOpenSettings: onOpenSettings,
          ),
        ),
        Container(width: 1, color: const Color(0xFFE5EAF2)),
        Expanded(child: child),
      ],
    );
  }
}

class _MacDesktopRail extends StatelessWidget {
  const _MacDesktopRail({
    required this.currentIndex,
    required this.unreadCount,
    required this.session,
    required this.onTap,
    required this.onOpenSettings,
  });

  final int currentIndex;
  final int unreadCount;
  final SessionIdentity? session;
  final ValueChanged<int> onTap;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFF8FBFF)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 760;
          final gap = responsive.displayScaled(compact ? 7.0 : 10.0);
          final avatar = _avatarSeedForSession(session);
          return Column(
            children: <Widget>[
              SizedBox(height: responsive.displayScaled(compact ? 40 : 50)),
              _MacRailAvatar(
                key: const Key('mac-me-rail-avatar'),
                seed: avatar.seed,
                labelOverride: avatar.labelOverride,
                selected: currentIndex == 5,
                onTap: () => onTap(5),
              ),
              SizedBox(height: responsive.displayScaled(compact ? 22 : 28)),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      _MacDesktopRailItem(
                        activeIcon: CupertinoIcons.chat_bubble_2_fill,
                        inactiveIcon: CupertinoIcons.chat_bubble_2,
                        label: '消息',
                        selected: currentIndex == 0,
                        badge: _formatUnreadBadge(unreadCount),
                        compact: compact,
                        onTap: () => onTap(0),
                      ),
                      SizedBox(height: gap),
                      _MacDesktopRailItem(
                        activeIcon: CupertinoIcons.person_2_fill,
                        inactiveIcon: CupertinoIcons.person_2,
                        label: '智能体',
                        selected: currentIndex == 1,
                        compact: compact,
                        onTap: () => onTap(1),
                      ),
                      SizedBox(height: gap),
                      _MacDesktopRailItem(
                        activeIcon: CupertinoIcons.person_fill,
                        inactiveIcon: CupertinoIcons.person,
                        label: '联系人',
                        selected: currentIndex == 2,
                        compact: compact,
                        onTap: () => onTap(2),
                      ),
                      SizedBox(height: gap),
                      _MacDesktopRailItem(
                        activeIcon: CupertinoIcons.checkmark_square_fill,
                        inactiveIcon: CupertinoIcons.checkmark_square,
                        label: '任务',
                        selected: currentIndex == 3,
                        compact: compact,
                        onTap: () => onTap(3),
                      ),
                      SizedBox(height: gap),
                      _MacDesktopRailItem(
                        activeIcon: CupertinoIcons.square_grid_2x2_fill,
                        inactiveIcon: CupertinoIcons.square_grid_2x2,
                        label: '工作台',
                        selected: currentIndex == 4,
                        compact: compact,
                        onTap: () => onTap(4),
                      ),
                      SizedBox(height: gap),
                      _MacDesktopRailItem(
                        activeIcon: CupertinoIcons.gear_alt_fill,
                        inactiveIcon: CupertinoIcons.gear_alt,
                        label: '设置',
                        selected: currentIndex == _macSettingsTabIndex,
                        compact: compact,
                        onTap: onOpenSettings,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: responsive.displayScaled(compact ? 12 : 18)),
            ],
          );
        },
      ),
    );
  }

  String? _formatUnreadBadge(int count) {
    if (count <= 0) {
      return null;
    }
    return count > 99 ? '99+' : '$count';
  }

  ({String seed, String? labelOverride}) _avatarSeedForSession(
    SessionIdentity? session,
  ) {
    final handle = session?.handle?.trim();
    if (handle != null && handle.isNotEmpty) {
      return (seed: handle, labelOverride: null);
    }
    final displayName = session?.displayName.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return (seed: displayName, labelOverride: null);
    }
    final did = session?.did.trim();
    if (did != null && did.isNotEmpty) {
      return (seed: did, labelOverride: null);
    }
    return (seed: 'Me', labelOverride: 'Me');
  }
}

class _MacEmbeddedSettingsPage extends StatelessWidget {
  const _MacEmbeddedSettingsPage();

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final settingsPaneWidth = responsive.displayScaled(420);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          key: const Key('mac-settings-list-pane'),
          width: settingsPaneWidth,
          child: const DecoratedBox(
            decoration: BoxDecoration(color: Color(0xFFF8FAFD)),
            child: SettingsPage(embedded: true),
          ),
        ),
        Container(width: 1, color: const Color(0xFFE5EAF2)),
        const Expanded(child: AwikiWorkspaceEmptyDetail()),
      ],
    );
  }
}

class _MacDesktopRailItem extends StatelessWidget {
  const _MacDesktopRailItem({
    required this.activeIcon,
    required this.inactiveIcon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
    this.badge,
  });

  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final foreground = selected ? _macRailActiveColor : _macRailInactiveColor;
    final icon = selected ? activeIcon : inactiveIcon;
    final height = responsive.displayScaled(compact ? 50.0 : 56.0);
    final width = responsive.displayScaled(58);
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      selected: selected,
      borderRadius: BorderRadius.circular(responsive.displayScaled(10)),
      pressedScale: 0.98,
      scaleOnPress: true,
      builder: (context, state, child) {
        final overlay = state.pressed
            ? const Color(0x1A0B65F8)
            : state.hovered || state.focused
            ? const Color(0x100B65F8)
            : const Color(0x00FFFFFF);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: overlay,
            borderRadius: BorderRadius.circular(responsive.displayScaled(10)),
          ),
          child: child,
        );
      },
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: width,
              height: height,
              padding: EdgeInsets.symmetric(
                vertical: responsive.displayScaled(compact ? 6 : 8),
              ),
              decoration: BoxDecoration(
                color: selected
                    ? _macRailActiveBackground
                    : const Color(0x00FFFFFF),
                borderRadius: BorderRadius.circular(
                  responsive.displayScaled(10),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: responsive.displayScaled(30),
                    height: responsive.displayScaled(24),
                    child: Center(
                      child: Icon(
                        icon,
                        color: foreground,
                        size: responsive.displayScaled(20),
                        weight: selected ? 700 : 400,
                      ),
                    ),
                  ),
                  SizedBox(height: responsive.displayScaled(compact ? 2 : 4)),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foreground,
                      fontSize: responsive.displayScaled(10.5),
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null)
              Positioned(
                right: responsive.displayScaled(5),
                top: responsive.displayScaled(4),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: responsive.displayScaled(5),
                    vertical: responsive.displayScaled(2),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0xFFF8FBFF)),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontSize: responsive.displayScaled(9),
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MacRailAvatar extends StatelessWidget {
  const _MacRailAvatar({
    super.key,
    required this.seed,
    this.labelOverride,
    required this.selected,
    required this.onTap,
  });

  final String seed;
  final String? labelOverride;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onTap,
      semanticLabel: '我',
      selected: selected,
      scaleOnPress: true,
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(responsive.displayScaled(19)),
      child: Container(
        width: responsive.displayScaled(38),
        height: responsive.displayScaled(38),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFDDEBFF) : const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(responsive.displayScaled(19)),
          border: Border.all(
            color: selected ? const Color(0xFF0B65F8) : const Color(0x00FFFFFF),
          ),
        ),
        child: Center(
          child: AvatarBadge(
            seed: seed,
            size: responsive.displayScaled(34),
            labelOverride: labelOverride,
          ),
        ),
      ),
    );
  }
}

class _MacDesktopPlaceholderPage extends StatelessWidget {
  const _MacDesktopPlaceholderPage({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFFBFDFF)),
      child: Center(
        child: Container(
          key: const Key('mac-desktop-placeholder-card'),
          constraints: BoxConstraints(maxWidth: responsive.displayScaled(420)),
          padding: EdgeInsets.all(responsive.displayScaled(28)),
          decoration: BoxDecoration(
            color: CupertinoColors.white,
            borderRadius: BorderRadius.circular(responsive.displayScaled(18)),
            border: Border.all(color: const Color(0xFFE5EAF2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                color: const Color(0xFF0B65F8),
                size: responsive.displayScaled(44),
              ),
              SizedBox(height: responsive.displayScaled(18)),
              Text(
                title,
                style: TextStyle(
                  color: const Color(0xFF101B32),
                  fontSize: responsive.displayScaled(22),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: responsive.displayScaled(10)),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF66728A),
                  fontSize: responsive.displayScaled(14),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.currentIndex,
    required this.onTap,
    this.embedded = false,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final l10n = context.l10n;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final showLabels = responsive.isPhone && !embedded;
    final horizontalPadding = embedded ? 0.0 : responsive.spacing(24);
    final bottomPadding = embedded
        ? 0.0
        : (bottomInset > 0 ? responsive.spacing(8) : 16.0);
    final navHeight = showLabels
        ? responsive.scaled(58)
        : responsive.navBarHeight;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          embedded ? 0 : responsive.spacing(8),
          horizontalPadding,
          bottomPadding,
        ),
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final navWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth.clamp(
                      0.0,
                      responsive.isPhone ? responsive.scaled(356.0) : 260.0,
                    )
                  : (responsive.isPhone ? responsive.scaled(356.0) : 260.0);
              return Container(
                width: navWidth,
                height: navHeight,
                padding: EdgeInsets.symmetric(
                  horizontal: showLabels
                      ? responsive.spacing(9)
                      : responsive.spacing(18),
                  vertical: showLabels
                      ? responsive.spacing(3)
                      : responsive.spacing(8),
                ),
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(
                    embedded ? responsive.radius(14) : responsive.radius(14),
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x10000000),
                      blurRadius: 28,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _NavButton(
                        label: l10n.shellNavMessages,
                        semanticsIdentifier: 'e2e-messages-tab',
                        activeAsset: 'assets/icons/message_Active.svg',
                        inactiveAsset: 'assets/icons/message_Inactive.svg',
                        active: currentIndex == 0,
                        showLabel: showLabels,
                        onTap: () => onTap(0),
                      ),
                    ),
                    Expanded(
                      child: _NavIconButton(
                        label: '智能体',
                        semanticsIdentifier: 'e2e-agents-tab',
                        icon: CupertinoIcons.sparkles,
                        active: currentIndex == 1,
                        showLabel: showLabels,
                        onTap: () => onTap(1),
                      ),
                    ),
                    Expanded(
                      child: _NavButton(
                        label: l10n.shellNavFriends,
                        semanticsIdentifier: 'e2e-friends-tab',
                        activeAsset: 'assets/icons/friend_Active.svg',
                        inactiveAsset: 'assets/icons/friend_Inactive.svg',
                        active: currentIndex == 2,
                        showLabel: showLabels,
                        onTap: () => onTap(2),
                      ),
                    ),
                    Expanded(
                      child: _NavButton(
                        label: l10n.shellNavMe,
                        semanticsIdentifier: 'e2e-profile-tab',
                        activeAsset: 'assets/icons/me_Active.svg',
                        inactiveAsset: 'assets/icons/me_Inactive.svg',
                        active: currentIndex == 3,
                        showLabel: showLabels,
                        onTap: () => onTap(3),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.label,
    required this.semanticsIdentifier,
    required this.icon,
    required this.active,
    required this.showLabel,
    required this.onTap,
  });

  final String label;
  final String semanticsIdentifier;
  final IconData icon;
  final bool active;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final foreground = active
        ? AwikiMePalette.actionBlue
        : AwikiMePalette.actionMuted;
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      selected: active,
      scaleOnPress: true,
      pressedScale: responsive.isPhone ? 0.96 : 0.98,
      borderRadius: BorderRadius.circular(
        showLabel ? responsive.radius(8) : 10,
      ),
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: showLabel
              ? EdgeInsets.fromLTRB(
                  responsive.spacing(4),
                  responsive.spacing(1),
                  responsive.spacing(4),
                  responsive.spacing(5),
                )
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: active && showLabel
                ? AwikiMePalette.actionBlueSoft
                : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(
              showLabel ? responsive.radius(8) : 0,
            ),
          ),
          child: showLabel
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(icon, color: foreground, size: responsive.scaled(24)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          color: foreground,
                          fontSize: responsive.scaled(13.25),
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Icon(icon, color: foreground, size: responsive.iconLg),
                ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.semanticsIdentifier,
    required this.activeAsset,
    required this.inactiveAsset,
    required this.active,
    required this.showLabel,
    required this.onTap,
  });

  final String label;
  final String semanticsIdentifier;
  final String activeAsset;
  final String inactiveAsset;
  final bool active;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final navIconSize = showLabel
        ? responsive.scaled(31)
        : (responsive.isPhone ? 30.0 : responsive.iconLg * 2);
    final tapSize = responsive.isPhone
        ? responsive.compactControlHeight + responsive.spacing(6)
        : 44.0;
    final labelFontSize = responsive.scaled(13.25);
    final navIconVisualScale = showLabel ? 1.5 : 1.0;
    final foreground = active
        ? AwikiMePalette.actionBlue
        : AwikiMePalette.actionMuted;
    Widget buildNavIcon() {
      final icon = SvgPicture.asset(
        active ? activeAsset : inactiveAsset,
        width: navIconSize,
        height: navIconSize,
        colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
      );
      return Transform.scale(scale: navIconVisualScale, child: icon);
    }

    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      selected: active,
      scaleOnPress: true,
      pressedScale: responsive.isPhone ? 0.96 : 0.98,
      borderRadius: BorderRadius.circular(
        showLabel ? responsive.radius(8) : 10,
      ),
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          width: showLabel ? double.infinity : tapSize,
          height: showLabel ? double.infinity : tapSize,
          padding: showLabel
              ? EdgeInsets.fromLTRB(
                  responsive.spacing(4),
                  responsive.spacing(1),
                  responsive.spacing(4),
                  responsive.spacing(5),
                )
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: active && showLabel
                ? AwikiMePalette.actionBlueSoft
                : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(
              showLabel ? responsive.radius(8) : 0,
            ),
          ),
          child: showLabel
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    buildNavIcon(),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          color: foreground,
                          fontSize: labelFontSize,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                )
              : Center(child: buildNavIcon()),
        ),
      ),
    );
  }
}
