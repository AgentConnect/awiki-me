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

    return Stack(
      children: <Widget>[
        AwikiMeWidgets.pageBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                Expanded(child: page),
                if (showsGlobalBottomNav) bottomNav,
              ],
            ),
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
    switch (tabIndex) {
      case 0:
        return ConversationWorkspacePage(
          listFooter: responsive.supportsTwoPane ? embeddedBottomNav : null,
        );
      case 1:
        return FriendsWorkspacePage(
          listFooter: responsive.supportsTwoPane ? embeddedBottomNav : null,
        );
      case 2:
        return ProfileWorkspacePage(
          listFooter: responsive.supportsTwoPane ? embeddedBottomNav : null,
        );
    }
    return const SizedBox.shrink();
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
