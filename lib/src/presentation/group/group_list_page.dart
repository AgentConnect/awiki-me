import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../app/ui_feedback.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_identity.dart';
import '../../domain/entities/group_summary.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/avatar_badge.dart';
import '../shared/copyable_did_line.dart';
import '../shared/responsive_layout.dart';
import '../shared/semantic_pill.dart';
import '../shared/widgets/app_widgets.dart';
import '../app_shell/providers/session_provider.dart';
import '../profile/peer_display_profile_provider.dart';
import 'create_group_dialog.dart';
import 'group_chat_navigation.dart';
import 'group_member_invite_dialog.dart';
import 'group_provider.dart';

class GroupListPage extends ConsumerWidget {
  const GroupListPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(groupProvider);
    final theme = context.awikiTheme;
    Future<void> refreshGroups() async {
      try {
        await ref.read(groupProvider.notifier).refresh();
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ref
            .read(uiFeedbackProvider.notifier)
            .showError(AppMessage.fromError(error));
      }
    }

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
                    onTap: refreshGroups,
                    child: Icon(
                      CupertinoIcons.refresh,
                      color: theme.title,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TopBarActionButton(
                    key: const Key('group-list-create-button'),
                    semanticsLabel: context.l10n.quickActionCreateGroup,
                    onTap: () => showCreateGroupDialog(
                      context,
                      ref,
                      closeCurrentRouteOnDesktop: !embedded,
                      replaceCurrentRouteOnPhone: !embedded,
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
            if (state.recoverySummary != null) ...<Widget>[
              _GroupRecoveryStatusBand(
                summary: state.recoverySummary!,
                isLoading: state.isResumingRecovery,
                onRetry: () async {
                  try {
                    final summary = await ref
                        .read(groupProvider.notifier)
                        .resumeRebindRecovery();
                    if (!context.mounted) {
                      return;
                    }
                    final feedback = ref.read(uiFeedbackProvider.notifier);
                    if (summary.hasBlocked) {
                      feedback.showInfo(
                        AppMessage.groupRecoveryBlocked(summary.blocked),
                      );
                    } else if (summary.hasPending) {
                      feedback.showInfo(
                        AppMessage.groupRecoveryPending(summary.pending),
                      );
                    } else {
                      feedback.showInfo(AppMessage.groupRecoveryCompleted());
                    }
                  } catch (error) {
                    ref
                        .read(uiFeedbackProvider.notifier)
                        .showError(AppMessage.fromError(error));
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
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

  Future<void> _showJoinDialog(BuildContext context, WidgetRef ref) async {
    final textController = TextEditingController();
    final session = ref.read(sessionProvider).session;
    final activeHandle = groupHandleForDid(
      handle: session?.handle,
      did: session?.did ?? '',
    );
    try {
      await AppNavigator.showDialog<void>(
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
                  final identity = GroupIdentitySelection.handle(
                    activeHandle ?? '',
                  );
                  final group = await ref
                      .read(groupProvider.notifier)
                      .joinGroup(groupDid, identity: identity);
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
    } finally {
      textController.dispose();
    }
  }
}

class _GroupRecoveryStatusBand extends StatelessWidget {
  const _GroupRecoveryStatusBand({
    required this.summary,
    required this.isLoading,
    required this.onRetry,
  });

  final GroupRebindRecoverySummary summary;
  final bool isLoading;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final title = summary.hasBlocked
        ? context.l10n.groupRecoveryBlocked(summary.blocked)
        : summary.hasPending
        ? context.l10n.groupRecoveryPending(summary.pending)
        : context.l10n.groupRecoveryCompleted;
    final accent = summary.hasBlocked
        ? const Color(0xFFB42318)
        : summary.hasPending
        ? const Color(0xFF8A5A00)
        : const Color(0xFF067647);
    return Container(
      key: const Key('group-recovery-status-band'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: AwikiMeTextStyles.cardTitle.copyWith(color: accent),
                ),
              ),
              Semantics(
                label: context.l10n.groupRecoveryRetry,
                button: true,
                child: CupertinoButton(
                  key: const Key('group-recovery-retry-button'),
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(40, 40),
                  onPressed: isLoading ? null : onRetry,
                  child: isLoading
                      ? const CupertinoActivityIndicator(radius: 9)
                      : Icon(CupertinoIcons.refresh, color: accent, size: 19),
                ),
              ),
            ],
          ),
          if (summary.items.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            for (final item in summary.items.take(6))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.groupDid,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AwikiMeTextStyles.cardSubtitle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _recoveryLayerLabel(context, item.layer),
                      style: AwikiMeTextStyles.cardSubtitle,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _recoveryPhaseLabel(context, item),
                      style: AwikiMeTextStyles.cardSubtitle.copyWith(
                        color: item.blocked ? accent : theme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

String _recoveryLayerLabel(BuildContext context, String layer) {
  return layer == 'p6'
      ? context.l10n.groupRecoveryEncryptionLayer
      : context.l10n.groupRecoveryMembershipLayer;
}

String _recoveryPhaseLabel(BuildContext context, GroupRebindRecoveryItem item) {
  if (item.blocked || item.phase == 'blocked') {
    return context.l10n.groupRecoveryPhaseBlocked;
  }
  if (item.phase == 'complete' || item.phase == 'completed') {
    return context.l10n.groupRecoveryPhaseCompleted;
  }
  return context.l10n.groupRecoveryPhasePending;
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
                        _group.displayName,
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
                          AvatarBadge(
                            seed: _group.displayName,
                            size: 56,
                            avatarUri: _group.avatarUri,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  _group.displayName,
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
                          SemanticPill(
                            label: context.l10n.conversationPeerTypeGroup,
                            tone: SemanticPillTone.identity,
                          ),
                          SemanticPill(
                            label: context.l10n.groupMemberCount(
                              _group.memberCount,
                            ),
                            tone: SemanticPillTone.metadata,
                          ),
                          SemanticPill(
                            label: _group.myRole ?? 'member',
                            tone: SemanticPillTone.relationship,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      CopyableDidLine(
                        value: _group.groupId,
                        copySemanticLabel: context.l10n.chatPeerInfoCopyDid,
                        copiedMessage: context.l10n.chatPeerInfoDidCopied,
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
                              context.l10n.groupMembersTitle,
                              style: AwikiMeTextStyles.sectionTitle,
                            ),
                          ),
                          _GroupDetailIconButton(
                            key: const Key('group-detail-add-member-button'),
                            semanticLabel: context.l10n.groupAddMembers,
                            icon: CupertinoIcons.person_add,
                            onTap: canManageMembers
                                ? () => _showAddMemberDialog(members)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          _GroupDetailIconButton(
                            key: const Key(
                              'group-detail-refresh-members-button',
                            ),
                            semanticLabel: context.l10n.groupRefreshMembers,
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
                                    showRemoveButton: true,
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

  void _showAddMemberDialog(List<GroupMemberSummary> members) {
    AppNavigator.showDialog<void>(
      context,
      (ctx) => AddGroupMemberDialog(
        groupId: _group.groupId,
        existingMembers: members,
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

class AddGroupMemberDialog extends ConsumerWidget {
  const AddGroupMemberDialog({
    super.key,
    required this.groupId,
    required this.existingMembers,
    required this.onGroupUpdated,
  });

  final String groupId;
  final List<GroupMemberSummary> existingMembers;
  final ValueChanged<GroupSummary> onGroupUpdated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupState = ref.watch(groupProvider);
    final members = groupState.membersByGroup.containsKey(groupId)
        ? groupState.membersByGroup[groupId]!
        : existingMembers;
    return GroupMemberInviteDialog(
      groupId: groupId,
      existingMembers: members,
      onGroupUpdated: onGroupUpdated,
    );
  }
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
    final enabled = onTap != null && !isLoading;
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
        color: enabled ? const Color(0xFF34415C) : theme.tertiaryText,
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
            AvatarBadge(
              seed: group.displayName,
              size: 52,
              avatarUri: group.avatarUri,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(group.displayName, style: AwikiMeTextStyles.cardTitle),
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
                  SemanticPill(
                    label: context.l10n.groupMemberCountCompact(
                      group.memberCount,
                    ),
                    tone: SemanticPillTone.metadata,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AppIconButton(
              onPressed: onOpenDetail,
              semanticLabel: context.l10n.groupDetails,
              tooltip: context.l10n.groupDetails,
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

class GroupMemberRow extends ConsumerWidget {
  const GroupMemberRow({
    super.key,
    required this.item,
    required this.onRemove,
    this.showRemoveButton = false,
  });

  final GroupMemberSummary item;
  final VoidCallback? onRemove;
  final bool showRemoveButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(
      peerDisplayNameProvider(_memberDisplayNameRequest(item)),
    );
    final identityLabel = _memberIdentityLabel(item);
    final avatarUri =
        peerAvatarUri(
          ref.watch(peerDisplayProfileProvider),
          item.did,
          peerPersonaId: item.peerPersonaId,
        ) ??
        item.avatarUri;
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Row(
      children: <Widget>[
        AvatarBadge(seed: title, size: 36, avatarUri: avatarUri),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                key: Key(
                  'group-member-title:${groupMemberPresentationKey(item)}',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AwikiMeTextStyles.cardTitle,
              ),
              if (identityLabel != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  identityLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AwikiMeTextStyles.cardSubtitle,
                ),
              ],
            ],
          ),
        ),
        if (showRemoveButton || onRemove != null) ...<Widget>[
          const SizedBox(width: 8),
          AppIconButton(
            onPressed: onRemove,
            semanticLabel: context.l10n.groupRemoveMember,
            tooltip: context.l10n.groupRemoveMember,
            size: responsive.scaled(32),
            backgroundColor: theme.subtleSurface,
            borderColor: const Color(0xFFDDE5F0),
            borderRadius: BorderRadius.circular(responsive.radius(8)),
            child: Icon(
              CupertinoIcons.minus_circle,
              color: onRemove == null
                  ? theme.tertiaryText
                  : theme.secondaryText,
              size: responsive.iconSm,
            ),
          ),
        ],
      ],
    );
  }
}

Future<void> showRemoveGroupMemberDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String groupId,
  required GroupMemberSummary member,
  required ValueChanged<GroupSummary> onGroupUpdated,
}) async {
  final memberTitle = ref.read(
    peerDisplayNameProvider(_memberDisplayNameRequest(member)),
  );
  await AppNavigator.showDialog<void>(
    context,
    (dialogContext) => CupertinoAlertDialog(
      title: Text(context.l10n.groupRemoveMember),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(context.l10n.groupRemoveMemberContent(memberTitle)),
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
                  .removeGroupMember(
                    groupId: groupId,
                    memberRef: _memberProtocolRef(member),
                  );
              onGroupUpdated(updated);
            } catch (error) {
              ref
                  .read(uiFeedbackProvider.notifier)
                  .showError(AppMessage.fromError(error));
            }
          },
          child: Text(context.l10n.groupRemoveMember),
        ),
      ],
    ),
  );
}

PeerDisplayNameRequest _memberDisplayNameRequest(GroupMemberSummary member) {
  return PeerDisplayNameRequest(
    peerPersonaId: member.peerPersonaId,
    did: member.did,
    nickname: member.displayName,
    fullHandle: member.handle,
  );
}

String? _memberIdentityLabel(GroupMemberSummary member) {
  final handle = member.handle.trim();
  final did = member.did.trim();
  if (handle.isEmpty || handle == did) {
    return null;
  }
  return '@$handle';
}

String _memberProtocolRef(GroupMemberSummary member) {
  final handle = member.handle.trim();
  return handle.isEmpty ? member.did.trim() : handle;
}

String groupMemberPresentationKey(GroupMemberSummary member) {
  final membershipId = member.membershipId?.trim() ?? '';
  if (membershipId.isNotEmpty) {
    return membershipId;
  }
  final peerPersonaId = member.peerPersonaId?.trim() ?? '';
  if (peerPersonaId.isNotEmpty) {
    return peerPersonaId;
  }
  return member.did.trim();
}

bool canManageGroupMembers(GroupSummary group) {
  final role = _groupRoleRank(group.myRole);
  return role >= _groupRoleRank('admin');
}

bool hasKnownGroupRole(GroupSummary group) {
  return _groupRoleRank(group.myRole) > 0;
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
