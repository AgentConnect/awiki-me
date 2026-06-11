import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../app/ui_feedback.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/avatar_badge.dart';
import '../shared/copyable_did_line.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import '../app_shell/providers/session_provider.dart';
import 'create_group_page.dart';
import 'group_chat_navigation.dart';
import 'group_provider.dart';

class GroupListPage extends ConsumerWidget {
  const GroupListPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(groupProvider);
    final theme = context.awikiTheme;
    final content = Stack(
      children: <Widget>[
        ListView(
          padding: EdgeInsets.fromLTRB(0, embedded ? 22 : 14, 0, 24),
          children: <Widget>[
            AwikiMeTopBar(
              title: context.l10n.groupListTitle,
              padding: EdgeInsets.zero,
              trailingWidth: 108,
              leading: embedded
                  ? const SizedBox.shrink()
                  : TopBarActionButton(
                      onTap: () => Navigator.of(context).pop(),
                      child: AwikiAssetIcon(
                        assetName: 'assets/icons/icon_left.svg',
                        color: theme.primaryDark,
                        size: 22,
                      ),
                    ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TopBarActionButton(
                    onTap: () => ref.read(groupProvider.notifier).refresh(),
                    child: Icon(
                      CupertinoIcons.refresh,
                      color: theme.title,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TopBarActionButton(
                    onTap: () => AppNavigator.push(
                      context,
                      (_) => const CreateGroupPage(),
                    ),
                    child: Icon(
                      CupertinoIcons.person_3_fill,
                      color: theme.primary,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TopBarActionButton(
                    onTap: () => _showJoinDialog(context, ref),
                    child: Icon(
                      CupertinoIcons.link,
                      color: theme.primary,
                      size: 21,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (state.groups.isEmpty)
              AppCardSection(
                color: theme.subtleSurface,
                padding: const EdgeInsets.all(16),
                child: Text(
                  context.l10n.groupListEmpty,
                  style: AwikiMeTextStyles.cardSubtitle,
                ),
              )
            else
              ...state.groups.map(
                (group) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _GroupCard(
                    group: group,
                    onTap: () => openGroupChat(
                      context,
                      ref,
                      group,
                      closeCurrentRouteOnDesktop: !embedded,
                    ),
                    onOpenDetail: () async {
                      await ref
                          .read(groupProvider.notifier)
                          .loadGroupMembers(group.groupId);
                      if (!context.mounted) {
                        return;
                      }
                      await AppNavigator.push(
                        context,
                        (_) => GroupDetailPage(initialGroup: group),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
        if (state.isLoading)
          AwikiMeLoadingMask(label: context.l10n.groupListLoading),
      ],
    );
    if (embedded) {
      return DecoratedBox(
        decoration: BoxDecoration(color: theme.background),
        child: SafeArea(bottom: false, child: content),
      );
    }
    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: AwikiAdaptiveScaffold(
        maxWidth: 900,
        includeBottomSafeArea: true,
        child: content,
      ),
    );
  }

  void _showJoinDialog(BuildContext context, WidgetRef ref) {
    final textController = TextEditingController();
    AppNavigator.showDialog<void>(
      context,
      (ctx) => CupertinoAlertDialog(
        title: Text(context.l10n.groupJoinDialogTitle),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AppTextField(
            controller: textController,
            label: context.l10n.groupJoinDialogTitle,
            placeholder: context.l10n.groupJoinDialogPlaceholder,
            keyboardType: TextInputType.text,
          ),
        ),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              final groupDid = textController.text.trim();
              if (groupDid.isEmpty) {
                return;
              }
              Navigator.of(ctx).pop();
              try {
                final group = await ref
                    .read(groupProvider.notifier)
                    .joinGroup(groupDid);
                await ref
                    .read(groupProvider.notifier)
                    .loadGroupMembers(group.groupId);
                if (!context.mounted) {
                  return;
                }
                await openGroupChat(
                  context,
                  ref,
                  group,
                  closeCurrentRouteOnDesktop: true,
                );
              } catch (error) {
                ref
                    .read(uiFeedbackProvider.notifier)
                    .showError(AppMessage.fromError(error));
              }
            },
            child: Text(context.l10n.commonJoin),
          ),
        ],
      ),
    );
  }
}

class GroupDetailPage extends ConsumerStatefulWidget {
  const GroupDetailPage({super.key, required this.initialGroup});

  final GroupSummary initialGroup;

  @override
  ConsumerState<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends ConsumerState<GroupDetailPage> {
  late GroupSummary _group;
  bool _didRequestMembers = false;
  bool _didRequestGroup = false;
  bool _isRefreshingMembers = false;

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup;
  }

  @override
  Widget build(BuildContext context) {
    _requestGroup(_group.groupId);
    _requestMembers(_group.groupId);
    final members = ref.watch(groupMembersProvider(_group.groupId));
    final currentDid = ref.watch(sessionProvider).session?.did;
    final canManageMembers = canManageGroupMembers(_group);
    final theme = context.awikiTheme;
    return Stack(
      children: <Widget>[
        CupertinoPageScaffold(
          backgroundColor: theme.background,
          child: AwikiAdaptiveScaffold(
            maxWidth: 900,
            includeBottomSafeArea: true,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    TopBarActionButton(
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: AwikiAssetIcon(
                          assetName: 'assets/icons/icon_left.svg',
                          color: theme.primaryDark,
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
                AppCardSection(
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
                                Text(
                                  _group.name,
                                  style: AwikiMeTextStyles.sectionTitle,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _group.description.isEmpty
                                      ? context.l10n.groupNoDescription
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
                          AppPill(
                            label: context.l10n.groupMemberCount(
                              _group.memberCount,
                            ),
                          ),
                          AppPill(label: _group.myRole ?? 'member'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      CopyableDidLine(
                        value: _group.groupId,
                        copySemanticLabel: '复制 Group DID',
                        copiedMessage: 'DID 已复制',
                        textKey: const Key('group-detail-did-value'),
                        buttonKey: const Key('group-detail-copy-did-button'),
                        textStyle: AwikiMeTextStyles.cardSubtitle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppCardSection(
                  color: members.isEmpty ? theme.subtleSurface : theme.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '成员',
                              style: AwikiMeTextStyles.sectionTitle,
                            ),
                          ),
                          if (canManageMembers) ...<Widget>[
                            _GroupDetailIconButton(
                              key: const Key('group-detail-add-member-button'),
                              semanticLabel: '添加成员',
                              icon: CupertinoIcons.person_add,
                              onTap: _showAddMemberDialog,
                            ),
                            const SizedBox(width: 8),
                          ],
                          _GroupDetailIconButton(
                            key: const Key(
                              'group-detail-refresh-members-button',
                            ),
                            semanticLabel: '刷新成员',
                            icon: CupertinoIcons.refresh,
                            isLoading: _isRefreshingMembers,
                            onTap: _isRefreshingMembers
                                ? null
                                : _refreshMembers,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (members.isEmpty)
                        Text(
                          context.l10n.groupMembersEmpty,
                          style: AwikiMeTextStyles.cardSubtitle,
                        )
                      else
                        Column(
                          children: members
                              .map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: GroupMemberRow(
                                    item: item,
                                    onRemove:
                                        canRemoveGroupMember(
                                          group: _group,
                                          member: item,
                                          currentDid: currentDid,
                                        )
                                        ? () => _confirmRemoveMember(item)
                                        : null,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _requestMembers(String groupId) {
    if (_didRequestMembers) {
      return;
    }
    _didRequestMembers = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      try {
        await ref.read(groupProvider.notifier).loadGroupMembers(groupId);
      } catch (_) {
        // Keep the page usable when the initial background member snapshot
        // cannot be loaded.
      }
    });
  }

  void _requestGroup(String groupId) {
    if (_didRequestGroup || _hasCompleteGroupRole(_group)) {
      return;
    }
    _didRequestGroup = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      try {
        final refreshed = await ref
            .read(groupProvider.notifier)
            .refreshGroup(groupId);
        if (!mounted) {
          return;
        }
        setState(() => _group = refreshed);
      } catch (_) {
        // Keep the group detail usable when the full snapshot cannot be loaded.
      }
    });
  }

  bool _hasCompleteGroupRole(GroupSummary group) {
    return _groupRoleRank(group.myRole) > 0;
  }

  Future<void> _refreshMembers() async {
    if (_isRefreshingMembers) {
      return;
    }
    setState(() {
      _isRefreshingMembers = true;
    });
    try {
      await ref.read(groupProvider.notifier).loadGroupMembers(_group.groupId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingMembers = false;
        });
      }
    }
  }

  void _showAddMemberDialog() {
    AppNavigator.showDialog<void>(
      context,
      (ctx) => AddGroupMemberDialog(
        groupId: _group.groupId,
        onGroupUpdated: (updated) {
          if (!mounted) {
            return;
          }
          setState(() => _group = updated);
        },
      ),
    );
  }

  Future<void> _confirmRemoveMember(GroupMemberSummary member) async {
    await showRemoveGroupMemberDialog(
      context: context,
      ref: ref,
      groupId: _group.groupId,
      member: member,
      onGroupUpdated: (updated) {
        if (!mounted) {
          return;
        }
        setState(() => _group = updated);
      },
    );
  }
}

class AddGroupMemberDialog extends ConsumerStatefulWidget {
  const AddGroupMemberDialog({
    super.key,
    required this.groupId,
    required this.onGroupUpdated,
  });

  final String groupId;
  final ValueChanged<GroupSummary> onGroupUpdated;

  @override
  ConsumerState<AddGroupMemberDialog> createState() =>
      _AddGroupMemberDialogState();
}

class _AddGroupMemberDialogState extends ConsumerState<AddGroupMemberDialog> {
  final TextEditingController _memberController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _memberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: const Text('添加成员'),
      content: Column(
        children: <Widget>[
          const SizedBox(height: 10),
          Text(
            '支持普通用户和智能体，输入 handle 或 DID 后会直接加入群聊。',
            style: AwikiMeTextStyles.cardSubtitle,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _memberController,
            label: '成员 handle 或 DID',
            placeholder: '输入 handle / DID',
            keyboardType: TextInputType.text,
            enabled: !_isSubmitting,
          ),
        ],
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        CupertinoDialogAction(
          isDefaultAction: !_isSubmitting,
          onPressed: _isSubmitting ? null : _addMember,
          child: _isSubmitting
              ? const CupertinoActivityIndicator()
              : const Text('添加'),
        ),
      ],
    );
  }

  Future<void> _addMember() async {
    final memberRef = _normalizeMemberRef(_memberController.text);
    if (memberRef.isEmpty) {
      return;
    }
    final groupNotifier = ref.read(groupProvider.notifier);
    final feedback = ref.read(uiFeedbackProvider.notifier);
    setState(() {
      _isSubmitting = true;
    });
    try {
      final updated = await groupNotifier.addGroupMember(
        groupId: widget.groupId,
        memberRef: memberRef,
      );
      widget.onGroupUpdated(updated);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
      });
      feedback.showError(AppMessage.fromError(error));
    }
  }
}

String _normalizeMemberRef(String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('@')) {
    return trimmed.substring(1).trim();
  }
  return trimmed;
}

class _GroupDetailIconButton extends StatelessWidget {
  const _GroupDetailIconButton({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    this.isLoading = false,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return AppIconButton(
      onPressed: isLoading ? null : onTap,
      semanticLabel: semanticLabel,
      tooltip: semanticLabel,
      isLoading: isLoading,
      size: responsive.scaled(34),
      backgroundColor: theme.surface,
      borderColor: const Color(0xFFDDE5F0),
      borderRadius: BorderRadius.circular(responsive.radius(8)),
      child: Icon(
        icon,
        color: const Color(0xFF34415C),
        size: responsive.iconSm,
      ),
    );
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
    return AppPressableTile(
      onTap: onTap,
      semanticLabel: group.name,
      borderRadius: BorderRadius.circular(AwikiMeRadii.md),
      child: AppCardSection(
        child: Row(
          children: <Widget>[
            AvatarBadge(seed: group.name, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(group.name, style: AwikiMeTextStyles.cardTitle),
                  const SizedBox(height: 6),
                  Text(
                    group.description.isEmpty
                        ? context.l10n.groupNoDescription
                        : group.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AwikiMeTextStyles.cardSubtitle,
                  ),
                  const SizedBox(height: 8),
                  AppPill(
                    label: context.l10n.groupMemberCountCompact(
                      group.memberCount,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AppIconButton(
              onPressed: onOpenDetail,
              semanticLabel: '查看群详情',
              tooltip: '查看群详情',
              size: context.awikiResponsive.compactControlHeight,
              child: AwikiAssetIcon(
                assetName: 'assets/icons/icon_right.svg',
                size: context.awikiResponsive.iconSm,
                color: context.awikiTheme.tertiaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GroupMemberRow extends StatelessWidget {
  const GroupMemberRow({super.key, required this.item, required this.onRemove});

  final GroupMemberSummary item;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final title = _handleLabel(item);
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Row(
      children: <Widget>[
        AvatarBadge(seed: title, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AwikiMeTextStyles.cardTitle,
          ),
        ),
        if (onRemove != null) ...<Widget>[
          const SizedBox(width: 8),
          AppIconButton(
            onPressed: onRemove,
            semanticLabel: '移除成员',
            tooltip: '移除成员',
            size: responsive.scaled(32),
            backgroundColor: theme.subtleSurface,
            borderColor: const Color(0xFFDDE5F0),
            borderRadius: BorderRadius.circular(responsive.radius(8)),
            child: Icon(
              CupertinoIcons.minus_circle,
              color: theme.secondaryText,
              size: responsive.iconSm,
            ),
          ),
        ],
      ],
    );
  }

  String _handleLabel(GroupMemberSummary item) {
    final handle = item.handle.trim();
    final did = item.did.trim();
    if (handle.isNotEmpty && handle != did) {
      return handle;
    }
    return DidDisplayFormatter.compactDid(did);
  }
}

Future<void> showRemoveGroupMemberDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String groupId,
  required GroupMemberSummary member,
  required ValueChanged<GroupSummary> onGroupUpdated,
}) async {
  final memberTitle = _memberDisplayLabel(member);
  await AppNavigator.showDialog<void>(
    context,
    (dialogContext) => CupertinoAlertDialog(
      title: const Text('移除成员'),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('移除 $memberTitle 后，对方将不能继续在这个群里发送消息。'),
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            try {
              final updated = await ref
                  .read(groupProvider.notifier)
                  .removeGroupMember(groupId: groupId, memberRef: member.did);
              onGroupUpdated(updated);
            } catch (error) {
              ref
                  .read(uiFeedbackProvider.notifier)
                  .showError(AppMessage.fromError(error));
            }
          },
          child: const Text('移除'),
        ),
      ],
    ),
  );
}

String _memberDisplayLabel(GroupMemberSummary member) {
  final handle = member.handle.trim();
  final did = member.did.trim();
  if (handle.isNotEmpty && handle != did) {
    return handle;
  }
  return DidDisplayFormatter.compactDid(did);
}

bool canManageGroupMembers(GroupSummary group) {
  final role = _groupRoleRank(group.myRole);
  return role >= _groupRoleRank('admin');
}

bool canRemoveGroupMember({
  required GroupSummary group,
  required GroupMemberSummary member,
  required String? currentDid,
}) {
  final actorRole = _groupRoleRank(group.myRole);
  if (actorRole < _groupRoleRank('admin')) {
    return false;
  }
  final memberDid = member.did.trim();
  if (currentDid != null &&
      currentDid.trim().isNotEmpty &&
      memberDid == currentDid.trim()) {
    return false;
  }
  final targetRole = _groupRoleRank(member.role);
  return actorRole > targetRole;
}

int _groupRoleRank(String? role) {
  switch (role?.trim()) {
    case 'owner':
      return 3;
    case 'admin':
      return 2;
    case 'member':
      return 1;
    default:
      return 0;
  }
}
