import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../domain/services/realtime_gateway.dart';
import '../../l10n/l10n.dart';
import '../conversation_list/conversation_workspace_page.dart';
import '../friends/friends_workspace_page.dart';
import '../onboarding/onboarding_page.dart';
import '../profile/profile_workspace_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/responsive_layout.dart';
import 'providers/app_update_provider.dart';
import 'providers/app_runtime_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/session_provider.dart';

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
          orElse: () => ref.watch(realtimeGatewayProvider).connectionStatus,
        );
    final responsive = context.awikiResponsive;
    final tabIndex = ref.watch(shellTabProvider);

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
            onTap: (index) {
              ref.read(shellTabProvider.notifier).setTab(index);
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
        AwikiMeWidgets.pageBackground(
          child: SafeArea(bottom: false, child: content),
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
        status == RealtimeConnectionStatus.reconnecting ||
        status == RealtimeConnectionStatus.disconnected ||
        status == RealtimeConnectionStatus.failed;
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
          return const _MacDesktopPlaceholderPage(
            title: '智能体',
            subtitle: '智能体工作台即将接入。当前可先在消息中与 Agent 协作。',
            icon: CupertinoIcons.person_2_fill,
          );
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
      }
      return const ConversationWorkspacePage();
    }
    switch (tabIndex) {
      case 0:
        return ConversationWorkspacePage(listFooter: desktopFooter);
      case 1:
        return FriendsWorkspacePage(listFooter: desktopFooter);
      case 2:
        return ProfileWorkspacePage(listFooter: desktopFooter);
    }
    return ConversationWorkspacePage(listFooter: desktopFooter);
  }
}

class _MacDesktopShell extends StatelessWidget {
  const _MacDesktopShell({
    required this.currentIndex,
    required this.onTap,
    required this.child,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 72,
          child: _MacDesktopRail(currentIndex: currentIndex, onTap: onTap),
        ),
        Container(width: 1, color: const Color(0xFFE5EAF2)),
        Expanded(child: child),
      ],
    );
  }
}

class _MacDesktopRail extends StatelessWidget {
  const _MacDesktopRail({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFF8FBFF)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 760;
          final gap = compact ? 7.0 : 10.0;
          return Column(
            children: <Widget>[
              SizedBox(height: compact ? 22 : 30),
              const Text(
                'AW',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF0B65F8),
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                ),
              ),
              SizedBox(height: compact ? 22 : 28),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      _MacDesktopRailItem(
                        icon: CupertinoIcons.chat_bubble_2_fill,
                        label: '消息',
                        selected: currentIndex == 0,
                        badge: '12',
                        compact: compact,
                        onTap: () => onTap(0),
                      ),
                      SizedBox(height: gap),
                      _MacDesktopRailItem(
                        icon: CupertinoIcons.person_2_fill,
                        label: '智能体',
                        selected: currentIndex == 1,
                        compact: compact,
                        onTap: () => onTap(1),
                      ),
                      SizedBox(height: gap),
                      _MacDesktopRailItem(
                        icon: CupertinoIcons.person,
                        label: '联系人',
                        selected: currentIndex == 2,
                        compact: compact,
                        onTap: () => onTap(2),
                      ),
                      SizedBox(height: gap),
                      _MacDesktopRailItem(
                        icon: CupertinoIcons.checkmark_square,
                        label: '任务',
                        selected: currentIndex == 3,
                        compact: compact,
                        onTap: () => onTap(3),
                      ),
                      SizedBox(height: gap),
                      _MacDesktopRailItem(
                        icon: CupertinoIcons.square_grid_2x2,
                        label: '工作台',
                        selected: currentIndex == 4,
                        compact: compact,
                        onTap: () => onTap(4),
                      ),
                      SizedBox(height: gap),
                      _MacDesktopRailItem(
                        icon: CupertinoIcons.gear_alt,
                        label: '配置',
                        selected: currentIndex == 5,
                        compact: compact,
                        onTap: () => onTap(5),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  top: compact ? 10 : 14,
                  bottom: compact ? 12 : 18,
                ),
                child: _MacRailAvatar(label: 'M', selected: currentIndex == 5),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MacDesktopRailItem extends StatelessWidget {
  const _MacDesktopRailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? const Color(0xFF0B65F8)
        : const Color(0xFF34415C);
    final height = compact ? 50.0 : 56.0;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 58,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 58,
                height: height,
                padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFEAF2FF)
                      : const Color(0x00FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 30,
                      height: 24,
                      child: Center(
                        child: Icon(icon, color: foreground, size: 20),
                      ),
                    ),
                    SizedBox(height: compact ? 2 : 4),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null)
                Positioned(
                  right: 5,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: const Color(0xFFF8FBFF)),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacRailAvatar extends StatelessWidget {
  const _MacRailAvatar({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFDDEBFF) : const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: selected ? const Color(0xFF0B65F8) : const Color(0x00FFFFFF),
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF0B65F8),
            fontSize: 16,
            fontWeight: FontWeight.w900,
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
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFFBFDFF)),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: CupertinoColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5EAF2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: const Color(0xFF0B65F8), size: 44),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF101B32),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF66728A),
                  fontSize: 14,
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
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final horizontalPadding = embedded ? 0.0 : responsive.spacing(24);
    final bottomPadding = embedded
        ? 0.0
        : (bottomInset > 0 ? responsive.spacing(8) : 16.0);
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
                      responsive.isPhone ? responsive.scaled(272.0) : 220.0,
                    )
                  : (responsive.isPhone ? responsive.scaled(272.0) : 220.0);
              return Container(
                width: navWidth,
                height: responsive.navBarHeight,
                padding: EdgeInsets.symmetric(
                  horizontal: responsive.spacing(18),
                  vertical: responsive.spacing(8),
                ),
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(
                    embedded ? 24 : responsive.radius(24),
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _NavButton(
                      activeAsset: 'assets/icons/message_Active.svg',
                      inactiveAsset: 'assets/icons/message_Inactive.svg',
                      active: currentIndex == 0,
                      onTap: () => onTap(0),
                    ),
                    _NavButton(
                      activeAsset: 'assets/icons/friend_Active.svg',
                      inactiveAsset: 'assets/icons/friend_Inactive.svg',
                      active: currentIndex == 1,
                      onTap: () => onTap(1),
                    ),
                    _NavButton(
                      activeAsset: 'assets/icons/me_Active.svg',
                      inactiveAsset: 'assets/icons/me_Inactive.svg',
                      active: currentIndex == 2,
                      onTap: () => onTap(2),
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

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.activeAsset,
    required this.inactiveAsset,
    required this.active,
    required this.onTap,
  });

  final String activeAsset;
  final String inactiveAsset;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final navIconSize = responsive.isPhone ? 42.0 : responsive.iconLg * 2;
    final tapSize = responsive.isPhone
        ? responsive.compactControlHeight + responsive.spacing(6)
        : 44.0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: tapSize,
        height: tapSize,
        child: Center(
          child: SvgPicture.asset(
            active ? activeAsset : inactiveAsset,
            width: navIconSize,
            height: navIconSize,
          ),
        ),
      ),
    );
  }
}
