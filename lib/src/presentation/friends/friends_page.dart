import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../domain/entities/relationship_summary.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../../app/ui_feedback.dart';
import '../group/group_list_page.dart';
import '../settings/settings_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/identity_flow.dart';
import '../shared/quick_actions.dart';
import '../shared/responsive_layout.dart';
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
  });

  final bool embedded;
  final double bottomInset;
  final VoidCallback? onGroupTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onFollowersTap;

  Future<void> _openContact(
    BuildContext context,
    WidgetRef ref,
    RelationshipSummary item,
  ) async {
    await openDirectConversationForDid(
      context,
      ref,
      peerDid: item.did,
      peerHandle: item.handle,
      peerName: _displayName(item),
      avatarUri: item.avatarUri,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(friendsProvider);
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final following = state.following.take(_previewLimit).toList();
    final followers = state.followers
        .where((item) => !state.isFollowing(item.did))
        .take(_previewLimit)
        .toList();
    final openGroups =
        onGroupTap ??
        () => AppNavigator.push(context, (_) => const GroupListPage());
    final sectionWidgets = <Widget>[
      Padding(
        padding: EdgeInsets.only(top: responsive.spacing(12)),
        child: _FriendRow.group(
          title: context.l10n.friendsGroups,
          onTap: openGroups,
        ),
      ),
      if (following.isNotEmpty)
        _FriendsSection(
          title: context.l10n.friendsFollowing,
          trailingLabel: context.l10n.friendsViewAll,
          onTrailingTap: () => _openRelationshipList(
            context,
            FriendsRelationshipListType.following,
          ),
          children: following
              .map(
                (item) => _FriendRow.contact(
                  seed: _displayName(item),
                  title: _displayName(item),
                  avatarUri: item.avatarUri,
                  onTap: () => _openContact(context, ref, item),
                ),
              )
              .toList(),
        ),
      if (followers.isNotEmpty)
        _FriendsSection(
          title: context.l10n.friendsFollowers,
          trailingLabel: context.l10n.friendsViewAll,
          onTrailingTap: () => _openRelationshipList(
            context,
            FriendsRelationshipListType.followers,
          ),
          children: followers
              .map(
                (item) => _FriendRow.contact(
                  seed: _displayName(item),
                  title: _displayName(item),
                  avatarUri: item.avatarUri,
                  trailing: _RelationshipActionButton(
                    label: context.l10n.friendsFollow,
                    onTap: () => _runRelationshipAction(
                      ref,
                      () => ref.read(friendsProvider.notifier).follow(item.did),
                    ),
                  ),
                  onTap: () => _openContact(context, ref, item),
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

    if (!responsive.supportsTwoPane) {
      final mobileContent = AwikiMeShellTabPage(
        title: context.l10n.friendsTitle,
        onSettingsTap: responsive.isMacDesktop
            ? null
            : () => AppNavigator.pushWithoutAnimation(
                context,
                (_) => const SettingsPage(),
              ),
        onQuickActionsTap: () => showCommonQuickActionsMenu(context, ref),
        child: ListView(
          padding: EdgeInsets.only(bottom: embedded ? bottomInset : 120),
          children: sectionWidgets,
        ),
      );
      if (embedded) {
        return mobileContent;
      }
      return mobileContent;
    }

    final content = AwikiMeShellTabPage(
      title: context.l10n.friendsTitle,
      onSettingsTap: responsive.isMacDesktop
          ? null
          : () => AppNavigator.pushWithoutAnimation(
              context,
              (_) => const SettingsPage(),
            ),
      onQuickActionsTap: () => showCommonQuickActionsMenu(context, ref),
      child: Padding(
        padding: EdgeInsets.only(bottom: embedded ? bottomInset : 120),
        child: DecoratedBox(
          decoration: BoxDecoration(color: theme.background),
          child: Stack(
            children: <Widget>[
              ListView(
                padding: EdgeInsets.only(right: responsive.spacing(24)),
                children: sectionWidgets,
              ),
              Positioned(
                top: 0,
                right: responsive.spacing(8),
                bottom: 0,
                child: const _IndexRail(),
              ),
            ],
          ),
        ),
      ),
    );

    if (embedded) {
      return content;
    }

    return AwikiAdaptiveScaffold(
      maxWidth: responsive.supportsTwoPane ? double.infinity : 920,
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

String _displayName(RelationshipSummary item) {
  return DidDisplayFormatter.compactDisplayName(
    displayName: item.displayName,
    fallbackDid: item.did,
  );
}

class _FriendsSection extends StatelessWidget {
  const _FriendsSection({
    required this.title,
    required this.children,
    this.trailingLabel,
    this.onTrailingTap,
  });

  final String title;
  final List<Widget> children;
  final String? trailingLabel;
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

class _FriendRow extends StatelessWidget {
  const _FriendRow.contact({
    required this.seed,
    required this.title,
    required this.onTap,
    this.trailing,
    this.avatarUri,
  }) : isGroup = false;

  const _FriendRow.group({required this.title, required this.onTap})
    : isGroup = true,
      seed = 'group',
      trailing = null,
      avatarUri = null;

  final bool isGroup;
  final String seed;
  final String title;
  final VoidCallback onTap;
  final Widget? trailing;
  final String? avatarUri;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Container(
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
        : theme.primary;
    final foreground = widget.destructive
        ? theme.danger
        : theme.primaryForeground;
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

class _IndexRail extends StatelessWidget {
  const _IndexRail();

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    const letters = <String>[
      'A',
      'B',
      'C',
      'E',
      'F',
      'G',
      'H',
      'I',
      'J',
      'M',
      'S',
      '#',
    ];
    final fontSize = responsive.isPhone ? 11.0 : 8.0;
    final itemSpacing = responsive.isPhone ? 3.0 : 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: letters
                  .map(
                    (letter) => Padding(
                      padding: EdgeInsets.symmetric(vertical: itemSpacing),
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: letter == 'E'
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: letter == 'E'
                              ? theme.primaryDark
                              : theme.tertiaryText,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

class RelationshipListPage extends ConsumerStatefulWidget {
  const RelationshipListPage({
    super.key,
    required this.type,
    this.embedded = false,
  });

  final FriendsRelationshipListType type;
  final bool embedded;

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
    final items = widget.type == FriendsRelationshipListType.followers
        ? listState.items
              .where((item) => !friendsState.isFollowing(item.did))
              .toList()
        : listState.items;
    final itemCount = items.isEmpty ? 2 : items.length + 2;
    final content = Stack(
      children: <Widget>[
        ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(0, widget.embedded ? 22 : 14, 0, 28),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                children: <Widget>[
                  AwikiMeTopBar(
                    title: title,
                    padding: EdgeInsets.zero,
                    trailingWidth: 42,
                    leading: widget.embedded
                        ? const SizedBox.shrink()
                        : TopBarActionButton(
                            onTap: () => Navigator.of(context).pop(),
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
            if (items.isEmpty && index == 1) {
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
            final footerIndex = items.isEmpty ? 2 : items.length + 1;
            if (index == footerIndex) {
              return _RelationshipListFooter(
                state: listState,
                onLoadMore: () => ref
                    .read(relationshipListProvider(widget.type).notifier)
                    .loadMore(),
              );
            }
            final item = items[index - 1];
            final displayName = _displayName(item);
            final isFollowing = friendsState.isFollowing(item.did);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _FriendRow.contact(
                seed: displayName,
                title: displayName,
                avatarUri: item.avatarUri,
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
                onTap: () => _openContact(context, ref, item: item),
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
    BuildContext context,
    WidgetRef ref, {
    required RelationshipSummary item,
  }) async {
    await openDirectConversationForDid(
      context,
      ref,
      peerDid: item.did,
      peerHandle: item.handle,
      peerName: _displayName(item),
      avatarUri: item.avatarUri,
    );
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
    (ctx) => CupertinoAlertDialog(
      title: Text(context.l10n.friendsUnfollowTitle),
      content: Text(context.l10n.friendsUnfollowMessage),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(context.l10n.commonCancel),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(context.l10n.friendsUnfollow),
        ),
      ],
    ),
  );
  if (confirmed != true) {
    return;
  }
  try {
    await ref.read(friendsProvider.notifier).unfollow(did);
  } catch (error) {
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
    ref
        .read(uiFeedbackProvider.notifier)
        .showError(AppMessage.fromError(error));
  }
}
