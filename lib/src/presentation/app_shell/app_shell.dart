import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui_feedback.dart';
import '../../l10n/l10n.dart';
import '../conversation_list/conversation_list_page.dart';
import '../friends/friends_page.dart';
import '../onboarding/onboarding_page.dart';
import '../profile/profile_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import 'providers/app_runtime_provider.dart';
import 'providers/session_provider.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _tabIndex = 0;
  int? _lastFeedbackId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appRuntimeProvider.notifier).initialize();
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

    if (!session.isLoggedIn) {
      return Stack(
        children: <Widget>[
          const OnboardingPage(),
          if (runtime.isBusy) const AwikiMeLoadingMask(),
        ],
      );
    }

    final tabs = <Widget>[
      const ConversationListPage(),
      const FriendsPage(),
      const ProfilePage(),
    ];

    return Stack(
      children: <Widget>[
        AwikiMeWidgets.pageBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: IndexedStack(index: _tabIndex, children: tabs),
                ),
                _BottomNavBar(
                  currentIndex: _tabIndex,
                  onTap: (index) {
                    setState(() => _tabIndex = index);
                  },
                ),
              ],
            ),
          ),
        ),
        if (runtime.isBusy)
          AwikiMeLoadingMask(label: context.l10n.commonPleaseWait),
      ],
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, bottomInset > 0 ? 8 : 18),
        child: Center(
          child: Container(
            width: 272,
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x10000000),
                  blurRadius: 28,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _NavButton(
                  activeAsset: 'assets/icons/message_Active.svg',
                  inactiveAsset: 'assets/icons/message_Inactive.svg',
                  active: currentIndex == 0,
                  onTap: () => onTap(0),
                ),
                const SizedBox(width: 42),
                _NavButton(
                  activeAsset: 'assets/icons/friend_Active.svg',
                  inactiveAsset: 'assets/icons/friend_Inactive.svg',
                  active: currentIndex == 1,
                  onTap: () => onTap(1),
                ),
                const SizedBox(width: 42),
                _NavButton(
                  activeAsset: 'assets/icons/me_Active.svg',
                  inactiveAsset: 'assets/icons/me_Inactive.svg',
                  active: currentIndex == 2,
                  onTap: () => onTap(2),
                ),
              ],
            ),
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
    const double navIconSize = 48;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
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
