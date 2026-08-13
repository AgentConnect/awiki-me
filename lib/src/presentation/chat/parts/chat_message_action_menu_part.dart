part of '../chat_page.dart';

class _MessageActionMenu extends StatefulWidget {
  const _MessageActionMenu({
    required this.contextSnapshot,
    required this.actions,
    required this.anchors,
    required this.onAction,
    required this.onDesktopPointerDown,
    required this.onDisposed,
  });

  final MessageActionContext contextSnapshot;
  final List<MessageActionSpec> actions;
  final TextSelectionToolbarAnchors anchors;
  final Future<void> Function(MessageActionSpec action) onAction;
  final void Function(
    MessageActionSpec action,
    int pointer,
    Rect activationBounds,
  )
  onDesktopPointerDown;
  final VoidCallback onDisposed;

  @override
  State<_MessageActionMenu> createState() => _MessageActionMenuState();
}

class _MessageActionMenuState extends State<_MessageActionMenu> {
  @override
  void dispose() {
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.contextSnapshot.isDesktop) {
      return _DesktopMessageActionMenu(
        actions: widget.actions,
        contextSnapshot: widget.contextSnapshot,
        anchor: widget.anchors.primaryAnchor,
        onAction: widget.onAction,
        onPointerDown: widget.onDesktopPointerDown,
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: widget.anchors,
      buttonItems: <ContextMenuButtonItem>[
        for (final action in widget.actions)
          ContextMenuButtonItem(
            label: action.label,
            onPressed: action.isEnabled(widget.contextSnapshot)
                ? () => unawaited(widget.onAction(action))
                : null,
          ),
      ],
    );
  }
}

class _DesktopMessageActionMenu extends StatelessWidget {
  const _DesktopMessageActionMenu({
    required this.actions,
    required this.contextSnapshot,
    required this.anchor,
    required this.onAction,
    required this.onPointerDown,
  });

  final List<MessageActionSpec> actions;
  final MessageActionContext contextSnapshot;
  final Offset anchor;
  final Future<void> Function(MessageActionSpec action) onAction;
  final void Function(
    MessageActionSpec action,
    int pointer,
    Rect activationBounds,
  )
  onPointerDown;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final screenPadding = responsive.displayScaled(8);
    final topPadding = MediaQuery.paddingOf(context).top + screenPadding;
    final menuWidth = responsive.displayScaled(156);
    final radius = responsive.displayScaled(9);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        screenPadding,
        topPadding,
        screenPadding,
        screenPadding,
      ),
      child: CustomSingleChildLayout(
        delegate: DesktopTextSelectionToolbarLayoutDelegate(
          anchor: anchor - Offset(screenPadding, topPadding),
        ),
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape):
                ContextMenuController.removeAny,
            const SingleActivator(LogicalKeyboardKey.arrowDown): () {
              FocusScope.of(context).nextFocus();
            },
            const SingleActivator(LogicalKeyboardKey.arrowUp): () {
              FocusScope.of(context).previousFocus();
            },
          },
          child: FocusTraversalGroup(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              role: SemanticsRole.menu,
              child: ConstrainedBox(
                key: const Key('message-action-menu'),
                constraints: BoxConstraints.tightFor(width: menuWidth),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: theme.border),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: theme.title.withValues(alpha: 0.18),
                        blurRadius: responsive.displayScaled(16),
                        offset: Offset(0, responsive.displayScaled(6)),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: Padding(
                      padding: EdgeInsets.all(responsive.displayScaled(4)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (
                            var index = 0;
                            index < actions.length;
                            index++
                          ) ...[
                            if (index > 0 &&
                                actions[index - 1].group !=
                                    actions[index].group)
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: responsive.displayScaled(3),
                                ),
                                child: SizedBox(
                                  height: 1,
                                  child: ColoredBox(color: theme.border),
                                ),
                              ),
                            _DesktopMessageActionMenuItem(
                              action: actions[index],
                              contextSnapshot: contextSnapshot,
                              onAction: onAction,
                              onPointerDown: onPointerDown,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopMessageActionMenuItem extends StatefulWidget {
  const _DesktopMessageActionMenuItem({
    required this.action,
    required this.contextSnapshot,
    required this.onAction,
    required this.onPointerDown,
  });

  final MessageActionSpec action;
  final MessageActionContext contextSnapshot;
  final Future<void> Function(MessageActionSpec action) onAction;
  final void Function(
    MessageActionSpec action,
    int pointer,
    Rect activationBounds,
  )
  onPointerDown;

  @override
  State<_DesktopMessageActionMenuItem> createState() =>
      _DesktopMessageActionMenuItemState();
}

class _DesktopMessageActionMenuItemState
    extends State<_DesktopMessageActionMenuItem> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'message-action-item');

  bool _hovered = false;
  bool _focused = false;

  bool get _enabled => widget.action.isEnabled(widget.contextSnapshot);

  void _activate() {
    if (_enabled) {
      unawaited(widget.onAction(widget.action));
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_enabled || event.buttons & kPrimaryMouseButton == 0) {
      return;
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return;
    }
    // SelectableRegion replaces its toolbar during this pointer sequence, so
    // the original menu item no longer exists by PointerUp on desktop.
    widget.onPointerDown(
      widget.action,
      event.pointer,
      renderBox.localToGlobal(Offset.zero) & renderBox.size,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_enabled || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final enabled = _enabled;
    final foreground = widget.action.destructive ? theme.alert : theme.title;
    final highlight = _hovered || _focused
        ? theme.primary.withValues(alpha: 0.08)
        : const Color(0x00000000);
    return Semantics(
      role: SemanticsRole.menuItem,
      label: widget.action.label,
      enabled: enabled,
      button: true,
      onTap: enabled ? _activate : null,
      child: Focus(
        focusNode: _focusNode,
        canRequestFocus: enabled,
        onFocusChange: (value) {
          if (_focused != value) {
            setState(() => _focused = value);
          }
        },
        onKeyEvent: _handleKeyEvent,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) {
            if (enabled && !_hovered) {
              setState(() => _hovered = true);
            }
          },
          onExit: (_) {
            if (_hovered) {
              setState(() => _hovered = false);
            }
          },
          child: Listener(
            key: Key('message-action:${widget.action.id.name}'),
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handlePointerDown,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              height: responsive.displayScaled(37),
              decoration: BoxDecoration(
                color: highlight,
                borderRadius: BorderRadius.circular(
                  responsive.displayScaled(5),
                ),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: responsive.displayScaled(9),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    widget.action.icon,
                    size: responsive.displayScaled(15),
                    color: enabled
                        ? foreground
                        : theme.secondaryText.withValues(alpha: 0.45),
                  ),
                  SizedBox(width: responsive.displayScaled(9)),
                  Expanded(
                    child: Text(
                      widget.action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled
                            ? foreground
                            : theme.secondaryText.withValues(alpha: 0.45),
                        fontSize: responsive.displayScaled(13),
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
