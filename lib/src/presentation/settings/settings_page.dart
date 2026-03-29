import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

import '../app_shell/app_controller.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_top_bar.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AwikiMeColors.background,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: <Widget>[
            AwikiMeTopBar(
              title: '设置',
              padding: EdgeInsets.zero,
              leading: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(
                  Icons.arrow_back,
                  color: AwikiMeColors.primaryDark,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: AwikiMeDecorations.card(color: AwikiMeColors.surface),
              child: Column(
                children: <Widget>[
                  _SettingsRow(
                    icon: Icons.notifications_none,
                    title: '消息推送通知',
                    trailing: Transform.scale(
                      scale: 0.88,
                      child: const CupertinoSwitch(
                        value: true,
                        activeColor: AwikiMeColors.online,
                        onChanged: null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: AwikiMeDecorations.card(color: AwikiMeColors.surface),
              child: Column(
                children: <Widget>[
                  _SettingsRow(
                    icon: Icons.ios_share,
                    title: '导出身份凭证',
                    subtitle: controller.session?.credentialName != null
                        ? '导出当前凭证：${controller.session!.credentialName}'
                        : '当前暂无可导出的登录凭证',
                    onTap: controller.session == null || controller.isBusy
                        ? null
                        : controller.exportCurrentCredential,
                  ),
                  const _Divider(),
                  _SettingsRow(
                    icon: Icons.logout,
                    title: '退出登录',
                    subtitle: '清除本地登录状态并返回登录页',
                    destructive: true,
                    onTap: () => _showLogoutDialog(context),
                  ),
                  const _Divider(),
                  _SettingsRow(
                    icon: Icons.delete_outline,
                    title: '注销当前凭证',
                    subtitle: controller.session?.credentialName != null
                        ? '删除本地凭证：${controller.session!.credentialName}'
                        : '删除当前登录凭证',
                    destructive: true,
                    onTap: () => _showDeleteCredentialDialog(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(ctx).pop();
              await controller.logout();
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  void _showDeleteCredentialDialog(BuildContext context) {
    final credentialName = controller.session?.credentialName;
    if (credentialName == null || credentialName.isEmpty) {
      return;
    }
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('注销当前凭证'),
        content: Text('将删除本地凭证 "$credentialName"，并退出登录。确定继续吗？'),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(ctx).pop();
              await controller.deleteCurrentCredential();
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('确认注销'),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: destructive
                  ? const Color(0xFFFFEBEB)
                  : AwikiMeColors.subtleSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: destructive ? AwikiMeColors.danger : AwikiMeColors.primaryDark,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: destructive ? AwikiMeColors.danger : AwikiMeColors.title,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AwikiMeTextStyles.cardSubtitle),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing ??
              Icon(
                Icons.chevron_right,
                size: 18,
                color: onTap == null
                    ? AwikiMeColors.border
                    : AwikiMeColors.tertiaryText,
              ),
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }
    return GestureDetector(onTap: onTap, child: content);
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: AwikiMeColors.border),
        ),
      ),
    );
  }
}
