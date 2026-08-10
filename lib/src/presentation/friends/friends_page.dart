import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/entities/relationship_summary.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../../app/ui_feedback.dart';
import '../app_shell/providers/session_provider.dart';
import '../group/group_chat_navigation.dart';
import '../group/group_list_page.dart';
import '../group/group_provider.dart';
import '../profile/peer_display_profile_provider.dart';
import '../profile/peer_profile_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/app_dialog.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/awiki_me_semantic_icon.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/quick_actions.dart';
import '../shared/identity_flow.dart';
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
    this.onGroupChatTap,
  });

  final bool embedded;
  final double bottomInset;
  final VoidCallback? onGroupTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onFollowersTap;
  final ValueChanged<RelationshipSummary>? onContactTap;
  final Future<void> Function(GroupSummary)? onGroupChatTap;

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

  Future<void> _openGroupChat(
    BuildContext context,
    WidgetRef ref,
    GroupSummary group,
  ) async {
    final callback = onGroupChatTap;
    if (callback != null) {
      await callback(group);
      return;
    }
    await openGroupChat(context, ref, group);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final responsive = context.awikiResponsive;
    final state = ref.watch(friendsProvider);
    final theme = context.awikiTheme;
    final query = ref.watch(_friendsSearchQueryProvider).trim().toLowerCase();
    if (responsive.isCompact && !embedded) {
      final selectedTab = ref.watch(_friendsDirectoryTabProvider);
      final compactDirectory = _CompactFriendsDirectory(
        state: state,
        selectedTab: selectedTab,
        query: query,
        bottomInset: bottomInset,
        onTabSelected: (tab) =>
            ref.read(_friendsDirectoryTabProvider.notifier).state = tab,
        onSearchChanged: (value) =>
            ref.read(_friendsSearchQueryProvider.notifier).state = value,
        onContactTap: (item) => _openContact(context, item),
        onGroupTap: (group) => _openGroupChat(context, ref, group),
      );
      final content = AwikiMeShellTabPage(
        key: const Key('friends-page-surface'),
        title: context.l10n.friendsTitle,
        quickActionIcon: CupertinoIcons.add_circled,
        onQuickActionsTap: (anchorContext) => showCommonQuickActionsMenu(
          anchorContext,
          ref,
          anchoredToTrigger: true,
        ),
        child: compactDirectory,
      );
      return AwikiAdaptiveScaffold(
        maxWidth: 920,
        padding: EdgeInsets.zero,
        child: content,
      );
    }
    final following = state.following
        .where((item) => _matchesFriendQuery(ref, item, query))
        .take(_previewLimit)
        .toList();
    final followers = state.followers
        .where((item) => _matchesFriendQuery(ref, item, query))
        .take(_previewLimit)
        .toList();
    final openGroups =
        onGroupTap ??
        () => AppNavigator.push(context, (_) => const GroupListPage());
    final sectionWidgets = <Widget>[
      _FriendsSearchField(
        onChanged: (value) =>
            ref.read(_friendsSearchQueryProvider.notifier).state = value,
      ),
      Padding(
        padding: EdgeInsets.only(
          top: responsive.isCompact ? 0 : responsive.spacing(4),
        ),
        child: _FriendRow.group(
          title: context.l10n.friendsGroups,
          subtitle: context.l10n.friendsGroupsSubtitle,
          onTap: openGroups,
        ),
      ),
      _FriendsSection(
        title: context.l10n.friendsFollowing,
        count: state.following.length,
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
                      trailing: _RelationshipActionButton(
                        label: context.l10n.friendsMessage,
                        onTap: () => openDirectConversationForDid(
                          context,
                          ref,
                          peerDid: item.did,
                          peerName: _displayName(ref, item),
                          peerHandle: item.handle,
                          avatarUri: _avatarUri(ref, item),
                        ),
                      ),
                      onTap: () => _openContact(context, item),
                    ),
                  )
                  .toList(),
      ),
      _FriendsSection(
        title: context.l10n.friendsFollowers,
        count: state.followers.length,
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
          color: responsive.isCompact
              ? AwikiMeColors.background
              : theme.surface,
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
      quickActionIcon: CupertinoIcons.add_circled,
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

final _friendsSearchQueryProvider = StateProvider.autoDispose<String>(
  (ref) => '',
);

enum _FriendsDirectoryTab { all, following, followers, groups }

final _friendsDirectoryTabProvider = StateProvider<_FriendsDirectoryTab>(
  (ref) => _FriendsDirectoryTab.all,
);

List<RelationshipSummary> _mergeAllFriends(FriendsState state) {
  final merged = <String, RelationshipSummary>{};
  for (final item in <RelationshipSummary>[
    ...state.following,
    ...state.followers,
  ]) {
    final did = item.did.trim().toLowerCase();
    final handle = item.handle?.trim().toLowerCase() ?? '';
    final key = did.isNotEmpty ? did : handle;
    if (key.isNotEmpty) {
      merged.putIfAbsent(key, () => item);
    }
  }
  return merged.values.toList(growable: false);
}

bool _matchesGroupQuery(GroupSummary group, String query) {
  if (query.isEmpty) {
    return true;
  }
  return <String>[
    group.displayName,
    group.description,
    group.groupId,
  ].join(' ').toLowerCase().contains(query);
}

class _CompactFriendsDirectory extends ConsumerWidget {
  const _CompactFriendsDirectory({
    required this.state,
    required this.selectedTab,
    required this.query,
    required this.bottomInset,
    required this.onTabSelected,
    required this.onSearchChanged,
    required this.onContactTap,
    required this.onGroupTap,
  });

  final FriendsState state;
  final _FriendsDirectoryTab selectedTab;
  final String query;
  final double bottomInset;
  final ValueChanged<_FriendsDirectoryTab> onTabSelected;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<RelationshipSummary> onContactTap;
  final Future<void> Function(GroupSummary) onGroupTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupState = ref.watch(groupProvider);
    final theme = context.awikiTheme;
    return DecoratedBox(
      key: const Key('friends-list-surface'),
      decoration: const BoxDecoration(color: AwikiMeColors.background),
      child: Column(
        children: <Widget>[
          _FriendsSearchField(
            placeholder: selectedTab == _FriendsDirectoryTab.groups
                ? context.l10n.friendsSearchGroupsPlaceholder
                : context.l10n.friendsSearchPlaceholder,
            onChanged: onSearchChanged,
          ),
          _FriendsCategoryTabs(
            selectedTab: selectedTab,
            onSelected: onTabSelected,
          ),
          Expanded(
            child: selectedTab == _FriendsDirectoryTab.groups
                ? _buildGroups(context, ref, groupState, theme)
                : _buildRelationships(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _buildRelationships(BuildContext context, WidgetRef ref) {
    final source = switch (selectedTab) {
      _FriendsDirectoryTab.all => _mergeAllFriends(state),
      _FriendsDirectoryTab.following => state.following,
      _FriendsDirectoryTab.followers => state.followers,
      _FriendsDirectoryTab.groups => const <RelationshipSummary>[],
    };
    final items = source
        .where((item) => _matchesFriendQuery(ref, item, query))
        .toList(growable: false);
    final hasRelevantError = switch (selectedTab) {
      _FriendsDirectoryTab.all => state.hasRefreshError,
      _FriendsDirectoryTab.following => state.followingError != null,
      _FriendsDirectoryTab.followers => state.followersError != null,
      _FriendsDirectoryTab.groups => false,
    };
    final children = <Widget>[];
    if (hasRelevantError && items.isEmpty) {
      children.add(
        _FriendsPreviewStatus(
          message: context.l10n.operationFailedRetry,
          onRetry: () => ref.read(friendsProvider.notifier).refresh(),
        ),
      );
    } else if (items.isEmpty) {
      final emptyMessage = query.isNotEmpty
          ? context.l10n.friendsNoResults
          : switch (selectedTab) {
              _FriendsDirectoryTab.all => context.l10n.friendsAllEmpty,
              _FriendsDirectoryTab.following =>
                context.l10n.friendsFollowingEmpty,
              _FriendsDirectoryTab.followers =>
                context.l10n.friendsFollowersEmpty,
              _FriendsDirectoryTab.groups => context.l10n.friendsAllEmpty,
            };
      children.add(_FriendsPreviewStatus(message: emptyMessage));
    } else {
      children.addAll(
        items.map(
          (item) => _FriendRow.contact(
            rowKey: Key(
              'friends-${selectedTab.name}-contact:${item.did.trim()}',
            ),
            titleKey: Key(
              'friends-${selectedTab.name}-contact-title:${item.did.trim()}',
            ),
            seed: _displayName(ref, item),
            title: _displayName(ref, item),
            subtitle: _handleLabel(item.handle),
            avatarUri: _avatarUri(ref, item),
            trailing: _relationshipAction(context, ref, item),
            onTap: () => onContactTap(item),
          ),
        ),
      );
    }
    if (state.isLoading) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    }
    return ListView(
      key: ValueKey<String>('friends-${selectedTab.name}-list'),
      padding: EdgeInsets.only(bottom: bottomInset),
      children: children,
    );
  }

  Widget _relationshipAction(
    BuildContext context,
    WidgetRef ref,
    RelationshipSummary item,
  ) {
    if (selectedTab == _FriendsDirectoryTab.following) {
      return _RelationshipActionButton(
        label: context.l10n.friendsUnfollow,
        destructive: true,
        onTap: () => confirmAndUnfollow(context, ref, item.did),
      );
    }
    if (state.isFollowing(item.did)) {
      return _RelationshipActionButton(
        label: context.l10n.friendsMessage,
        onTap: () => openDirectConversationForDid(
          context,
          ref,
          peerDid: item.did,
          peerName: _displayName(ref, item),
          peerHandle: item.handle,
          avatarUri: _avatarUri(ref, item),
        ),
      );
    }
    return _RelationshipActionButton(
      label: context.l10n.friendsFollow,
      onTap: () => _runRelationshipAction(
        ref,
        () => ref.read(friendsProvider.notifier).follow(item.did),
      ),
    );
  }

  Widget _buildGroups(
    BuildContext context,
    WidgetRef ref,
    GroupState groupState,
    AwikiMeThemeTokens theme,
  ) {
    final groups = groupState.groups
        .where((group) => _matchesGroupQuery(group, query))
        .toList(growable: false);
    final children = <Widget>[];
    if (groups.isEmpty && !groupState.isLoading) {
      children.add(
        _FriendsPreviewStatus(
          message: query.isNotEmpty
              ? context.l10n.friendsNoResults
              : context.l10n.groupListEmpty,
        ),
      );
    } else {
      children.addAll(
        groups.map(
          (group) =>
              _CompactGroupRow(group: group, onTap: () => onGroupTap(group)),
        ),
      );
    }
    if (groupState.groupsHasMore) {
      children.add(
        Center(
          child: CupertinoButton(
            key: const Key('friends-groups-load-more'),
            onPressed: groupState.isLoadingMoreGroups
                ? null
                : () async {
                    try {
                      await ref.read(groupProvider.notifier).loadMoreGroups();
                    } catch (error) {
                      if (context.mounted) {
                        ref
                            .read(uiFeedbackProvider.notifier)
                            .showError(AppMessage.fromError(error));
                      }
                    }
                  },
            child: groupState.isLoadingMoreGroups
                ? const CupertinoActivityIndicator()
                : Text(context.l10n.commonLoadMore),
          ),
        ),
      );
    }
    if (groupState.isLoading) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    }
    return DecoratedBox(
      key: const ValueKey<String>('friends-groups-list'),
      decoration: BoxDecoration(color: theme.background),
      child: ListView(
        padding: EdgeInsets.only(bottom: bottomInset),
        children: children,
      ),
    );
  }
}

class _FriendsCategoryTabs extends StatelessWidget {
  const _FriendsCategoryTabs({
    required this.selectedTab,
    required this.onSelected,
  });

  final _FriendsDirectoryTab selectedTab;
  final ValueChanged<_FriendsDirectoryTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final entries = <(_FriendsDirectoryTab, String)>[
      (_FriendsDirectoryTab.all, context.l10n.friendsTabAll),
      (_FriendsDirectoryTab.following, context.l10n.friendsTabFollowing),
      (_FriendsDirectoryTab.followers, context.l10n.friendsTabFollowers),
      (_FriendsDirectoryTab.groups, context.l10n.friendsTabGroups),
    ];
    return Container(
      key: const Key('friends-category-tabs'),
      height: 56,
      decoration: BoxDecoration(
        color: theme.background,
        border: Border(bottom: BorderSide(color: theme.border)),
      ),
      child: Row(
        children: entries
            .map((entry) {
              final selected = entry.$1 == selectedTab;
              return Expanded(
                child: Semantics(
                  selected: selected,
                  button: true,
                  label: entry.$2,
                  child: AppPressable(
                    key: Key('friends-category-tab-${entry.$1.name}'),
                    selected: selected,
                    semanticLabel: entry.$2,
                    onTap: () => onSelected(entry.$1),
                    builder: (context, state, child) => AnimatedOpacity(
                      opacity: state.pressed ? 0.72 : 1,
                      duration: const Duration(milliseconds: 120),
                      child: child,
                    ),
                    child: SizedBox.expand(
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          Text(
                            entry.$2,
                            style: TextStyle(
                              color: selected ? theme.primary : theme.title,
                              fontSize: 15,
                              fontWeight: selected
                                  ? FontWeight.w400
                                  : FontWeight.w400,
                            ),
                          ),
                          if (selected)
                            Positioned(
                              bottom: 0,
                              child: Container(
                                key: const Key(
                                  'friends-category-tab-indicator',
                                ),
                                width: 40,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: theme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _CompactGroupRow extends StatelessWidget {
  const _CompactGroupRow({required this.group, required this.onTap});

  final GroupSummary group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final description = group.description.trim();
    return Container(
      key: Key('friends-group-tab-row:${group.groupId}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppListTile(
          horizontalPadding: 0,
          title: group.displayName,
          subtitle: description.isEmpty
              ? context.l10n.chatPeerInfoMemberCount(group.memberCount)
              : description,
          leading: AppSurface(
            padding: EdgeInsets.zero,
            color: theme.colorScheme.secondaryContainer,
            radius: AwikiMeRadii.pill,
            constraints: BoxConstraints.tightFor(
              width: responsive.displayScaled(48),
              height: responsive.displayScaled(48),
            ),
            child: Icon(
              CupertinoIcons.person_3,
              color: theme.colorScheme.onSecondaryContainer,
              size: responsive.displayScaled(22),
            ),
          ),
          trailing: AwikiAssetIcon(
            assetName: 'assets/icons/icon_right.svg',
            size: responsive.iconSm,
            color: theme.tertiaryText,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

bool _matchesFriendQuery(
  WidgetRef ref,
  RelationshipSummary item,
  String query,
) {
  if (query.isEmpty) {
    return true;
  }
  return <String>[
    _displayName(ref, item),
    item.handle ?? '',
    item.did,
  ].join(' ').toLowerCase().contains(query);
}

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
  return value.startsWith('@') ? value.substring(1) : value;
}

class _FriendsSearchField extends StatelessWidget {
  const _FriendsSearchField({required this.onChanged, this.placeholder});

  final ValueChanged<String> onChanged;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Padding(
      padding: responsive.isCompact
          ? const EdgeInsets.fromLTRB(16, 8, 16, 8)
          : EdgeInsets.fromLTRB(
              responsive.spacing(16),
              responsive.spacing(8),
              responsive.spacing(16),
              responsive.spacing(8),
            ),
      child: SizedBox(
        height: responsive.isCompact ? 52 : responsive.displayScaled(52),
        child: CupertinoSearchTextField(
          key: const Key('friends-search-field'),
          placeholder: placeholder ?? context.l10n.friendsSearchPlaceholder,
          onChanged: onChanged,
          style: TextStyle(
            color: theme.title,
            fontSize: responsive.displayScaled(15),
          ),
          placeholderStyle: TextStyle(
            color: theme.tertiaryText,
            fontSize: responsive.displayScaled(15),
          ),
          prefixIcon: Icon(
            CupertinoIcons.search,
            color: theme.secondaryText,
            size: responsive.iconSm,
          ),
          decoration: BoxDecoration(
            color: theme.subtleSurface,
            borderRadius: BorderRadius.circular(responsive.radius(16)),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: responsive.spacing(14),
            vertical: responsive.spacing(12),
          ),
        ),
      ),
    );
  }
}

class _FriendsSection extends StatelessWidget {
  const _FriendsSection({
    required this.title,
    required this.children,
    this.count,
    this.trailingLabel,
    this.trailingKey,
    this.onTrailingTap,
  });

  final String title;
  final List<Widget> children;
  final int? count;
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
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                if (count != null) ...<Widget>[
                  Text(
                    '$count',
                    style: TextStyle(
                      color: theme.secondaryText,
                      fontSize: responsive.metaSm,
                    ),
                  ),
                  SizedBox(width: responsive.spacing(10)),
                ],
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
                          fontWeight: FontWeight.w400,
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
    final leading = isGroup
        ? AppSurface(
            padding: EdgeInsets.zero,
            color: theme.colorScheme.secondaryContainer,
            radius: AwikiMeRadii.pill,
            constraints: BoxConstraints.tightFor(
              width: responsive.displayScaled(48),
              height: responsive.displayScaled(48),
            ),
            child: Icon(
              CupertinoIcons.person_3,
              color: theme.colorScheme.onSecondaryContainer,
              size: responsive.displayScaled(22),
            ),
          )
        : AvatarBadge(
            seed: seed,
            size: responsive.displayScaled(48),
            avatarUri: avatarUri,
          );
    if (isGroup && responsive.isCompact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppPressable(
          onTap: onTap,
          semanticLabel: title,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            key: rowKey,
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AwikiMePalette.navigationBorder),
            ),
            child: Row(
              children: <Widget>[
                leading,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: AwikiMeTextStyles.listTitle.copyWith(
                          fontSize: 14,
                          color: theme.title,
                        ),
                      ),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AwikiMeTextStyles.cardSubtitle.copyWith(
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AwikiAssetIcon(
                  assetName: 'assets/icons/icon_right.svg',
                  size: responsive.iconSm,
                  color: theme.tertiaryText,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      key: rowKey,
      padding: EdgeInsets.symmetric(vertical: responsive.spacing(8)),
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
          leading: leading,
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
    final buttonWidth = widget.label.runes.length > 2 ? 80.0 : 64.0;
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
      child: SizedBox(
        width: buttonWidth,
        height: 44,
        child: Center(
          child: Container(
            key: const Key('relationship-action-visual'),
            width: buttonWidth,
            height: 38,
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
                    maxLines: 1,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
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
                    titleFontSize: awikiMeCompactTopBarTitleFontSize,
                    titleFontWeight: awikiMeCompactTopBarTitleFontWeight,
                    titleHeight: awikiMeCompactTopBarTitleHeight,
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
