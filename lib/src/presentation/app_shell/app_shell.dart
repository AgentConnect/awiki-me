import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/bootstrap.dart';
import '../chat/chat_page.dart';
import '../conversation_list/conversation_list_page.dart';
import '../friends/friends_page.dart';
import '../group/create_group_page.dart';
import '../group/group_list_page.dart';
import '../onboarding/onboarding_page.dart';
import '../profile/profile_page.dart';
import '../settings/settings_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import 'app_controller.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.bootstrap});

  final AppBootstrap bootstrap;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tabIndex = 0;
  String? _lastShownError;
  String? _lastShownInfo;

  AppController get controller => widget.bootstrap.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final nextError = controller.errorMessage;
    final nextInfo = controller.infoMessage;
    if (nextError != null &&
        nextError.isNotEmpty &&
        nextError != _lastShownError) {
      _lastShownError = nextError;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          AwikiMeToast.show(context, nextError, danger: true);
        }
      });
    } else if (nextError == null || nextError.isEmpty) {
      _lastShownError = null;
    }
    if (nextInfo != null && nextInfo.isNotEmpty && nextInfo != _lastShownInfo) {
      _lastShownInfo = nextInfo;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          AwikiMeToast.show(context, nextInfo);
        }
      });
    } else if (nextInfo == null || nextInfo.isEmpty) {
      _lastShownInfo = null;
    }
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      setState(() {});
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _onTabTapped(int index) {
    setState(() => _tabIndex = index);
    if (index == 1) {
      controller.refreshFriendsTab().catchError((_) {});
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => SettingsPage(controller: controller),
      ),
    );
  }

  Future<void> _showQuickActions() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text(
          '快捷操作',
          style: TextStyle(color: AwikiMeColors.title),
        ),
        actions: <Widget>[
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(this.context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => CreateGroupPage(controller: controller),
                ),
              );
            },
            child: const Text(
              '发起群聊',
              style: TextStyle(color: AwikiMeColors.title),
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(this.context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => GroupListPage(controller: controller),
                ),
              );
            },
            child: const Text(
              '加入群聊',
              style: TextStyle(color: AwikiMeColors.title),
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(context).pop();
              setState(() => _tabIndex = 1);
              await Future<void>.delayed(const Duration(milliseconds: 120));
              if (!mounted) return;
              _showAddFriendDialog();
            },
            child: const Text(
              '添加朋友',
              style: TextStyle(color: AwikiMeColors.title),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: AwikiMeColors.title),
          ),
        ),
      ),
    );
  }

  void _showAddFriendDialog() {
    final textController = TextEditingController();
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('添加朋友'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: textController,
            placeholder: '输入 Handle 或 DID',
            autofocus: true,
          ),
        ),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              final val = textController.text.trim();
              if (val.isEmpty) return;
              Navigator.of(ctx).pop();

              final status = await controller.checkRelationship(val);
              if (!mounted) {
                return;
              }
              if (status != null && status.relationship != 'none') {
                AwikiMeToast.show(context, '已经添加或正在申请中');
                return;
              }

              await controller.followUser(val);
              if (!mounted) {
                return;
              }
              AwikiMeToast.show(context, '已关注');
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (!controller.isLoggedIn) {
      content = OnboardingPage(controller: controller);
    } else {
      final tabs = <Widget>[
        ConversationListPage(
          controller: controller,
          onOpenChat: (conversation) async {
            await controller.openConversation(conversation);
            if (!context.mounted) {
              return;
            }
            await Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => ChatPage(
                  controller: controller,
                  conversation: conversation,
                ),
              ),
            );
          },
          onOpenSettings: _openSettings,
          onOpenQuickActions: _showQuickActions,
        ),
        FriendsPage(
          controller: controller,
          onOpenSettings: _openSettings,
          onOpenQuickActions: _showQuickActions,
          onOpenGroups: () {
            Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => GroupListPage(controller: controller),
              ),
            );
          },
        ),
        ProfilePage(
          controller: controller,
          onOpenSettings: _openSettings,
          onOpenQuickActions: _showQuickActions,
        ),
      ];

      content = AwikiMeWidgets.pageBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Expanded(
                child: IndexedStack(
                  index: _tabIndex,
                  children: tabs,
                ),
              ),
              _BottomNavBar(
                currentIndex: _tabIndex,
                onTap: _onTabTapped,
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: <Widget>[
        content,
        if (controller.isBusy) const AwikiMeLoadingMask(label: '请稍候...'),
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
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AwikiMeColors.surface,
        border: Border(
          top: BorderSide(
            color: Color(0x0F000000),
            width: 1,
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset + 12),
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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 96,
        height: 64,
        child: Center(
          child: SvgPicture.asset(
            active ? activeAsset : inactiveAsset,
            width: 56,
            height: 56,
          ),
        ),
      ),
    );
  }
}
