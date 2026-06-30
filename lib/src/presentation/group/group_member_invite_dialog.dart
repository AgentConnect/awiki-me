import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/e2e_semantics.dart';
import '../../domain/entities/agent/agent_status.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/entities/relationship_summary.dart';
import '../../domain/entities/user_profile.dart';
import '../agents/agents_provider.dart';
import '../conversation_list/conversation_provider.dart';
import '../friends/friends_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/app_dialog.dart';
import '../shared/avatar_badge.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/identity_flow.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'group_provider.dart';

class GroupMemberInviteDialog extends ConsumerStatefulWidget {
  const GroupMemberInviteDialog({
    super.key,
    required this.groupId,
    required this.existingMembers,
    required this.onGroupUpdated,
  });

  final String groupId;
  final List<GroupMemberSummary> existingMembers;
  final ValueChanged<GroupSummary> onGroupUpdated;

  @override
  ConsumerState<GroupMemberInviteDialog> createState() =>
      _GroupMemberInviteDialogState();
}

class _GroupMemberInviteDialogState
    extends ConsumerState<GroupMemberInviteDialog> {
  static const int _defaultVisibleLimit = 6;

  final TextEditingController _queryController = TextEditingController();
  final ScrollController _candidateScrollController = ScrollController();
  final Map<String, GroupInviteCandidate> _resolvedCandidates =
      <String, GroupInviteCandidate>{};
  final Set<String> _selectedDids = <String>{};

  bool _isLoadingLocalCandidates = false;
  bool _showAllCandidates = false;
  bool _isResolving = false;
  bool _isSubmitting = false;
  String _query = '';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_handleQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadLocalSources());
    });
  }

  @override
  void dispose() {
    _queryController
      ..removeListener(_handleQueryChanged)
      ..dispose();
    _candidateScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GroupMemberInviteDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId ||
        oldWidget.existingMembers != widget.existingMembers) {
      _selectedDids.removeWhere(_isExistingMemberDid);
    }
  }

  void _handleQueryChanged() {
    final next = _queryController.text;
    if (next == _query) {
      return;
    }
    setState(() {
      _query = next;
      _showAllCandidates = false;
    });
  }

  Future<void> _loadLocalSources() async {
    if (_isLoadingLocalCandidates) {
      return;
    }
    setState(() {
      _isLoadingLocalCandidates = true;
    });
    await Future.wait<void>(<Future<void>>[
      ref.read(agentsProvider.notifier).ensureLoaded().catchError((_) {}),
      ref.read(friendsProvider.notifier).refresh().catchError((_) {}),
      ref
          .read(conversationListProvider.notifier)
          .refreshFastLocal()
          .catchError((_) {}),
    ], eagerError: false);
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoadingLocalCandidates = false;
    });
  }

  Future<void> _resolveQuery() async {
    final query = normalizeDidOrHandleInput(_queryController.text);
    if (query.isEmpty) {
      setState(() {
        _errorText = '请输入 handle 或 DID。';
      });
      return;
    }
    setState(() {
      _isResolving = true;
      _errorText = null;
      _showAllCandidates = true;
    });
    try {
      final profile = await resolveIdentityProfile(ref, query);
      final candidate = GroupInviteCandidate.fromProfile(
        profile,
        source: GroupInviteCandidateSource.resolved,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _resolvedCandidates[_normalizeDid(candidate.did)] = candidate;
        _isResolving = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isResolving = false;
        _errorText = '未找到该身份，请检查 handle / DID 是否正确。';
      });
    }
  }

  Future<void> _submitSelected() async {
    if (_selectedDids.isEmpty || _isSubmitting || _isResolving) {
      return;
    }
    final candidatesByDid = <String, GroupInviteCandidate>{
      for (final candidate in _allCandidates(watch: false))
        _normalizeDid(candidate.did): candidate,
    };
    final selected = <GroupInviteCandidate>[
      for (final did in _selectedDids)
        if (candidatesByDid[did] != null) candidatesByDid[did]!,
    ];
    if (selected.isEmpty) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final failed = <String>[];
    GroupSummary? latestGroup;
    for (final candidate in selected) {
      try {
        latestGroup = await ref
            .read(groupProvider.notifier)
            .addGroupMember(groupId: widget.groupId, memberRef: candidate.did);
        _selectedDids.remove(_normalizeDid(candidate.did));
      } catch (error) {
        failed.add('${candidate.displayName}: $error');
      }
    }

    if (!mounted) {
      return;
    }
    if (latestGroup != null) {
      widget.onGroupUpdated(latestGroup);
      try {
        await ref.read(groupProvider.notifier).loadGroupMembers(widget.groupId);
      } catch (_) {
        // The updated group count is already available; member refresh is a
        // best-effort follow-up so the dialog flow is not blocked by it.
      }
    }
    if (!mounted) {
      return;
    }
    if (failed.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isSubmitting = false;
      _errorText = failed.join('\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final candidates = _filteredCandidates();
    final hasMore =
        !_showAllCandidates &&
        candidates.length > _defaultVisibleLimit &&
        _normalizedQuery.isEmpty;
    final visibleCandidates = hasMore
        ? candidates.take(_defaultVisibleLimit).toList()
        : candidates;
    final selectedCount = _selectedDids.length;
    return AppDialogScaffold(
      maxWidth: 620,
      maxHeightFraction: 0.9,
      horizontalPadding: responsive.isPhone ? 14 : 16,
      verticalPadding: 24,
      borderRadius: BorderRadius.circular(responsive.radius(16)),
      avoidViewInsets: true,
      padding: responsive.scaledInsets(
        const EdgeInsets.fromLTRB(22, 20, 22, 20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _InviteDialogHeader(isBusy: _isSubmitting),
          SizedBox(height: responsive.spacing(18)),
          _InviteSearchInput(
            controller: _queryController,
            enabled: !_isSubmitting && !_isResolving,
            isResolving: _isResolving,
            onSubmitted: _resolveQuery,
            onResolve: _resolveQuery,
          ),
          if (_errorText != null) ...<Widget>[
            SizedBox(height: responsive.spacing(10)),
            AwikiMeErrorNotice(message: _errorText!, compact: true),
          ],
          SizedBox(height: responsive.spacing(14)),
          _SelectedInviteStrip(
            selected: _selectedCandidates(candidates),
            onRemove: _isSubmitting
                ? null
                : (candidate) => _toggleCandidate(candidate),
          ),
          SizedBox(height: responsive.spacing(12)),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _candidateSectionTitle,
                  style: AwikiMeTextStyles.sectionTitle.copyWith(
                    fontSize: responsive.bodyMd,
                  ),
                ),
              ),
              if (_isLoadingLocalCandidates)
                const CupertinoActivityIndicator(radius: 8),
            ],
          ),
          SizedBox(height: responsive.spacing(10)),
          Flexible(
            fit: FlexFit.loose,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: responsive.isPhone ? 300 : 340,
                minHeight: 150,
              ),
              child: _InviteCandidateList(
                controller: _candidateScrollController,
                candidates: visibleCandidates,
                selectedDids: _selectedDids,
                existingMemberDids: _existingMemberDids,
                onToggle: _isSubmitting ? null : _toggleCandidate,
                query: _normalizedQuery,
              ),
            ),
          ),
          if (hasMore) ...<Widget>[
            SizedBox(height: responsive.spacing(8)),
            SizedBox(
              width: double.infinity,
              child: AppSecondaryButton(
                label: '查看更多',
                onPressed: _isSubmitting
                    ? null
                    : () => setState(() {
                        _showAllCandidates = true;
                      }),
              ),
            ),
          ],
          SizedBox(height: responsive.spacing(16)),
          Row(
            children: <Widget>[
              Expanded(
                child: AppSecondaryButton(
                  label: '取消',
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
              ),
              SizedBox(width: responsive.spacing(12)),
              Expanded(
                child: AppPrimaryButton(
                  key: const Key('identity-add-group-member-button'),
                  label: _isSubmitting
                      ? '添加中...'
                      : selectedCount == 0
                      ? '确认添加'
                      : '确认添加 ($selectedCount)',
                  semanticsIdentifier: 'e2e-identity-add-group-member-button',
                  onPressed: selectedCount == 0 || _isSubmitting || _isResolving
                      ? null
                      : _submitSelected,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _normalizedQuery => _normalizeSearchText(_query);

  String get _candidateSectionTitle {
    if (_normalizedQuery.isEmpty) {
      return '可邀请的身份';
    }
    return '搜索结果';
  }

  Set<String> get _existingMemberDids => <String>{
    for (final member in widget.existingMembers)
      if (member.did.trim().isNotEmpty) _normalizeDid(member.did),
  };

  bool _isExistingMemberDid(String did) => _existingMemberDids.contains(did);

  List<GroupInviteCandidate> _selectedCandidates(
    List<GroupInviteCandidate> filtered,
  ) {
    final all = <String, GroupInviteCandidate>{
      for (final candidate in <GroupInviteCandidate>[
        ...filtered,
        ..._allCandidates(),
      ])
        _normalizeDid(candidate.did): candidate,
    };
    return <GroupInviteCandidate>[
      for (final did in _selectedDids)
        if (all[did] != null) all[did]!,
    ];
  }

  void _toggleCandidate(GroupInviteCandidate candidate) {
    final did = _normalizeDid(candidate.did);
    if (did.isEmpty || _existingMemberDids.contains(did)) {
      return;
    }
    setState(() {
      if (!_selectedDids.remove(did)) {
        _selectedDids.add(did);
      }
    });
  }

  List<GroupInviteCandidate> _filteredCandidates() {
    final query = _normalizedQuery;
    final candidates = _allCandidates();
    if (query.isEmpty) {
      return candidates;
    }
    final matched = candidates
        .where((candidate) => candidate.matches(query))
        .toList(growable: false);
    matched.sort((a, b) {
      final rank = a.matchRank(query).compareTo(b.matchRank(query));
      if (rank != 0) {
        return rank;
      }
      final source = a.source.index.compareTo(b.source.index);
      if (source != 0) {
        return source;
      }
      return a.displayName.compareTo(b.displayName);
    });
    return matched;
  }

  List<GroupInviteCandidate> _allCandidates({bool watch = true}) {
    final byDid = <String, GroupInviteCandidate>{};
    void add(GroupInviteCandidate? candidate) {
      if (candidate == null) {
        return;
      }
      final did = _normalizeDid(candidate.did);
      if (did.isEmpty || _looksLikeGroupDid(did)) {
        return;
      }
      final existing = byDid[did];
      byDid[did] = existing == null ? candidate : existing.merge(candidate);
    }

    final agentsState = watch
        ? ref.watch(agentsProvider)
        : ref.read(agentsProvider);
    for (final agent in agentsState.agents) {
      add(GroupInviteCandidate.fromAgent(agent));
    }

    final friendsState = watch
        ? ref.watch(friendsProvider)
        : ref.read(friendsProvider);
    for (final relationship in friendsState.following) {
      add(
        GroupInviteCandidate.fromRelationship(
          relationship,
          source: GroupInviteCandidateSource.following,
        ),
      );
    }
    for (final relationship in friendsState.followers) {
      add(
        GroupInviteCandidate.fromRelationship(
          relationship,
          source: GroupInviteCandidateSource.follower,
        ),
      );
    }

    final conversations =
        (watch
                ? ref.watch(conversationListProvider)
                : ref.read(conversationListProvider))
            .conversations;
    for (final conversation in conversations) {
      add(GroupInviteCandidate.fromConversation(conversation));
    }

    for (final candidate in _resolvedCandidates.values) {
      add(candidate);
    }

    final candidates = byDid.values.toList(growable: false);
    candidates.sort((a, b) {
      final source = a.source.index.compareTo(b.source.index);
      if (source != 0) {
        return source;
      }
      final timeA = a.lastInteractedAt;
      final timeB = b.lastInteractedAt;
      if (timeA != null || timeB != null) {
        if (timeA == null) {
          return 1;
        }
        if (timeB == null) {
          return -1;
        }
        return timeB.compareTo(timeA);
      }
      return a.displayName.compareTo(b.displayName);
    });
    return candidates;
  }
}

enum GroupInviteCandidateSource { agent, following, follower, recent, resolved }

enum GroupInviteIdentityKind { human, agent }

class GroupInviteCandidate {
  const GroupInviteCandidate({
    required this.did,
    required this.displayName,
    required this.kind,
    required this.source,
    this.handle,
    this.avatarUri,
    this.avatarSeed,
    this.lastInteractedAt,
  });

  final String did;
  final String displayName;
  final GroupInviteIdentityKind kind;
  final GroupInviteCandidateSource source;
  final String? handle;
  final String? avatarUri;
  final String? avatarSeed;
  final DateTime? lastInteractedAt;

  factory GroupInviteCandidate.fromAgent(AgentSummary agent) {
    if (agent.kind != AgentKind.runtime || agent.agentDid.trim().isEmpty) {
      return const GroupInviteCandidate(
        did: '',
        displayName: '',
        kind: GroupInviteIdentityKind.agent,
        source: GroupInviteCandidateSource.agent,
      );
    }
    final displayName = agent.displayName.trim().isNotEmpty
        ? agent.displayName.trim()
        : '未命名智能体';
    return GroupInviteCandidate(
      did: agent.agentDid.trim(),
      displayName: displayName,
      kind: GroupInviteIdentityKind.agent,
      source: GroupInviteCandidateSource.agent,
      handle: agent.handle,
      avatarSeed: displayName,
    );
  }

  factory GroupInviteCandidate.fromRelationship(
    RelationshipSummary relationship, {
    required GroupInviteCandidateSource source,
  }) {
    final did = relationship.did.trim();
    final displayName = relationship.displayName.trim().isNotEmpty
        ? relationship.displayName.trim()
        : _displayNameFallback(relationship.handle, did);
    return GroupInviteCandidate(
      did: did,
      displayName: displayName,
      kind: _kindFromIdentityText(
        subjectType: null,
        did: did,
        displayName: displayName,
        handle: relationship.handle,
      ),
      source: source,
      handle: relationship.handle,
      avatarUri: relationship.avatarUri,
      avatarSeed: displayName,
    );
  }

  factory GroupInviteCandidate.fromConversation(
    ConversationSummary conversation,
  ) {
    if (conversation.isGroup) {
      return const GroupInviteCandidate(
        did: '',
        displayName: '',
        kind: GroupInviteIdentityKind.human,
        source: GroupInviteCandidateSource.recent,
      );
    }
    final did = conversation.targetDid?.trim() ?? '';
    final peer = conversation.targetPeer?.trim();
    final displayName = conversation.displayName.trim().isNotEmpty
        ? conversation.displayName.trim()
        : _displayNameFallback(peer, did);
    return GroupInviteCandidate(
      did: did,
      displayName: displayName,
      kind: conversation.isDeletedAgentConversation
          ? GroupInviteIdentityKind.agent
          : _kindFromIdentityText(
              subjectType: null,
              did: did,
              displayName: displayName,
              handle: peer,
            ),
      source: GroupInviteCandidateSource.recent,
      handle: _handleFromDirectPeer(peer),
      avatarUri: conversation.avatarUri,
      avatarSeed: conversation.avatarSeed ?? displayName,
      lastInteractedAt: conversation.lastMessageAt,
    );
  }

  factory GroupInviteCandidate.fromProfile(
    UserProfile profile, {
    required GroupInviteCandidateSource source,
  }) {
    final displayName = DidDisplayFormatter.profileName(profile);
    return GroupInviteCandidate(
      did: profile.did.trim(),
      displayName: displayName,
      kind: _kindFromIdentityText(
        subjectType: profile.subjectType,
        did: profile.did,
        displayName: profile.displayName,
        handle: profile.handle ?? profile.fullHandle,
        bio: profile.bio,
        tags: profile.tags,
      ),
      source: source,
      handle: profile.fullHandle ?? profile.handle,
      avatarUri: profile.avatarUri,
      avatarSeed: profile.handle ?? displayName,
    );
  }

  GroupInviteCandidate merge(GroupInviteCandidate other) {
    if (source.index <= other.source.index) {
      return _copyWithMissing(other);
    }
    return other._copyWithMissing(this);
  }

  GroupInviteCandidate _copyWithMissing(GroupInviteCandidate other) {
    return GroupInviteCandidate(
      did: did,
      displayName: displayName.trim().isEmpty ? other.displayName : displayName,
      kind:
          kind == GroupInviteIdentityKind.human &&
              other.kind == GroupInviteIdentityKind.agent
          ? GroupInviteIdentityKind.agent
          : kind,
      source: source,
      handle: _firstNonEmpty(handle, other.handle),
      avatarUri: _firstNonEmpty(avatarUri, other.avatarUri),
      avatarSeed: _firstNonEmpty(avatarSeed, other.avatarSeed),
      lastInteractedAt: lastInteractedAt ?? other.lastInteractedAt,
    );
  }

  bool matches(String normalizedQuery) {
    if (normalizedQuery.isEmpty) {
      return true;
    }
    return _searchText.contains(normalizedQuery);
  }

  int matchRank(String normalizedQuery) {
    final handleText = _normalizeSearchText(handle ?? '');
    final titleText = _normalizeSearchText(displayName);
    final didText = _normalizeSearchText(did);
    if (handleText == normalizedQuery || didText == normalizedQuery) {
      return 0;
    }
    if (titleText == normalizedQuery) {
      return 1;
    }
    if (handleText.startsWith(normalizedQuery) ||
        titleText.startsWith(normalizedQuery)) {
      return 2;
    }
    if (didText.startsWith(normalizedQuery)) {
      return 3;
    }
    return 4;
  }

  String get _searchText => _normalizeSearchText(
    <String>[displayName, handle ?? '', did, sourceLabel, kindLabel].join(' '),
  );

  String get kindLabel => kind == GroupInviteIdentityKind.agent ? '智能体' : '用户';

  String get sourceLabel {
    switch (source) {
      case GroupInviteCandidateSource.agent:
        return '我的智能体';
      case GroupInviteCandidateSource.following:
        return '我关注的';
      case GroupInviteCandidateSource.follower:
        return '关注我的';
      case GroupInviteCandidateSource.recent:
        return '最近会话';
      case GroupInviteCandidateSource.resolved:
        return '匹配结果';
    }
  }
}

class _InviteDialogHeader extends StatelessWidget {
  const _InviteDialogHeader({required this.isBusy});

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return AppDialogHeader(
      title: '添加群成员',
      subtitle: '搜索本地身份，或输入 handle / DID 匹配新身份。',
      onClose: () => Navigator.of(context).pop(),
      isCloseEnabled: !isBusy,
    );
  }
}

class _InviteSearchInput extends StatefulWidget {
  const _InviteSearchInput({
    required this.controller,
    required this.enabled,
    required this.isResolving,
    required this.onSubmitted,
    required this.onResolve,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isResolving;
  final Future<void> Function() onSubmitted;
  final Future<void> Function() onResolve;

  @override
  State<_InviteSearchInput> createState() => _InviteSearchInputState();
}

class _InviteSearchInputState extends State<_InviteSearchInput> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant _InviteSearchInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      widget.controller.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    super.dispose();
  }

  void _handleTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final showClearButton =
        widget.enabled && widget.controller.text.trim().isNotEmpty;
    final searchField = Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(CupertinoIcons.search, color: Color(0xFF34415C), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: e2eSemantics(
              identifier: 'e2e-identity-lookup-input',
              label: '输入 handle 或 DID',
              textField: true,
              child: CupertinoTextField(
                key: const Key('identity-lookup-input'),
                controller: widget.controller,
                enabled: widget.enabled,
                placeholder: '搜索名称、handle、DID',
                textInputAction: TextInputAction.search,
                onSubmitted: (_) async {
                  if (widget.enabled) {
                    await widget.onSubmitted();
                  }
                },
                decoration: null,
                padding: EdgeInsets.zero,
                style: const TextStyle(color: Color(0xFF17213A), fontSize: 14),
                placeholderStyle: const TextStyle(
                  color: Color(0xFF8A96AA),
                  fontSize: 14,
                ),
              ),
            ),
          ),
          if (showClearButton) ...<Widget>[
            const SizedBox(width: 8),
            AppIconButton(
              key: const Key('identity-lookup-clear-button'),
              semanticLabel: '清空输入',
              tooltip: '清空输入',
              onPressed: widget.controller.clear,
              size: 28,
              backgroundColor: const Color(0xFFEAF0F7),
              activeBackgroundColor: const Color(0xFFDDE8F6),
              borderColor: CupertinoColors.transparent,
              borderRadius: BorderRadius.circular(999),
              child: const Icon(
                CupertinoIcons.xmark,
                color: Color(0xFF66728A),
                size: 15,
              ),
            ),
          ],
        ],
      ),
    );
    final resolveButton = SizedBox(
      height: 52,
      child: AppSecondaryButton(
        key: const Key('identity-lookup-search-button'),
        label: widget.isResolving ? '匹配中...' : '匹配身份',
        semanticsIdentifier: 'e2e-identity-lookup-search-button',
        onPressed: widget.enabled && !widget.isResolving
            ? widget.onResolve
            : null,
      ),
    );

    if (responsive.isPhone) {
      return Column(
        children: <Widget>[
          searchField,
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: resolveButton),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(child: searchField),
        const SizedBox(width: 10),
        SizedBox(width: 112, child: resolveButton),
      ],
    );
  }
}

class _SelectedInviteStrip extends StatelessWidget {
  const _SelectedInviteStrip({required this.selected, required this.onRemove});

  final List<GroupInviteCandidate> selected;
  final ValueChanged<GroupInviteCandidate>? onRemove;

  @override
  Widget build(BuildContext context) {
    if (selected.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          '选择一个或多个身份后，统一确认添加。',
          style: TextStyle(
            color: Color(0xFF0B65F8),
            fontSize: 12,
            height: 1.35,
          ),
        ),
      );
    }
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: selected.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final candidate = selected[index];
          return _SelectedInviteChip(
            candidate: candidate,
            onRemove: onRemove == null ? null : () => onRemove!(candidate),
          );
        },
      ),
    );
  }
}

class _SelectedInviteChip extends StatelessWidget {
  const _SelectedInviteChip({required this.candidate, required this.onRemove});

  final GroupInviteCandidate candidate;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7FC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            candidate.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF17213A),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 16,
                color: Color(0xFF8A96AA),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteCandidateList extends StatelessWidget {
  const _InviteCandidateList({
    required this.controller,
    required this.candidates,
    required this.selectedDids,
    required this.existingMemberDids,
    required this.onToggle,
    required this.query,
  });

  final ScrollController controller;
  final List<GroupInviteCandidate> candidates;
  final Set<String> selectedDids;
  final Set<String> existingMemberDids;
  final ValueChanged<GroupInviteCandidate>? onToggle;
  final String query;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFFBFDFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDDE5F0)),
        ),
        child: Text(
          query.isEmpty ? '暂无可邀请的本地身份。' : '没有匹配的本地身份，可以尝试匹配 handle / DID。',
          textAlign: TextAlign.center,
          style: AwikiMeTextStyles.cardSubtitle,
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: CupertinoScrollbar(
        controller: controller,
        child: ListView.separated(
          controller: controller,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: candidates.length,
          separatorBuilder: (_, _) => const Padding(
            padding: EdgeInsets.only(left: 64),
            child: SizedBox(
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFE6EDF5)),
              ),
            ),
          ),
          itemBuilder: (context, index) {
            final candidate = candidates[index];
            final did = _normalizeDid(candidate.did);
            final isSelected = selectedDids.contains(did);
            final disabledReason = existingMemberDids.contains(did)
                ? '已在群中'
                : null;
            return _InviteCandidateTile(
              candidate: candidate,
              selected: isSelected,
              disabledReason: disabledReason,
              onTap: disabledReason != null || onToggle == null
                  ? null
                  : () => onToggle!(candidate),
            );
          },
        ),
      ),
    );
  }
}

class _InviteCandidateTile extends StatelessWidget {
  const _InviteCandidateTile({
    required this.candidate,
    required this.selected,
    required this.disabledReason,
    required this.onTap,
  });

  final GroupInviteCandidate candidate;
  final bool selected;
  final String? disabledReason;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final isDisabled = disabledReason != null || onTap == null;
    final handle = candidate.handle?.trim();
    final subtitle = handle == null || handle.isEmpty
        ? DidDisplayFormatter.compactDid(candidate.did)
        : '@$handle';
    return AppPressableTile(
      onTap: onTap,
      semanticLabel: candidate.displayName,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(12),
          vertical: responsive.spacing(10),
        ),
        color: selected ? const Color(0xFFEAF2FF) : CupertinoColors.transparent,
        child: Opacity(
          opacity: isDisabled ? 0.58 : 1,
          child: Row(
            children: <Widget>[
              AvatarBadge(
                seed: candidate.avatarSeed ?? candidate.displayName,
                size: responsive.isPhone ? 38 : 42,
                avatarUri: candidate.avatarUri,
              ),
              SizedBox(width: responsive.spacing(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            candidate.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF101B32),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _IdentityKindBadge(kind: candidate.kind),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF66728A),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        _SourceBadge(label: candidate.sourceLabel),
                        if (disabledReason != null)
                          _SourceBadge(label: disabledReason!, muted: true),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: responsive.spacing(10)),
              _SelectionMark(selected: selected, disabled: isDisabled),
            ],
          ),
        ),
      ),
    );
  }
}

class _IdentityKindBadge extends StatelessWidget {
  const _IdentityKindBadge({required this.kind});

  final GroupInviteIdentityKind kind;

  @override
  Widget build(BuildContext context) {
    final isAgent = kind == GroupInviteIdentityKind.agent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isAgent ? const Color(0xFFEAF2FF) : const Color(0xFFE6F8EE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isAgent ? '智能体' : '用户',
        style: TextStyle(
          color: isAgent ? const Color(0xFF0B65F8) : const Color(0xFF0F8A4B),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: muted ? const Color(0xFFF1F3F6) : const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: muted ? const Color(0xFF8A96AA) : const Color(0xFF7A4E00),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected, required this.disabled});

  final bool selected;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final color = disabled
        ? const Color(0xFFD4DAE4)
        : selected
        ? const Color(0xFF0B65F8)
        : const Color(0xFFB9C2D0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: selected ? color : CupertinoColors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.4),
      ),
      child: selected
          ? const Icon(
              CupertinoIcons.check_mark,
              color: CupertinoColors.white,
              size: 15,
            )
          : null,
    );
  }
}

GroupInviteIdentityKind _kindFromIdentityText({
  required String? subjectType,
  required String did,
  required String displayName,
  required String? handle,
  String bio = '',
  List<String> tags = const <String>[],
}) {
  final subject = subjectType?.trim().toLowerCase();
  if (subject == 'agent' || subject == 'runtime_agent' || subject == 'bot') {
    return GroupInviteIdentityKind.agent;
  }
  final joined = <String>[
    did,
    displayName,
    handle ?? '',
    bio,
    ...tags,
  ].join(' ').toLowerCase();
  if (joined.contains(':agent:') ||
      joined.contains(':agents:') ||
      joined.contains(':runtime_agent:') ||
      joined.contains(' agent ') ||
      joined.contains('智能体')) {
    return GroupInviteIdentityKind.agent;
  }
  return GroupInviteIdentityKind.human;
}

String _displayNameFallback(String? handle, String did) {
  final normalizedHandle = handle?.trim();
  if (normalizedHandle != null && normalizedHandle.isNotEmpty) {
    return normalizedHandle;
  }
  return DidDisplayFormatter.compactDid(did);
}

String? _handleFromDirectPeer(String? peer) {
  final value = peer?.trim();
  if (value == null || value.isEmpty || value.startsWith('did:')) {
    return null;
  }
  if (value.startsWith('handle:')) {
    return value.substring('handle:'.length);
  }
  return value;
}

String? _firstNonEmpty(String? a, String? b) {
  final normalizedA = a?.trim();
  if (normalizedA != null && normalizedA.isNotEmpty) {
    return normalizedA;
  }
  final normalizedB = b?.trim();
  if (normalizedB != null && normalizedB.isNotEmpty) {
    return normalizedB;
  }
  return null;
}

String _normalizeDid(String value) => value.trim();

String _normalizeSearchText(String value) {
  var normalized = value.trim().toLowerCase();
  while (normalized.startsWith('@')) {
    normalized = normalized.substring(1).trimLeft();
  }
  return normalized;
}

bool _looksLikeGroupDid(String value) {
  final normalized = value.toLowerCase();
  return normalized.contains(':group:') || normalized.contains(':groups:');
}
