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
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
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

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup;
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(groupMembersProvider(_group.groupId));
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
                  child: Column(
                    children: <Widget>[
                      _ActionRow(title: '添加成员', onTap: _showAddMemberDialog),
                      const AppSectionDivider(),
                      _ActionRow(
                        title: context.l10n.groupRefreshSnapshot,
                        onTap: () async {
                          final refreshed = await ref
                              .read(groupProvider.notifier)
                              .refreshGroup(_group.groupId);
                          if (!mounted) {
                            return;
                          }
                          setState(() => _group = refreshed);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppCardSection(
                  color: members.isEmpty ? theme.subtleSurface : theme.surface,
                  child: members.isEmpty
                      ? Text(
                          context.l10n.groupMembersEmpty,
                          style: AwikiMeTextStyles.cardSubtitle,
                        )
                      : Column(
                          children: members
                              .map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _MemberRow(item: item),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showAddMemberDialog() {
    final memberController = TextEditingController();
    AppNavigator.showDialog<void>(
      context,
      (ctx) => CupertinoAlertDialog(
        title: const Text('添加成员'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AppTextField(
            controller: memberController,
            label: '成员 DID',
            placeholder: '请输入成员 DID',
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
              final memberDid = memberController.text.trim();
              if (memberDid.isEmpty) {
                return;
              }
              Navigator.of(ctx).pop();
              try {
                final updated = await ref
                    .read(groupProvider.notifier)
                    .addGroupMember(
                      groupId: _group.groupId,
                      memberDid: memberDid,
                    );
                if (!mounted) {
                  return;
                }
                setState(() => _group = updated);
              } catch (error) {
                ref
                    .read(uiFeedbackProvider.notifier)
                    .showError(AppMessage.fromError(error));
              }
            },
            child: const Text('添加'),
          ),
        ],
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
    return GestureDetector(
      onTap: onTap,
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
            GestureDetector(
              onTap: onOpenDetail,
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

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: AppActionRow(title: title, onTap: onTap),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.item});

  final GroupMemberSummary item;

  @override
  Widget build(BuildContext context) {
    final title = item.handle.trim().isEmpty ? item.did : item.handle.trim();
    return Row(
      children: <Widget>[
        AvatarBadge(seed: title, size: 36),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: AwikiMeTextStyles.cardTitle)),
        AppPill(label: item.role),
      ],
    );
  }
}
