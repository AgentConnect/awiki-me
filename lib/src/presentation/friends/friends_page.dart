import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../domain/entities/relationship_summary.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../../app/ui_feedback.dart';
import '../app_shell/providers/session_provider.dart';
import '../group/group_list_page.dart';
import '../profile/peer_display_profile_provider.dart';
import '../profile/peer_profile_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/app_dialog.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/awiki_me_semantic_icon.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/quick_actions.dart';
import '../shared/responsive_layout.dart';
import '../shared/sidebar_workspace.dart';
import '../shared/widgets/app_widgets.dart';
import 'friends_provider.dart';

class FriendsPage extends ConsumerWidget {
  const FriendsPage({
    super.key,
    this.embedded = false,
    this.bottomInset = 120,
    this.onGroupTap,
    this.onFollowingTap,
    this.onFollowersTap,
    this.onContactTap,
  });

  final bool embedded;
  final double bottomInset;
  final VoidCallback? onGroupTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onFollowersTap;
  final ValueChanged<RelationshipSummary>? onContactTap;

  Future<void> _openContact(
    BuildContext context,
    RelationshipSummary item,
  ) async {
    final callback = onContactTap;
    if (callback != null) {
      callback(item);
      return;
    }
    await AppNavigator.push(context, (_) => PeerProfilePage(did: item.did));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final responsive = context.awikiResponsive;
    final state = ref.watch(friendsProvider);
    final theme = context.awikiTheme;
    final following = state.following.take(_previewLimit).toList();
    final followers = state.followers.take(_previewLimit).toList();
    final openGroups =
        onGroupTap ??
        () => AppNavigator.push(context, (_) => const GroupListPage());
    final sectionWidgets = <Widget>[
      Padding(
        padding: EdgeInsets.only(top: responsive.spacing(12)),
        child: _FriendRow.group(
          title: context.l10n.friendsGroups,
          subtitle: context.l10n.friendsGroupsSubtitle,
          onTap: openGroups,
        ),
      ),
      _FriendsSection(
        title: context.l10n.friendsFollowing,
        trailingLabel: following.isEmpty ? null : context.l10n.friendsViewAll,
        trailingKey: following.isEmpty
            ? null
            : const Key('friends-following-view-all'),
        onTrailingTap: following.isEmpty
            ? null
            : () => _openRelationshipList(
                context,
                FriendsRelationshipListType.following,
              ),
        children: state.followingError != null
            ? <Widget>[
                _FriendsPreviewStatus(
                  message: context.l10n.operationFailedRetry,
                  onRetry: () => ref.read(friendsProvider.notifier).refresh(),
                ),
              ]
            : following.isEmpty
            ? <Widget>[
                _FriendsPreviewStatus(
                  message: context.l10n.friendsFollowingEmpty,
                ),
              ]
            : following
                  .map(
                    (item) => _FriendRow.contact(
                      rowKey: Key('contact-row:${item.did.trim()}'),
                      titleKey: Key('contact-row-title:${item.did.trim()}'),
                      seed: _displayName(ref, item),
                      title: _displayName(ref, item),
                      subtitle: _handleLabel(item.handle),
                      avatarUri: _avatarUri(ref, item),
                      onTap: () => _openContact(context, item),
                    ),
                  )
                  .toList(),
      ),
      _FriendsSection(
        title: context.l10n.friendsFollowers,
        trailingLabel: followers.isEmpty ? null : context.l10n.friendsViewAll,
        trailingKey: followers.isEmpty
            ? null
            : const Key('friends-followers-view-all'),
        onTrailingTap: followers.isEmpty
            ? null
            : () => _openRelationshipList(
                context,
                FriendsRelationshipListType.followers,
              ),
        children: state.followersError != null
            ? <Widget>[
                _FriendsPreviewStatus(
                  message: context.l10n.operationFailedRetry,
                  onRetry: () => ref.read(friendsProvider.notifier).refresh(),
                ),
              ]
            : followers.isEmpty
            ? <Widget>[
                _FriendsPreviewStatus(
                  message: context.l10n.friendsFollowersEmpty,
                ),
              ]
            : followers
                  .map(
                    (item) => _FriendRow.contact(
                      rowKey: Key('contact-row:${item.did.trim()}'),
                      titleKey: Key('contact-row-title:${item.did.trim()}'),
                      seed: _displayName(ref, item),
                      title: _displayName(ref, item),
                      subtitle: _handleLabel(item.handle),
                      avatarUri: _avatarUri(ref, item),
                      trailing: state.isFollowing(item.did)
                          ? null
                          : _RelationshipActionButton(
                              label: context.l10n.friendsFollow,
                              onTap: () => _runRelationshipAction(
                                ref,
                                () => ref
                                    .read(friendsProvider.notifier)
                                    .follow(item.did),
                              ),
                            ),
                      onTap: () => _openContact(context, item),
                    ),
                  )
                  .toList(),
      ),
    ];
    if (state.isLoading) {
      sectionWidgets.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    }

    final list = Padding(
      padding: embedded
          ? EdgeInsets.only(bottom: bottomInset)
          : EdgeInsets.zero,
      child: DecoratedBox(
        key: const Key('friends-list-surface'),
        decoration: BoxDecoration(
          color: responsive.isCompact ? theme.surface : theme.background,
        ),
        child: ListView(
          padding: embedded
              ? EdgeInsets.zero
              : EdgeInsets.only(bottom: bottomInset),
          children: sectionWidgets,
        ),
      ),
    );

    if (embedded) {
      return Column(
        children: <Widget>[
          AwikiSidebarHeader(
            key: const Key('friends-expanded-list-header'),
            title: context.l10n.friendsTitle,
            trailing: Builder(
              builder: (anchorContext) => TopBarActionButton(
                key: const Key('shell-quick-actions-button'),
                onTap: () => showCommonQuickActionsMenu(
                  anchorContext,
                  ref,
                  anchoredToTrigger: true,
                ),
                semanticsIdentifier: 'e2e-quick-actions-button',
                semanticsLabel: context.l10n.commonMoreActions,
                child: AwikiMeSemanticIcon(
                  role: AwikiMeIconRole.add,
                  size: responsive.iconMd,
                  color: theme.secondaryText,
                ),
              ),
            ),
          ),
          Expanded(child: list),
        ],
      );
    }

    final content = AwikiMeShellTabPage(
      key: const Key('friends-page-surface'),
      title: context.l10n.friendsTitle,
      onQuickActionsTap: (anchorContext) => showCommonQuickActionsMenu(
        anchorContext,
        ref,
        anchoredToTrigger: true,
      ),
      child: list,
    );
    return AwikiAdaptiveScaffold(
      maxWidth: responsive.supportsTwoPane ? double.infinity : 920,
      padding: responsive.isCompact ? EdgeInsets.zero : null,
      child: content,
    );
  }

  void _openRelationshipList(
    BuildContext context,
    FriendsRelationshipListType type,
  ) {
    final callback = switch (type) {
      FriendsRelationshipListType.following => onFollowingTap,
      FriendsRelationshipListType.followers => onFollowersTap,
    };
    if (callback != null) {
      callback();
      return;
    }
    AppNavigator.push(context, (_) => RelationshipListPage(type: type));
  }
}

const int _previewLimit = 3;

String _displayName(WidgetRef ref, RelationshipSummary item) {
  return ref.watch(
    peerDisplayNameProvider(
      PeerDisplayNameRequest(
        did: item.did,
        nickname: item.displayName,
        fullHandle: item.handle,
      ),
    ),
  );
}

String? _avatarUri(WidgetRef ref, RelationshipSummary item) {
  return peerAvatarUri(ref.watch(peerDisplayProfileProvider), item.did) ??
      item.avatarUri;
}

String? _handleLabel(String? handle) {
  final value = handle?.trim() ?? '';
  if (value.isEmpty) {
    return null;
  }
  return value.startsWith('@') ? value : '@$value';
}

class _FriendsSection extends StatelessWidget {
  const _FriendsSection({
    required this.title,
    required this.children,
    this.trailingLabel,
    this.trailingKey,
    this.onTrailingTap,
  });

  final String title;
  final List<Widget> children;
  final String? trailingLabel;
  final Key? trailingKey;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Padding(
      padding: EdgeInsets.only(top: responsive.spacing(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: responsive.tabContentHorizontalPadding,
              vertical: responsive.spacing(6),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: theme.secondaryText,
                      fontSize: responsive.metaSm,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (trailingLabel != null && onTrailingTap != null)
                  AppPressableText(
                    key: trailingKey,
                    onTap: onTrailingTap,
                    semanticLabel: trailingLabel,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Text(
                        trailingLabel!,
                        style: TextStyle(
                          color: theme.primary,
                          fontSize: responsive.metaSm,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _FriendsPreviewStatus extends StatelessWidget {
  const _FriendsPreviewStatus({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.tabContentHorizontalPadding,
        vertical: responsive.spacing(12),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: responsive.bodySm,
              ),
            ),
          ),
          if (onRetry != null)
            CupertinoButton(
              key: const Key('friends-preview-retry'),
              padding: EdgeInsets.symmetric(
                horizontal: responsive.spacing(10),
                vertical: responsive.spacing(4),
              ),
              onPressed: onRetry,
              child: Text(context.l10n.commonRetry),
            ),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow.contact({
    required this.rowKey,
    required this.titleKey,
    required this.seed,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.avatarUri,
  }) : isGroup = false;

  const _FriendRow.group({
    required this.title,
    required this.onTap,
    this.subtitle,
  }) : isGroup = true,
       rowKey = const Key('friends-groups-row'),
       titleKey = null,
       seed = 'group',
       trailing = null,
       avatarUri = null;

  final bool isGroup;
  final Key rowKey;
  final Key? titleKey;
  final String seed;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final String? avatarUri;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Container(
      key: rowKey,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.border)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.tabContentHorizontalPadding,
        ),
        child: AppListTile(
          horizontalPadding: 0,
          title: title,
          subtitle: subtitle,
          titleKey: titleKey,
          trailing: trailing,
          leading: isGroup
              ? AppSurface(
                  padding: EdgeInsets.zero,
                  color: theme.colorScheme.secondaryContainer,
                  radius: AwikiMeRadii.pill,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  child: Icon(
                    CupertinoIcons.person_3_fill,
                    color: theme.colorScheme.onSecondaryContainer,
                    size: 20,
                  ),
                )
              : AvatarBadge(seed: seed, size: 32, avatarUri: avatarUri),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _RelationshipActionButton extends StatelessWidget {
  const _RelationshipActionButton({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final Future<void> Function() onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return _RelationshipActionButtonInner(
      label: label,
      onTap: onTap,
      destructive: destructive,
    );
  }
}

class _RelationshipActionButtonInner extends StatefulWidget {
  const _RelationshipActionButtonInner({
    required this.label,
    required this.onTap,
    required this.destructive,
  });

  final String label;
  final Future<void> Function() onTap;
  final bool destructive;

  @override
  State<_RelationshipActionButtonInner> createState() =>
      _RelationshipActionButtonInnerState();
}

class _RelationshipActionButtonInnerState
    extends State<_RelationshipActionButtonInner> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final background = widget.destructive
        ? theme.dangerContainer
        : theme.primary.withValues(alpha: 0.08);
    final foreground = widget.destructive ? theme.danger : theme.primaryDark;
    return AppPressable(
      onTap: _isBusy
          ? null
          : () async {
              setState(() => _isBusy = true);
              try {
                await widget.onTap();
              } finally {
                if (mounted) {
                  setState(() => _isBusy = false);
                }
              }
            },
      semanticLabel: widget.label,
      tooltip: widget.label,
      enabled: !_isBusy,
      scaleOnPress: true,
      pressedScale: 0.97,
      borderRadius: BorderRadius.circular(8),
      builder: (context, state, child) {
        return AnimatedOpacity(
          opacity: state.pressed
              ? 0.80
              : state.hovered || state.focused
              ? 0.92
              : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      child: Container(
        height: 30,
        constraints: const BoxConstraints(minWidth: 58),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: _isBusy
            ? CupertinoActivityIndicator(
                key: const Key('relationship-action-progress'),
                radius: 7,
                color: widget.destructive ? theme.danger : null,
              )
            : Text(
                widget.label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }
}

class RelationshipListPage extends ConsumerStatefulWidget {
  const RelationshipListPage({
    super.key,
    required this.type,
    this.embedded = false,
    this.showTopBar = true,
    this.bottomInset = 28,
    this.onContactTap,
  });

  final FriendsRelationshipListType type;
  final bool embedded;
  final bool showTopBar;
  final double bottomInset;
  final ValueChanged<RelationshipSummary>? onContactTap;

  @override
  ConsumerState<RelationshipListPage> createState() =>
      _RelationshipListPageState();
}

class _RelationshipListPageState extends ConsumerState<RelationshipListPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(relationshipListProvider(widget.type));
    final friendsState = ref.watch(friendsProvider);
    final theme = context.awikiTheme;
    final title = switch (widget.type) {
      FriendsRelationshipListType.following => context.l10n.friendsFollowing,
      FriendsRelationshipListType.followers => context.l10n.friendsFollowers,
    };
    // A follower remains part of the Followers list after we follow them back.
    // Relationship state only changes the row action; it must not change list
    // membership returned by the Core relationship query.
    final items = listState.items;
    final headerCount = widget.showTopBar ? 1 : 0;
    final itemCount = headerCount + (items.isEmpty ? 1 : items.length + 1);
    final content = Stack(
      children: <Widget>[
        ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            0,
            widget.showTopBar ? (widget.embedded ? 22 : 14) : 0,
            0,
            widget.bottomInset,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (widget.showTopBar && index == 0) {
              return Column(
                children: <Widget>[
                  AwikiMeTopBar(
                    title: title,
                    padding: EdgeInsets.zero,
                    trailingWidth: 42,
                    leading: widget.embedded
                        ? const SizedBox.shrink()
                        : TopBarActionButton(
                            key: const Key('relationship-list-back-button'),
                            onTap: () => Navigator.of(context).pop(),
                            semanticsLabel: context.l10n.commonBack,
                            child: AwikiAssetIcon(
                              assetName: 'assets/icons/icon_left.svg',
                              color: theme.primaryDark,
                              size: 22,
                            ),
                          ),
                    trailing: TopBarActionButton(
                      onTap: () => ref
                          .read(relationshipListProvider(widget.type).notifier)
                          .refresh(),
                      child: Icon(
                        CupertinoIcons.refresh,
                        color: theme.title,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            }
            final contentIndex = index - headerCount;
            if (items.isEmpty && contentIndex == 0) {
              if (listState.error != null) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: AwikiMeErrorNotice(
                    message: AppMessage.fromError(
                      listState.error!,
                    ).resolve(context.l10n),
                    trailing: AppSecondaryButton(
                      label: context.l10n.commonRetry,
                      onPressed: () => ref
                          .read(relationshipListProvider(widget.type).notifier)
                          .refresh(),
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: AppCardSection(
                  color: theme.subtleSurface,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.type == FriendsRelationshipListType.following
                        ? context.l10n.friendsFollowingEmpty
                        : context.l10n.friendsFollowersEmpty,
                    style: AwikiMeTextStyles.cardSubtitle,
                  ),
                ),
              );
            }
            if (contentIndex == items.length) {
              return _RelationshipListFooter(
                state: listState,
                onLoadMore: () => ref
                    .read(relationshipListProvider(widget.type).notifier)
                    .loadMore(),
              );
            }
            final item = items[contentIndex];
            final displayName = _displayName(ref, item);
            final isFollowing = friendsState.isFollowing(item.did);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _FriendRow.contact(
                rowKey: Key('contact-row:${item.did.trim()}'),
                titleKey: Key('contact-row-title:${item.did.trim()}'),
                seed: displayName,
                title: displayName,
                subtitle: _handleLabel(item.handle),
                avatarUri: _avatarUri(ref, item),
                trailing: isFollowing
                    ? _RelationshipActionButton(
                        label: context.l10n.friendsUnfollow,
                        destructive: true,
                        onTap: () => confirmAndUnfollow(context, ref, item.did),
                      )
                    : _RelationshipActionButton(
                        label: context.l10n.friendsFollow,
                        onTap: () => _runRelationshipAction(
                          ref,
                          () => ref
                              .read(friendsProvider.notifier)
                              .follow(item.did),
                        ),
                      ),
                onTap: () => _openContact(context, item: item),
              ),
            );
          },
        ),
        if (listState.isLoading)
          AwikiMeLoadingMask(label: context.l10n.commonLoading),
      ],
    );

    if (widget.embedded) {
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

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.extentAfter > 320) {
      return;
    }
    ref.read(relationshipListProvider(widget.type).notifier).loadMore();
  }

  Future<void> _openContact(
    BuildContext context, {
    required RelationshipSummary item,
  }) async {
    final callback = widget.onContactTap;
    if (callback != null) {
      callback(item);
      return;
    }
    await AppNavigator.push(context, (_) => PeerProfilePage(did: item.did));
  }
}

class _RelationshipListFooter extends StatelessWidget {
  const _RelationshipListFooter({
    required this.state,
    required this.onLoadMore,
  });

  final RelationshipListState state;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading || (!state.hasMore && !state.isLoadingMore)) {
      return const SizedBox(height: 24);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: state.isLoadingMore
          ? const Center(child: CupertinoActivityIndicator())
          : AppSecondaryButton(
              label: context.l10n.commonLoadMore,
              onPressed: onLoadMore,
            ),
    );
  }
}

Future<void> confirmAndUnfollow(
  BuildContext context,
  WidgetRef ref,
  String did,
) async {
  final confirmed = await AppNavigator.showDialog<bool>(
    context,
    (ctx) => AppConfirmationDialog(
      title: context.l10n.friendsUnfollowTitle,
      message: context.l10n.friendsUnfollowMessage,
      confirmLabel: context.l10n.friendsUnfollow,
      confirmButtonKey: const Key('confirm-unfollow-button'),
      destructive: true,
      onCancel: () => Navigator.of(ctx).pop(false),
      onConfirm: () => Navigator.of(ctx).pop(true),
    ),
  );
  if (confirmed != true) {
    return;
  }
  try {
    await ref.read(friendsProvider.notifier).unfollow(did);
  } catch (error) {
    if (isSessionEpochChangedError(error)) {
      return;
    }
    ref
        .read(uiFeedbackProvider.notifier)
        .showError(AppMessage.fromError(error));
  }
}

Future<void> _runRelationshipAction(
  WidgetRef ref,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (isSessionEpochChangedError(error)) {
      return;
    }
    ref
        .read(uiFeedbackProvider.notifier)
        .showError(AppMessage.fromError(error));
  }
}
