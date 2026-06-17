import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_router.dart';
import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/entities/user_profile.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../agents/agent_inbox_panel.dart';
import '../app_shell/providers/selected_conversation_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../chat/chat_page.dart';
import '../group/group_list_page.dart';
import '../group/group_provider.dart';
import '../profile/peer_profile_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/avatar_badge.dart';
import '../shared/copyable_did_line.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/responsive_layout.dart';
import '../shared/sidebar_workspace.dart';
import '../shared/widgets/app_widgets.dart';
import 'conversation_list_page.dart';
import 'conversation_peer_classifier.dart';

class ConversationWorkspacePage extends ConsumerWidget {
  const ConversationWorkspacePage({super.key, this.listFooter});

  final Widget? listFooter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final responsive = context.awikiResponsive;
    if (!responsive.supportsTwoPane) {
      return const ConversationListPage();
    }

    final selectedConversation = ref.watch(selectedConversationProvider);
    if (responsive.isMacDesktop) {
      return _MacConversationWorkspace(
        selectedConversation: selectedConversation,
        onConversationSelected: (conversation) async {
          ref
              .read(selectedConversationProvider.notifier)
              .selectConversation(conversation);
        },
        onClearSelection: () {
          ref.read(selectedConversationProvider.notifier).clearSelection();
        },
      );
    }
    return AwikiSidebarWorkspace(
      footer: listFooter,
      sidebar: ConversationListPage(
        embedded: true,
        selectedThreadId: selectedConversation?.threadId,
        bottomInset: listFooter == null ? 24 : 16,
        onConversationSelected: (conversation) async {
          ref
              .read(selectedConversationProvider.notifier)
              .selectConversation(conversation);
        },
      ),
      detailPane: selectedConversation == null
          ? const AwikiWorkspaceEmptyDetail()
          : ChatView(
              key: ValueKey('chat-view:${selectedConversation.threadId}'),
              conversation: selectedConversation,
              embedded: true,
              onBack: () {
                ref
                    .read(selectedConversationProvider.notifier)
                    .clearSelection();
              },
            ),
    );
  }
}

class _MacConversationWorkspace extends StatelessWidget {
  const _MacConversationWorkspace({
    required this.selectedConversation,
    required this.onConversationSelected,
    required this.onClearSelection,
  });

  final ConversationSummary? selectedConversation;
  final ConversationSelectionHandler onConversationSelected;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return DecoratedBox(
      decoration: const BoxDecoration(color: CupertinoColors.white),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 1200.0;

          return AwikiPaneLayout(
            listPaneWidth: responsive.displayScaled(
              _listPaneWidth(availableWidth),
            ),
            minListPaneWidth: responsive.displayScaled(
              _minListPaneWidth(availableWidth),
            ),
            minDetailPaneWidth: responsive.displayScaled(
              _minDetailPaneWidth(availableWidth),
            ),
            listPane: SizedBox(
              key: const Key('mac-conversation-list-pane'),
              child: ConversationListPage(
                embedded: true,
                macStyle: true,
                selectedThreadId: selectedConversation?.threadId,
                bottomInset: 18,
                onConversationSelected: onConversationSelected,
              ),
            ),
            detailPane: _MacConversationDetailArea(
              selectedConversation: selectedConversation,
              onClearSelection: onClearSelection,
            ),
          );
        },
      ),
    );
  }

  double _listPaneWidth(double availableWidth) {
    if (availableWidth < 560) {
      return 220;
    }
    if (availableWidth < 760) {
      return 260;
    }
    if (availableWidth < 980) {
      return 300;
    }
    return 340;
  }

  double _minListPaneWidth(double availableWidth) {
    return availableWidth < 700 ? 220 : 240;
  }

  double _minDetailPaneWidth(double availableWidth) {
    return availableWidth < 760 ? 320 : 360;
  }
}

enum _MacDetailSidePanel { conversationInfo, identityCard, agentInbox }

class _MacConversationDetailArea extends StatefulWidget {
  const _MacConversationDetailArea({
    required this.selectedConversation,
    required this.onClearSelection,
  });

  final ConversationSummary? selectedConversation;
  final VoidCallback onClearSelection;

  @override
  State<_MacConversationDetailArea> createState() =>
      _MacConversationDetailAreaState();
}

class _MacConversationDetailAreaState
    extends State<_MacConversationDetailArea> {
  static const double _sidePanelDividerHitWidth = 12;
  static const double _minChatPaneWidth = 370;
  static const double _maxConversationInfoWidth = 420;
  static const double _maxIdentityCardWidth = 560;
  static const double _maxAgentInboxWidth = 420;

  _MacDetailSidePanel _sidePanel = _MacDetailSidePanel.conversationInfo;
  bool _isSidePanelOpen = false;
  bool _isInlineSidePanelOpen = false;
  String? _activeThreadId;
  double? _conversationInfoWidth;
  double? _identityCardWidth;
  double? _agentInboxWidth;

  @override
  void didUpdateWidget(_MacConversationDetailArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedThreadId = widget.selectedConversation?.threadId;
    if (selectedThreadId != _activeThreadId) {
      _activeThreadId = selectedThreadId;
      _sidePanel = _MacDetailSidePanel.conversationInfo;
      _isSidePanelOpen = false;
      _isInlineSidePanelOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedConversation = widget.selectedConversation;
    if (selectedConversation == null) {
      return const AwikiWorkspaceEmptyDetail();
    }
    final responsive = context.awikiResponsive;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 640.0;
        final detailWidth = _sidePanelWidth(availableWidth);
        final canShowSidePanel =
            availableWidth >=
            _minSidePanelWidth(context) +
                responsive.displayScaled(_minChatPaneWidth) +
                responsive.displayScaled(_sidePanelDividerHitWidth);

        if (!canShowSidePanel && _isInlineSidePanelOpen) {
          return _buildSidePanel(selectedConversation, inline: true);
        }
        final visiblePanelIsOpen = canShowSidePanel
            ? _isSidePanelOpen
            : _isInlineSidePanelOpen;
        final conversationInfoPanelActive =
            _sidePanel == _MacDetailSidePanel.conversationInfo &&
            visiblePanelIsOpen;

        return Row(
          children: <Widget>[
            Expanded(
              child: ChatView(
                key: ValueKey('chat-view:${selectedConversation.threadId}'),
                conversation: selectedConversation,
                embedded: true,
                macStyle: true,
                onBack: widget.onClearSelection,
                onMacIdentityPanelTap: selectedConversation.isGroup
                    ? () {
                        _openIdentityPanel(canShowSidePanel: canShowSidePanel);
                      }
                    : null,
                onMacConversationInfoTap: () {
                  _toggleConversationInfo(canShowSidePanel: canShowSidePanel);
                },
                macConversationInfoPanelActive: conversationInfoPanelActive,
              ),
            ),
            if (canShowSidePanel && _isSidePanelOpen) ...<Widget>[
              _MacSidePanelDivider(
                onDragUpdate: (details) {
                  setState(() {
                    _setSidePanelWidth(
                      detailWidth - details.delta.dx,
                      availableWidth,
                    );
                  });
                },
              ),
              SizedBox(
                key: const Key('mac-side-panel'),
                width: detailWidth,
                child: _buildSidePanel(selectedConversation, inline: false),
              ),
            ],
          ],
        );
      },
    );
  }

  double _sidePanelWidth(double availableWidth) {
    final preferred =
        switch (_sidePanel) {
          _MacDetailSidePanel.identityCard => _identityCardWidth,
          _MacDetailSidePanel.agentInbox => _agentInboxWidth,
          _MacDetailSidePanel.conversationInfo => _conversationInfoWidth,
        } ??
        _defaultSidePanelWidth(context, availableWidth);
    return _clampSidePanelWidth(context, preferred, availableWidth);
  }

  double _defaultSidePanelWidth(BuildContext context, double availableWidth) {
    final responsive = context.awikiResponsive;
    if (_sidePanel == _MacDetailSidePanel.identityCard) {
      if (availableWidth < 920) {
        return responsive.displayScaled(320);
      }
      if (availableWidth < 1180) {
        return responsive.displayScaled(360);
      }
      return responsive.displayScaled(400);
    }
    if (_sidePanel == _MacDetailSidePanel.agentInbox) {
      if (availableWidth < 920) {
        return responsive.displayScaled(320);
      }
      return responsive.displayScaled(380);
    }
    if (availableWidth < 820) {
      return responsive.displayScaled(244);
    }
    return responsive.displayScaled(270);
  }

  double _minSidePanelWidth(BuildContext context) {
    final responsive = context.awikiResponsive;
    return responsive.displayScaled(
      _sidePanel == _MacDetailSidePanel.identityCard ||
              _sidePanel == _MacDetailSidePanel.agentInbox
          ? 300
          : 244,
    );
  }

  double _maxSidePanelWidth(BuildContext context, double availableWidth) {
    final responsive = context.awikiResponsive;
    final panelMax = switch (_sidePanel) {
      _MacDetailSidePanel.identityCard => responsive.displayScaled(
        _maxIdentityCardWidth,
      ),
      _MacDetailSidePanel.agentInbox => responsive.displayScaled(
        _maxAgentInboxWidth,
      ),
      _MacDetailSidePanel.conversationInfo => responsive.displayScaled(
        _maxConversationInfoWidth,
      ),
    };
    final availableMax =
        availableWidth -
        responsive.displayScaled(_minChatPaneWidth) -
        responsive.displayScaled(_sidePanelDividerHitWidth);
    return math.max(
      _minSidePanelWidth(context),
      math.min(panelMax, availableMax),
    );
  }

  double _clampSidePanelWidth(
    BuildContext context,
    double width,
    double availableWidth,
  ) {
    return width
        .clamp(
          _minSidePanelWidth(context),
          _maxSidePanelWidth(context, availableWidth),
        )
        .toDouble();
  }

  void _setSidePanelWidth(double width, double availableWidth) {
    final next = _clampSidePanelWidth(context, width, availableWidth);
    if (_sidePanel == _MacDetailSidePanel.identityCard) {
      _identityCardWidth = next;
    } else if (_sidePanel == _MacDetailSidePanel.agentInbox) {
      _agentInboxWidth = next;
    } else {
      _conversationInfoWidth = next;
    }
  }

  void _openIdentityPanel({required bool canShowSidePanel}) {
    setState(() {
      if (canShowSidePanel &&
          _sidePanel == _MacDetailSidePanel.identityCard &&
          _isSidePanelOpen) {
        _isSidePanelOpen = false;
        _isInlineSidePanelOpen = false;
        return;
      }
      _sidePanel = _MacDetailSidePanel.identityCard;
      _isSidePanelOpen = true;
      _isInlineSidePanelOpen = !canShowSidePanel;
    });
  }

  Widget _buildSidePanel(
    ConversationSummary selectedConversation, {
    required bool inline,
  }) {
    return KeyedSubtree(
      key: inline ? const Key('mac-inline-side-panel') : null,
      child: switch (_sidePanel) {
        _MacDetailSidePanel.identityCard => _MacPeerProfilePanel(
          key: ValueKey<String>(
            'mac-peer-profile-${selectedConversation.threadId}',
          ),
          conversation: selectedConversation,
          useBackButton: inline,
          onClose: inline
              ? _closeInlineSidePanel
              : () {
                  setState(() {
                    _sidePanel = _MacDetailSidePanel.conversationInfo;
                    _isSidePanelOpen = true;
                    _isInlineSidePanelOpen = false;
                  });
                },
        ),
        _MacDetailSidePanel.agentInbox => AgentInboxPanel(
          conversation: selectedConversation,
          useBackButton: inline,
          onClose: inline
              ? _closeInlineSidePanel
              : () {
                  setState(() {
                    _sidePanel = _MacDetailSidePanel.conversationInfo;
                    _isSidePanelOpen = true;
                    _isInlineSidePanelOpen = false;
                  });
                },
        ),
        _MacDetailSidePanel.conversationInfo => _MacAgentDetailPanel(
          conversation: selectedConversation,
          onBack: inline ? _closeInlineSidePanel : null,
        ),
      },
    );
  }

  void _toggleConversationInfo({required bool canShowSidePanel}) {
    setState(() {
      if (!canShowSidePanel) {
        _sidePanel = _MacDetailSidePanel.conversationInfo;
        _isSidePanelOpen = true;
        _isInlineSidePanelOpen = true;
        return;
      }
      if (_sidePanel == _MacDetailSidePanel.conversationInfo) {
        _isSidePanelOpen = !_isSidePanelOpen;
      } else {
        _sidePanel = _MacDetailSidePanel.conversationInfo;
        _isSidePanelOpen = true;
      }
      _isInlineSidePanelOpen = false;
    });
  }

  void _closeInlineSidePanel() {
    setState(() {
      _isInlineSidePanelOpen = false;
    });
  }
}

class _MacSidePanelDivider extends StatelessWidget {
  const _MacSidePanelDivider({required this.onDragUpdate});

  final GestureDragUpdateCallback onDragUpdate;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        key: const Key('mac-side-panel-resize-divider'),
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: onDragUpdate,
        child: SizedBox(
          width: responsive.displayScaled(
            _MacConversationDetailAreaState._sidePanelDividerHitWidth,
          ),
          child: const Center(
            child: SizedBox(
              width: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFE5EAF2)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MacPeerProfilePanel extends ConsumerWidget {
  const _MacPeerProfilePanel({
    super.key,
    required this.conversation,
    required this.onClose,
    this.useBackButton = false,
  });

  final ConversationSummary conversation;
  final VoidCallback onClose;
  final bool useBackButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetDid = conversation.targetDid?.trim();
    if (conversation.isGroup) {
      return _MacGroupInfoPanel(
        conversation: conversation,
        onClose: onClose,
        useBackButton: useBackButton,
      );
    }
    if (targetDid == null || targetDid.isEmpty) {
      return _MacPanelShell(
        title: _identityCardTitleForConversation(context, conversation),
        onClose: onClose,
        closeIcon: useBackButton ? CupertinoIcons.chevron_left : null,
        closeButtonKey: useBackButton
            ? const Key('mac-compact-panel-back-button')
            : null,
        closeSemanticLabel: useBackButton ? '返回会话' : '关闭身份卡',
        closeButtonLeading: useBackButton,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AwikiMeErrorText(
              message: context.l10n.peerProfileLoadFailed,
              textAlign: TextAlign.center,
              compact: true,
            ),
          ),
        ),
      );
    }

    final state = ref.watch(peerProfileProvider(targetDid));
    final profile = state.profile;
    if (state.isLoading) {
      return _MacPanelShell(
        title: _identityCardTitleForConversation(context, conversation),
        onClose: onClose,
        closeIcon: useBackButton ? CupertinoIcons.chevron_left : null,
        closeButtonKey: useBackButton
            ? const Key('mac-compact-panel-back-button')
            : null,
        closeSemanticLabel: useBackButton ? '返回会话' : '关闭身份卡',
        closeButtonLeading: useBackButton,
        child: const Center(child: CupertinoActivityIndicator()),
      );
    }
    if (profile == null) {
      return _MacPanelShell(
        title: _identityCardTitleForConversation(context, conversation),
        onClose: onClose,
        closeIcon: useBackButton ? CupertinoIcons.chevron_left : null,
        closeButtonKey: useBackButton
            ? const Key('mac-compact-panel-back-button')
            : null,
        closeSemanticLabel: useBackButton ? '返回会话' : '关闭身份卡',
        closeButtonLeading: useBackButton,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AwikiMeErrorText(
              message: context.l10n.peerProfileLoadFailed,
              textAlign: TextAlign.center,
              compact: true,
            ),
          ),
        ),
      );
    }

    final name = DidDisplayFormatter.profileName(profile);
    final profileContent = profile.profileMarkdown.trim().isNotEmpty
        ? profile.profileMarkdown.trim()
        : profile.bio.trim();
    final homepageUrl = ref
        .watch(profileHomepageResolverProvider)
        .homepageUrl(profile);

    return _MacPanelShell(
      title: _identityCardTitleForProfile(profile),
      onClose: onClose,
      closeIcon: useBackButton ? CupertinoIcons.chevron_left : null,
      closeButtonKey: useBackButton
          ? const Key('mac-compact-panel-back-button')
          : null,
      closeSemanticLabel: useBackButton ? '返回会话' : '关闭身份卡',
      closeButtonLeading: useBackButton,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
        children: <Widget>[
          _MacProfileCard(
            title: '身份信息',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AvatarBadge(
                      seed: name,
                      size: 56,
                      avatarUri: profile.avatarUri,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF101B32),
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            profile.did,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF66728A),
                              fontSize: 11.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _MacProfilePill(
                      label: localizeRelationshipLabel(
                        context.l10n,
                        state.relationship,
                      ),
                    ),
                    if (profile.handle?.trim().isNotEmpty == true)
                      _MacProfilePill(label: '@${profile.handle!.trim()}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _MacProfileCard(
            title: '主页',
            child: AppPressableTile(
              onTap: () async {
                await launchUrl(
                  Uri.parse(homepageUrl),
                  mode: LaunchMode.externalApplication,
                );
              },
              semanticLabel: '打开主页',
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBFDFF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5EAF2)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      CupertinoIcons.link,
                      color: Color(0xFF34415C),
                      size: 15,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        homepageUrl,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0B65F8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _MacProfileCard(
            title: '资料',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (profileContent.isEmpty)
                  Text(
                    context.l10n.profileEmpty,
                    style: const TextStyle(
                      color: Color(0xFF66728A),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  )
                else
                  MarkdownBody(
                    data: profileContent,
                    shrinkWrap: true,
                    styleSheet:
                        MarkdownStyleSheet.fromCupertinoTheme(
                          CupertinoTheme.of(context),
                        ).copyWith(
                          p: const TextStyle(
                            color: Color(0xFF17213A),
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                          h1: const TextStyle(
                            color: Color(0xFF101B32),
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                          h2: const TextStyle(
                            color: Color(0xFF101B32),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                  ),
                if (profile.tags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: profile.tags
                        .map((tag) => _MacProfilePill(label: tag))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _identityCardTitleForProfile(UserProfile profile) {
    final userName = profile.displayName.trim();
    final handle = profile.handle?.trim() ?? '';
    final titleName = userName.isNotEmpty
        ? userName
        : (handle.isNotEmpty
              ? handle
              : DidDisplayFormatter.compactDid(profile.did));
    return '$titleName 的身份卡';
  }

  String _identityCardTitleForConversation(
    BuildContext context,
    ConversationSummary conversation,
  ) {
    final title = DidDisplayFormatter.conversationTitle(
      conversation,
      context.l10n,
    );
    return '$title 的身份卡';
  }
}

class _MacGroupInfoPanel extends ConsumerStatefulWidget {
  const _MacGroupInfoPanel({
    required this.conversation,
    required this.onClose,
    this.useBackButton = false,
  });

  final ConversationSummary conversation;
  final VoidCallback onClose;
  final bool useBackButton;

  @override
  ConsumerState<_MacGroupInfoPanel> createState() => _MacGroupInfoPanelState();
}

class _MacGroupInfoPanelState extends ConsumerState<_MacGroupInfoPanel> {
  late GroupSummary _group;
  bool _didRequestMembers = false;
  bool _didRequestGroup = false;
  bool _isRefreshingMembers = false;

  @override
  void initState() {
    super.initState();
    _group = _groupFromConversation(widget.conversation);
  }

  @override
  void didUpdateWidget(covariant _MacGroupInfoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.groupId != widget.conversation.groupId ||
        oldWidget.conversation.threadId != widget.conversation.threadId) {
      _group = _groupFromConversation(widget.conversation);
      _didRequestMembers = false;
      _didRequestGroup = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupId = _group.groupId;
    final knownGroup = _knownGroup(groupId);
    if (knownGroup != null && knownGroup != _group) {
      _group = knownGroup;
    }
    _requestGroup(groupId);
    _requestMembers(groupId);
    final members = ref.watch(groupMembersProvider(groupId));
    final currentDid = ref.watch(sessionProvider).session?.did;
    final canManageMembers = canManageGroupMembers(_group);
    final theme = context.awikiTheme;
    return _MacPanelShell(
      title: '${_group.displayName} 的群聊信息',
      onClose: widget.onClose,
      closeIcon: widget.useBackButton ? CupertinoIcons.chevron_left : null,
      closeButtonKey: widget.useBackButton
          ? const Key('mac-compact-panel-back-button')
          : null,
      closeSemanticLabel: widget.useBackButton ? '返回会话' : '关闭群聊信息',
      closeButtonLeading: widget.useBackButton,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
        children: <Widget>[
          _MacProfileCard(
            title: '群聊信息',
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _group.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AwikiMeTextStyles.cardTitle,
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
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    AppPill(
                      label: context.l10n.groupMemberCount(_group.memberCount),
                    ),
                    AppPill(label: _group.myRole ?? 'member'),
                  ],
                ),
                const SizedBox(height: 14),
                CopyableDidLine(
                  value: groupId,
                  copySemanticLabel: '复制 Group DID',
                  copiedMessage: 'DID 已复制',
                  textKey: const Key('mac-group-info-did-value'),
                  buttonKey: const Key('mac-group-info-copy-did-button'),
                  textStyle: AwikiMeTextStyles.cardSubtitle,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _MacProfileCard(
            title: '成员',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _MacPanelIconButton(
                  key: const Key('mac-group-info-add-member-button'),
                  semanticLabel: '添加成员',
                  icon: CupertinoIcons.person_add,
                  onTap: canManageMembers ? _openAddMemberDialog : null,
                ),
                const SizedBox(width: 8),
                _MacPanelIconButton(
                  key: const Key('mac-group-info-refresh-button'),
                  semanticLabel: '刷新成员',
                  icon: CupertinoIcons.refresh,
                  isLoading: _isRefreshingMembers,
                  onTap: _isRefreshingMembers ? null : _refreshMembers,
                ),
              ],
            ),
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
          ),
          if (ref.watch(groupProvider).isLoading) ...<Widget>[
            const SizedBox(height: 12),
            Center(child: CupertinoActivityIndicator(color: theme.primary)),
          ],
        ],
      ),
    );
  }

  GroupSummary? _knownGroup(String groupId) {
    for (final group in ref.watch(groupProvider).groups) {
      if (group.groupId == groupId) {
        return group;
      }
    }
    return null;
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
        // Background loading should not replace the conversation-derived group
        // panel with an async Flutter error.
      }
    });
  }

  void _requestGroup(String groupId) {
    if (_didRequestGroup || _hasCompleteGroupData(_group)) {
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
        setState(() {
          _group = refreshed;
        });
      } catch (_) {
        // Keep the conversation-derived summary visible if the full snapshot
        // cannot be refreshed.
        try {
          await ref.read(groupProvider.notifier).loadGroupMembers(groupId);
        } catch (_) {
          // Member loading is best-effort during the initial side-panel render.
        }
      }
    });
  }

  bool _hasCompleteGroupData(GroupSummary group) {
    return hasKnownGroupRole(group);
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
      if (!mounted) {
        return;
      }
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

  void _openAddMemberDialog() {
    AppNavigator.showDialog<void>(
      context,
      (dialogContext) => AddGroupMemberDialog(
        groupId: _group.groupId,
        onGroupUpdated: (updated) {
          if (!mounted) {
            return;
          }
          setState(() {
            _group = updated;
          });
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
        setState(() {
          _group = updated;
        });
      },
    );
  }

  GroupSummary _groupFromConversation(ConversationSummary conversation) {
    final groupId = conversation.groupId?.trim().isNotEmpty == true
        ? conversation.groupId!.trim()
        : conversation.threadId;
    final name = conversation.displayName.trim().isNotEmpty
        ? conversation.displayName.trim()
        : groupId;
    return GroupSummary(
      groupId: groupId,
      displayName: name,
      description: '',
      memberCount: 0,
      lastMessageAt: conversation.lastMessageAt,
      avatarUri: conversation.avatarUri,
      membershipStatus: null,
    );
  }
}

class _MacProfileCard extends StatelessWidget {
  const _MacProfileCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF17213A),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _MacPanelShell extends StatelessWidget {
  const _MacPanelShell({
    required this.title,
    required this.onClose,
    required this.child,
    this.closeIcon,
    this.closeButtonKey,
    this.closeSemanticLabel = '关闭身份卡',
    this.closeButtonLeading = false,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;
  final IconData? closeIcon;
  final Key? closeButtonKey;
  final String closeSemanticLabel;
  final bool closeButtonLeading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFF8FAFD)),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Container(
              height: 60,
              padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE5EAF2))),
              ),
              child: Row(
                children: <Widget>[
                  if (closeButtonLeading) ...<Widget>[
                    _MacPanelIconButton(
                      key:
                          closeButtonKey ??
                          const Key('mac-side-panel-close-button'),
                      semanticLabel: closeSemanticLabel,
                      icon: closeIcon ?? CupertinoIcons.xmark,
                      onTap: onClose,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF101B32),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (!closeButtonLeading)
                    _MacPanelIconButton(
                      key:
                          closeButtonKey ??
                          const Key('mac-side-panel-close-button'),
                      semanticLabel: closeSemanticLabel,
                      icon: closeIcon ?? CupertinoIcons.xmark,
                      onTap: onClose,
                    ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _MacPanelIconButton extends StatelessWidget {
  const _MacPanelIconButton({
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
      size: responsive.displayScaled(32),
      backgroundColor: CupertinoColors.white,
      borderColor: const Color(0xFFDDE5F0),
      borderRadius: BorderRadius.circular(responsive.displayScaled(8)),
      child: Icon(
        icon,
        color: enabled ? const Color(0xFF34415C) : theme.tertiaryText,
        size: responsive.displayScaled(16),
      ),
    );
  }
}

class _MacProfilePill extends StatelessWidget {
  const _MacProfilePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF0B65F8),
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _MacAgentDetailPanel extends ConsumerWidget {
  const _MacAgentDetailPanel({required this.conversation, this.onBack});

  final ConversationSummary conversation;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classification = ref
        .watch(
          conversationPeerClassificationProvider(
            ConversationPeerTarget.fromConversation(conversation),
          ),
        )
        .maybeWhen(
          data: (value) => value,
          orElse: () => conversation.isGroup
              ? const ConversationPeerClassification.group()
              : const ConversationPeerClassification.unknown(),
        );
    final address = conversation.targetDid?.trim().isNotEmpty == true
        ? conversation.targetDid!.trim()
        : conversation.groupId ?? conversation.threadId;
    final children = <Widget>[
      if (onBack == null) ...<Widget>[
        const Text(
          '会话信息',
          style: TextStyle(
            color: Color(0xFF101B32),
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 22),
      ],
      const _MacDetailRow(
        label: '身份状态:',
        child: Row(
          children: <Widget>[
            Icon(
              CupertinoIcons.checkmark_shield_fill,
              color: Color(0xFF17BF63),
              size: 16,
            ),
            SizedBox(width: 6),
            Text(
              '已验证',
              style: TextStyle(
                color: Color(0xFF17BF63),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      _MacDetailRow(label: '所属:', text: classification.detailOwnerLabel),
      _MacDetailRow(
        label: 'DID:',
        child: CopyableDidLine(
          value: address,
          copySemanticLabel: '复制 DID',
          copiedMessage: 'DID 已复制',
          textKey: const Key('mac-conversation-did-value'),
          buttonKey: const Key('mac-conversation-copy-did-button'),
        ),
      ),
      _MacDetailRow(label: '类型:', text: classification.detailTypeLabel),
      const SizedBox(height: 16),
      const _MacDetailCard(
        title: '会话能力',
        children: <Widget>[
          _MacAbilityGridItem(
            icon: CupertinoIcons.chat_bubble_text,
            label: '发送消息',
          ),
          _MacAbilityGridItem(
            icon: CupertinoIcons.person_crop_circle,
            label: '查看资料',
          ),
          _MacAbilityGridItem(icon: CupertinoIcons.shield, label: '安全连接'),
          _MacAbilityGridItem(icon: CupertinoIcons.doc_text, label: '会话记录'),
        ],
      ),
      const SizedBox(height: 14),
      _MacDetailCard(
        title: '会话状态',
        children: <Widget>[
          _MacStatusLine(
            label: '未读消息:',
            value: '${conversation.unreadCount} 条',
            color: const Color(0xFF0B65F8),
          ),
          _MacStatusLine(
            label: '最近预览:',
            value: conversation.lastMessagePreview.trim().isEmpty
                ? context.l10n.conversationsNoMessagePreview
                : conversation.lastMessagePreview.trim(),
            color: const Color(0xFF66728A),
            indicatorKey: const Key('mac-conversation-preview-status-dot'),
            valueKey: const Key('mac-conversation-preview-status-value'),
          ),
          const _MacStatusLine(
            label: '连接状态:',
            value: '已建立',
            color: Color(0xFF17BF63),
          ),
        ],
      ),
    ];
    if (onBack != null) {
      return _MacPanelShell(
        title: '会话信息',
        onClose: onBack!,
        closeIcon: CupertinoIcons.chevron_left,
        closeButtonKey: const Key('mac-compact-panel-back-button'),
        closeSemanticLabel: '返回会话',
        closeButtonLeading: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          children: children,
        ),
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFF8FAFD)),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
          children: children,
        ),
      ),
    );
  }
}

class _MacDetailRow extends StatelessWidget {
  const _MacDetailRow({required this.label, this.text, this.child});

  final String label;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF34415C),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child:
                child ??
                Text(
                  text ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF17213A),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _MacDetailCard extends StatelessWidget {
  const _MacDetailCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF17213A),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }
}

class _MacAbilityGridItem extends StatelessWidget {
  const _MacAbilityGridItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: const Color(0xFF34415C)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF34415C),
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MacStatusLine extends StatelessWidget {
  const _MacStatusLine({
    required this.label,
    required this.value,
    required this.color,
    this.indicatorKey,
    this.valueKey,
  });

  final String label;
  final String value;
  final Color color;
  final Key? indicatorKey;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 70,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF66728A),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4.6),
            child: Icon(
              CupertinoIcons.circle_fill,
              key: indicatorKey,
              color: color,
              size: 7,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              key: valueKey,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: const TextStyle(
                color: Color(0xFF17213A),
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
