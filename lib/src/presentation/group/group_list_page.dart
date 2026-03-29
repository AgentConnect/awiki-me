import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../app_shell/app_controller.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_top_bar.dart';

class GroupListPage extends StatelessWidget {
  const GroupListPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Stack(
        children: <Widget>[
          CupertinoPageScaffold(
            backgroundColor: AwikiMeColors.background,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: <Widget>[
                  AwikiMeTopBar(
                    title: '群聊列表',
                    padding: EdgeInsets.zero,
                    trailingWidth: 64,
                    leading: GestureDetector(
                      onTap: controller.isBusy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Icon(
                        Icons.arrow_back,
                        color: AwikiMeColors.primaryDark,
                        size: 22,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        GestureDetector(
                          onTap: controller.isBusy ? null : controller.refreshGroups,
                          child: const Icon(
                            Icons.refresh,
                            color: AwikiMeColors.title,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: controller.isBusy
                              ? null
                              : () => _showJoinDialog(context),
                          child: const Icon(
                            Icons.group_add,
                            color: AwikiMeColors.primary,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (controller.groups.isEmpty)
                    Container(
                      decoration:
                          AwikiMeDecorations.card(color: AwikiMeColors.subtleSurface),
                      padding: const EdgeInsets.all(16),
                      child: const Text(
                        '还没有群组。先创建一个群，或使用 6 位 join-code 加入。',
                        style: AwikiMeTextStyles.cardSubtitle,
                      ),
                    )
                  else
                    ...controller.groups.map(
                      (group) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _GroupCard(
                          group: group,
                          onTap: () async {
                            await controller.openGroupChat(context, group: group);
                          },
                          onOpenDetail: () async {
                            await controller.loadGroupMembers(group.groupId);
                            if (!context.mounted) {
                              return;
                            }
                            Navigator.of(context).push(
                              CupertinoPageRoute<void>(
                                builder: (_) => GroupDetailPage(
                                  controller: controller,
                                  initialGroup: group,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (controller.isBusy)
            const AwikiMeLoadingMask(label: '正在加载群数据...'),
        ],
      ),
    );
  }

  void _showJoinDialog(BuildContext context) {
    final textController = TextEditingController();
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('通过 Join-code 入群'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: textController,
            placeholder: '输入 6 位数字 join-code',
            keyboardType: TextInputType.number,
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
              final joinCode = textController.text.trim();
              if (joinCode.isEmpty) {
                return;
              }
              Navigator.of(ctx).pop();
              final group = await controller.joinGroup(joinCode);
              if (!context.mounted || group == null) {
                return;
              }
              await controller.loadGroupMembers(group.groupId);
              if (!context.mounted) {
                return;
              }
              Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => GroupDetailPage(
                    controller: controller,
                    initialGroup: group,
                  ),
                ),
              );
            },
            child: const Text('加入'),
          ),
        ],
      ),
    );
  }
}

class GroupDetailPage extends StatefulWidget {
  const GroupDetailPage({
    super.key,
    required this.controller,
    required this.initialGroup,
  });

  final AppController controller;
  final GroupSummary initialGroup;

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  String? _joinCode;
  late GroupSummary _group;

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup;
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.controller.membersByGroup[_group.groupId] ??
        const <GroupMemberSummary>[];
    return Stack(
      children: <Widget>[
        CupertinoPageScaffold(
          backgroundColor: AwikiMeColors.background,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    GestureDetector(
                      onTap: widget.controller.isBusy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back,
                          color: AwikiMeColors.primaryDark,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AwikiMeTextStyles.navTitle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: AwikiMeDecorations.card(color: AwikiMeColors.surface),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          AvatarBadge(seed: _group.name, size: 56),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(_group.name,
                                    style: AwikiMeTextStyles.sectionTitle),
                                const SizedBox(height: 4),
                                Text(
                                  _group.description.isEmpty
                                      ? '暂无群描述'
                                      : _group.description,
                                  style: AwikiMeTextStyles.cardSubtitle,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          _Pill(label: '${_group.memberCount} 人'),
                          _Pill(label: _group.myRole ?? 'member'),
                          if (_joinCode != null) _Pill(label: 'Join-code: $_joinCode'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Group ID: ${_group.groupId}',
                        style: AwikiMeTextStyles.meta.copyWith(letterSpacing: 0),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: AwikiMeDecorations.card(color: AwikiMeColors.surface),
                  child: Column(
                    children: <Widget>[
                      _ActionRow(
                        icon: Icons.chat_bubble,
                        title: '进入群聊',
                        onTap: () => widget.controller.openGroupChat(
                          context,
                          group: _group,
                        ),
                      ),
                      const _Divider(),
                      _ActionRow(
                        icon: Icons.qr_code_2,
                        title: '获取当前 Join-code',
                        onTap: _loadJoinCode,
                      ),
                      const _Divider(),
                      _ActionRow(
                        icon: Icons.refresh,
                        title: '刷新 Join-code',
                        onTap: _refreshJoinCode,
                      ),
                      const _Divider(),
                      _ActionRow(
                        icon: Icons.groups_2,
                        title: '刷新群详情与成员',
                        onTap: _refreshGroupSnapshot,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('群成员', style: AwikiMeTextStyles.sectionTitle),
                ),
                const SizedBox(height: 12),
                if (members.isEmpty)
                  Container(
                    decoration:
                        AwikiMeDecorations.card(color: AwikiMeColors.subtleSurface),
                    padding: const EdgeInsets.all(16),
                    child: const Text(
                      '暂无成员快照，先执行一次刷新群详情与成员。',
                      style: AwikiMeTextStyles.cardSubtitle,
                    ),
                  )
                else
                  ...members.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration:
                            AwikiMeDecorations.card(color: AwikiMeColors.surface),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: <Widget>[
                            AvatarBadge(
                              seed: item.handle.isNotEmpty ? item.handle : item.did,
                              size: 40,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    item.handle.isNotEmpty ? item.handle : item.did,
                                    style: AwikiMeTextStyles.cardTitle,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            _Pill(label: item.role),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (widget.controller.isBusy)
          const AwikiMeLoadingMask(label: '请稍候...'),
      ],
    );
  }

  Future<void> _loadJoinCode() async {
    final code = await widget.controller.getGroupJoinCode(_group.groupId);
    if (!mounted) {
      return;
    }
    setState(() {
      _joinCode = code;
      _group = _currentGroup();
    });
  }

  Future<void> _refreshJoinCode() async {
    final code = await widget.controller.refreshGroupJoinCode(_group.groupId);
    if (!mounted) {
      return;
    }
    setState(() {
      _joinCode = code;
      _group = _currentGroup();
    });
  }

  Future<void> _refreshGroupSnapshot() async {
    final refreshed = await widget.controller.refreshGroup(_group.groupId);
    if (!mounted) {
      return;
    }
    setState(() {
      _group = refreshed ?? _currentGroup();
    });
  }

  GroupSummary _currentGroup() {
    for (final item in widget.controller.groups) {
      if (item.groupId == _group.groupId) {
        return item;
      }
    }
    return _group;
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.onTap,
    required this.onOpenDetail,
  });

  final GroupSummary group;
  final VoidCallback onTap;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onOpenDetail,
      child: Container(
        decoration: AwikiMeDecorations.card(color: AwikiMeColors.surface),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            AvatarBadge(seed: group.name, size: 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(group.name, style: AwikiMeTextStyles.cardTitle),
                  const SizedBox(height: 4),
                  Text(
                    group.description.isEmpty ? '暂无群描述' : group.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AwikiMeTextStyles.cardSubtitle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                _Pill(label: '${group.memberCount}人'),
                const SizedBox(height: 8),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AwikiMeColors.tertiaryText,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AwikiMeColors.subtleSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: AwikiMeColors.primaryDark),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: AwikiMeTextStyles.cardTitle)),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AwikiMeColors.tertiaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AwikiMeColors.primaryDark,
        ),
      ),
    );
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
