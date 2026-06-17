part of '../conversation_workspace_page.dart';

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
