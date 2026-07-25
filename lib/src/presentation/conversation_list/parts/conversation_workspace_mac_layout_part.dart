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
      child: AwikiPaneLayout(
        listPaneWidth: responsive.displayScaled(272),
        minListPaneWidth: responsive.displayScaled(240),
        minDetailPaneWidth: responsive.displayScaled(360),
        listPane: SizedBox(
          key: const Key('mac-conversation-list-pane'),
          child: ConversationListPage(
            embedded: true,
            macStyle: true,
            selectedConversationId: selectedConversation?.conversationId,
            bottomInset: 18,
            onConversationSelected: onConversationSelected,
          ),
        ),
        detailPane: _MacConversationDetailArea(
          selectedConversation: selectedConversation,
          onClearSelection: onClearSelection,
        ),
      ),
    );
  }
}

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

  bool _isSidePanelOpen = false;
  bool _isInlineSidePanelOpen = false;
  String? _activeConversationId;
  double? _conversationInfoWidth;

  @override
  void didUpdateWidget(_MacConversationDetailArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedConversationId = widget.selectedConversation?.conversationId;
    if (selectedConversationId != _activeConversationId) {
      _activeConversationId = selectedConversationId;
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
        return Row(
          children: <Widget>[
            Expanded(
              child: ChatView(
                key: ValueKey(
                  'chat-view:${selectedConversation.conversationId}',
                ),
                conversation: selectedConversation,
                embedded: true,
                macStyle: true,
                onBack: widget.onClearSelection,
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
        _conversationInfoWidth ??
        _defaultSidePanelWidth(context, availableWidth);
    return _clampSidePanelWidth(context, preferred, availableWidth);
  }

  double _defaultSidePanelWidth(BuildContext context, double availableWidth) {
    final responsive = context.awikiResponsive;
    if (availableWidth < 820) {
      return responsive.displayScaled(244);
    }
    return responsive.displayScaled(270);
  }

  double _minSidePanelWidth(BuildContext context) {
    final responsive = context.awikiResponsive;
    return responsive.displayScaled(244);
  }

  double _maxSidePanelWidth(BuildContext context, double availableWidth) {
    final responsive = context.awikiResponsive;
    final panelMax = responsive.displayScaled(_maxConversationInfoWidth);
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
    _conversationInfoWidth = next;
  }

  Widget _buildSidePanel(
    ConversationSummary selectedConversation, {
    required bool inline,
  }) {
    return KeyedSubtree(
      key: inline ? const Key('mac-inline-side-panel') : null,
      child: _MacAgentDetailPanel(
        conversation: selectedConversation,
        onBack: inline ? _closeInlineSidePanel : null,
      ),
    );
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
                decoration: BoxDecoration(color: AwikiMePalette.hairline),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
