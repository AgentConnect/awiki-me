part of '../agents_page.dart';

class _AgentAccessPolicyPanel extends StatefulWidget {
  const _AgentAccessPolicyPanel({
    super.key,
    required this.policy,
    required this.isLoading,
    required this.isSaving,
    required this.errorText,
    required this.onUpdate,
  });

  final AgentInvocationPolicy policy;
  final bool isLoading;
  final bool isSaving;
  final String? errorText;
  final Future<bool> Function(AgentInvocationPolicy policy) onUpdate;

  @override
  State<_AgentAccessPolicyPanel> createState() =>
      _AgentAccessPolicyPanelState();
}

class _AgentAccessPolicyPanelState extends State<_AgentAccessPolicyPanel> {
  late final TextEditingController _whitelistController;
  late final TextEditingController _blacklistController;
  bool _savingLocally = false;
  String? _whitelistError;
  String? _blacklistError;

  @override
  void initState() {
    super.initState();
    _whitelistController = TextEditingController();
    _blacklistController = TextEditingController();
  }

  @override
  void dispose() {
    _whitelistController.dispose();
    _blacklistController.dispose();
    super.dispose();
  }

  bool get _busy => widget.isLoading || widget.isSaving || _savingLocally;

  Future<bool> _persist(AgentInvocationPolicy policy) async {
    if (_busy) {
      return false;
    }
    setState(() => _savingLocally = true);
    try {
      return await widget.onUpdate(policy);
    } finally {
      if (mounted) {
        setState(() => _savingLocally = false);
      }
    }
  }

  Future<void> _setMode(AgentInvocationPolicyMode mode) async {
    if (_busy || widget.policy.activeMode == mode) {
      return;
    }
    final saved = await _persist(widget.policy.copyWith(activeMode: mode));
    if (saved && mounted) {
      setState(() {
        _whitelistError = null;
        _blacklistError = null;
      });
    }
  }

  Future<void> _addHandle({
    required AgentInvocationPolicyMode listMode,
    required TextEditingController controller,
  }) async {
    final parsed = _parseSingleHandle(controller.text);
    if (parsed.error != null) {
      setState(() {
        if (listMode == AgentInvocationPolicyMode.whitelist) {
          _whitelistError = parsed.error;
        } else {
          _blacklistError = parsed.error;
        }
      });
      return;
    }
    final handle = parsed.handle!;
    final current = _handlesForMode(listMode);
    if (current.contains(handle)) {
      setState(() {
        if (listMode == AgentInvocationPolicyMode.whitelist) {
          _whitelistError = 'duplicate_whitelist';
        } else {
          _blacklistError = 'duplicate_blacklist';
        }
      });
      return;
    }
    final next = _policyWithList(listMode, <String>[...current, handle]);
    final saved = await _persist(next);
    if (saved && mounted) {
      controller.clear();
      setState(() {
        if (listMode == AgentInvocationPolicyMode.whitelist) {
          _whitelistError = null;
        } else {
          _blacklistError = null;
        }
      });
    }
  }

  Future<void> _removeHandle({
    required AgentInvocationPolicyMode listMode,
    required String handle,
  }) async {
    final nextList = _handlesForMode(
      listMode,
    ).where((item) => item != handle).toList(growable: false);
    await _persist(_policyWithList(listMode, nextList));
  }

  List<String> _handlesForMode(AgentInvocationPolicyMode mode) {
    return switch (mode) {
      AgentInvocationPolicyMode.whitelist => widget.policy.whitelistHandles,
      AgentInvocationPolicyMode.blacklist => widget.policy.blacklistHandles,
    };
  }

  AgentInvocationPolicy _policyWithList(
    AgentInvocationPolicyMode mode,
    List<String> handles,
  ) {
    return switch (mode) {
      AgentInvocationPolicyMode.whitelist => widget.policy.copyWith(
        whitelistHandles: handles,
      ),
      AgentInvocationPolicyMode.blacklist => widget.policy.copyWith(
        blacklistHandles: handles,
      ),
    };
  }

  _ParsedAccessHandle _parseSingleHandle(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const _ParsedAccessHandle(error: 'required');
    }
    if (RegExp(r'[\s,，;；]').hasMatch(trimmed)) {
      return const _ParsedAccessHandle(error: 'single_only');
    }
    final normalized = trimmed.replaceFirst(RegExp(r'^@+'), '').toLowerCase();
    if (normalized.isEmpty ||
        normalized.contains('@') ||
        normalized.contains('://') ||
        normalized.startsWith('did:')) {
      return const _ParsedAccessHandle(error: 'invalid');
    }
    return _ParsedAccessHandle(handle: normalized);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final type = theme.typographyFor(
      responsive.isCompact
          ? AwikiMeTypographyMode.compact
          : AwikiMeTypographyMode.expanded,
    );
    final saving = widget.isSaving || _savingLocally;
    return Container(
      padding: EdgeInsets.all(responsive.spacing(16)),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(responsive.radius(12)),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.l10n.agentAccessTitle,
                      style: type.cardTitle.copyWith(color: theme.title),
                    ),
                    SizedBox(height: responsive.spacing(2)),
                    Text(
                      context.l10n.agentAccessSubtitle,
                      style: type.cardSubtitle.copyWith(
                        color: theme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: responsive.spacing(12)),
              if (widget.isLoading || saving) ...<Widget>[
                const CupertinoActivityIndicator(),
                SizedBox(width: responsive.spacing(8)),
              ],
              SelectionContainer.disabled(
                child: _AccessModeToggle(
                  activeMode: widget.policy.activeMode,
                  onChanged: _busy ? null : (mode) => unawaited(_setMode(mode)),
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.spacing(14)),
          LayoutBuilder(
            builder: (context, constraints) {
              final whitelistActive =
                  widget.policy.activeMode ==
                  AgentInvocationPolicyMode.whitelist;
              final blacklistActive =
                  widget.policy.activeMode ==
                  AgentInvocationPolicyMode.blacklist;
              final modules = <Widget>[
                _AccessPolicyModule(
                  mode: AgentInvocationPolicyMode.whitelist,
                  title: context.l10n.agentAccessWhitelist,
                  active: whitelistActive,
                  handles: widget.policy.whitelistHandles,
                  controller: _whitelistController,
                  fieldKey: const Key('agent-access-whitelist-field'),
                  addKey: const Key('agent-access-whitelist-add'),
                  enabled: whitelistActive && !_busy,
                  errorText: _whitelistError,
                  onSubmitted: () => unawaited(
                    _addHandle(
                      listMode: AgentInvocationPolicyMode.whitelist,
                      controller: _whitelistController,
                    ),
                  ),
                  onRemove: (handle) => unawaited(
                    _removeHandle(
                      listMode: AgentInvocationPolicyMode.whitelist,
                      handle: handle,
                    ),
                  ),
                ),
                _AccessPolicyModule(
                  mode: AgentInvocationPolicyMode.blacklist,
                  title: context.l10n.agentAccessBlacklist,
                  active: blacklistActive,
                  handles: widget.policy.blacklistHandles,
                  controller: _blacklistController,
                  fieldKey: const Key('agent-access-blacklist-field'),
                  addKey: const Key('agent-access-blacklist-add'),
                  enabled: blacklistActive && !_busy,
                  errorText: _blacklistError,
                  onSubmitted: () => unawaited(
                    _addHandle(
                      listMode: AgentInvocationPolicyMode.blacklist,
                      controller: _blacklistController,
                    ),
                  ),
                  onRemove: (handle) => unawaited(
                    _removeHandle(
                      listMode: AgentInvocationPolicyMode.blacklist,
                      handle: handle,
                    ),
                  ),
                ),
              ];
              if (constraints.maxWidth >= responsive.displayScaled(680)) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: modules[0]),
                    SizedBox(width: responsive.spacing(12)),
                    Expanded(child: modules[1]),
                  ],
                );
              }
              return Column(
                children: <Widget>[
                  modules[0],
                  SizedBox(height: responsive.spacing(10)),
                  modules[1],
                ],
              );
            },
          ),
          if (widget.errorText != null) ...<Widget>[
            SizedBox(height: responsive.spacing(12)),
            _DiagnosticNotice(text: widget.errorText!),
          ],
        ],
      ),
    );
  }
}

class _ParsedAccessHandle {
  const _ParsedAccessHandle({this.handle, this.error});

  final String? handle;
  final String? error;
}

String _accessHandleErrorText(BuildContext context, String code) {
  return switch (code) {
    'duplicate_whitelist' => context.l10n.agentAccessDuplicateWhitelist,
    'duplicate_blacklist' => context.l10n.agentAccessDuplicateBlacklist,
    'required' => context.l10n.agentAccessHandleRequired,
    'single_only' => context.l10n.agentAccessSingleHandleOnly,
    'invalid' => context.l10n.agentAccessHandleInvalid,
    _ => code,
  };
}

class _AccessModeToggle extends StatelessWidget {
  const _AccessModeToggle({required this.activeMode, required this.onChanged});

  final AgentInvocationPolicyMode activeMode;
  final ValueChanged<AgentInvocationPolicyMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final blacklistActive = activeMode == AgentInvocationPolicyMode.blacklist;
    final enabled = onChanged != null;
    return Container(
      key: const Key('agent-access-mode-toggle'),
      padding: EdgeInsets.all(responsive.displayScaled(2)),
      decoration: BoxDecoration(
        color: theme.subtleSurface,
        borderRadius: BorderRadius.circular(responsive.radius(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _AccessModeSegment(
            key: const Key('agent-access-whitelist-mode'),
            label: context.l10n.agentAccessWhitelist,
            selected: !blacklistActive,
            color: theme.primary,
            onPressed: enabled
                ? () => onChanged!(AgentInvocationPolicyMode.whitelist)
                : null,
            semanticLabel: !blacklistActive
                ? context.l10n.agentAccessCurrentWhitelist
                : context.l10n.agentAccessSwitchToWhitelist,
          ),
          _AccessModeSegment(
            key: const Key('agent-access-blacklist-mode'),
            label: context.l10n.agentAccessBlacklist,
            selected: blacklistActive,
            color: theme.danger,
            onPressed: enabled
                ? () => onChanged!(AgentInvocationPolicyMode.blacklist)
                : null,
            semanticLabel: blacklistActive
                ? context.l10n.agentAccessCurrentBlacklist
                : context.l10n.agentAccessSwitchToBlacklist,
          ),
        ],
      ),
    );
  }
}

class _AccessModeSegment extends StatelessWidget {
  const _AccessModeSegment({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onPressed,
    required this.semanticLabel,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return AppPressable(
      onTap: onPressed,
      enabled: onPressed != null,
      selected: selected,
      semanticLabel: semanticLabel,
      tooltip: semanticLabel,
      borderRadius: BorderRadius.circular(responsive.radius(8)),
      child: AnimatedContainer(
        duration: AwikiMeMotion.fast,
        curve: AwikiMeMotion.emphasized,
        constraints: BoxConstraints(
          minHeight: responsive.displayScaled(responsive.isCompact ? 32 : 28),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(11),
          vertical: responsive.spacing(5),
        ),
        decoration: BoxDecoration(
          color: selected ? theme.surface : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(responsive.radius(8)),
          border: selected ? Border.all(color: theme.border) : null,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? color : theme.secondaryText,
            fontSize: responsive.metaSm,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _AccessPolicyModule extends StatelessWidget {
  const _AccessPolicyModule({
    required this.mode,
    required this.title,
    required this.active,
    required this.handles,
    required this.controller,
    required this.fieldKey,
    required this.addKey,
    required this.enabled,
    required this.errorText,
    required this.onSubmitted,
    required this.onRemove,
  });

  final AgentInvocationPolicyMode mode;
  final String title;
  final bool active;
  final List<String> handles;
  final TextEditingController controller;
  final Key fieldKey;
  final Key addKey;
  final bool enabled;
  final String? errorText;
  final VoidCallback onSubmitted;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final accentColor = switch (mode) {
      AgentInvocationPolicyMode.whitelist => theme.primary,
      AgentInvocationPolicyMode.blacklist => theme.danger,
    };
    final statusColor = active ? accentColor : theme.secondaryText;
    final fieldFill = enabled ? theme.surface : theme.subtleSurface;
    return AnimatedOpacity(
      duration: AwikiMeMotion.fast,
      opacity: active ? 1 : 0.55,
      child: AnimatedContainer(
        duration: AwikiMeMotion.fast,
        padding: EdgeInsets.all(responsive.spacing(12)),
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.circular(responsive.radius(12)),
          border: Border.all(color: theme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: active ? theme.title : theme.secondaryText,
                      fontSize: responsive.bodySm,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: responsive.spacing(7),
                    vertical: responsive.spacing(3),
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    active
                        ? context.l10n.agentAccessEnabled
                        : context.l10n.agentAccessDisabled,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: responsive.metaSm,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: responsive.spacing(10)),
            Row(
              children: <Widget>[
                Expanded(
                  child: CupertinoTextField(
                    key: fieldKey,
                    controller: controller,
                    enabled: enabled,
                    placeholder: context.l10n.agentAccessHandlePlaceholder,
                    padding: EdgeInsets.symmetric(
                      horizontal: responsive.spacing(10),
                      vertical: responsive.spacing(8),
                    ),
                    decoration: BoxDecoration(
                      color: fieldFill,
                      borderRadius: BorderRadius.circular(responsive.radius(9)),
                      border: Border.all(color: theme.border),
                    ),
                    style: TextStyle(
                      color: enabled ? theme.body : theme.secondaryText,
                      fontSize: responsive.bodySm,
                      height: 1.2,
                      fontFamily: 'monospace',
                    ),
                    placeholderStyle: TextStyle(
                      color: theme.tertiaryText,
                      fontSize: responsive.bodySm,
                    ),
                    onSubmitted: enabled ? (_) => onSubmitted() : null,
                  ),
                ),
                SizedBox(width: responsive.spacing(8)),
                _AccessAddButton(
                  key: addKey,
                  enabled: enabled,
                  onPressed: onSubmitted,
                ),
              ],
            ),
            if (errorText != null) ...<Widget>[
              SizedBox(height: responsive.spacing(6)),
              Text(
                _accessHandleErrorText(context, errorText!),
                style: TextStyle(
                  color: theme.danger,
                  fontSize: responsive.metaSm,
                ),
              ),
            ],
            SizedBox(height: responsive.spacing(10)),
            _AccessHandleList(
              mode: mode,
              handles: handles,
              active: active,
              enabled: enabled,
              onRemove: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessAddButton extends StatelessWidget {
  const _AccessAddButton({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final size = responsive.displayScaled(responsive.isCompact ? 38 : 32);
    return AppPressable(
      onTap: enabled ? onPressed : null,
      enabled: enabled,
      semanticLabel: context.l10n.agentAccessAddHandle,
      tooltip: context.l10n.agentAccessAddHandle,
      borderRadius: BorderRadius.circular(responsive.radius(9)),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: enabled ? theme.primary : theme.mutedSurface,
          borderRadius: BorderRadius.circular(responsive.radius(9)),
        ),
        alignment: Alignment.center,
        child: Icon(
          CupertinoIcons.plus,
          color: enabled ? theme.primaryForeground : theme.tertiaryText,
          size: responsive.iconSm,
        ),
      ),
    );
  }
}

class _AccessHandleList extends StatelessWidget {
  const _AccessHandleList({
    required this.mode,
    required this.handles,
    required this.active,
    required this.enabled,
    required this.onRemove,
  });

  final AgentInvocationPolicyMode mode;
  final List<String> handles;
  final bool active;
  final bool enabled;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    if (handles.isEmpty) {
      return Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: responsive.displayScaled(36)),
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: responsive.spacing(10)),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(responsive.radius(9)),
          border: Border.all(color: theme.border),
        ),
        child: Text(
          context.l10n.agentAccessNoHandles,
          style: TextStyle(
            color: theme.tertiaryText,
            fontSize: responsive.metaSm,
          ),
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (final handle in handles) ...<Widget>[
          _AccessHandleRow(
            key: ValueKey<String>('access-${mode.wireValue}-$handle'),
            handle: handle,
            active: active,
            enabled: enabled,
            onRemove: () => onRemove(handle),
          ),
          if (handle != handles.last) SizedBox(height: responsive.spacing(6)),
        ],
      ],
    );
  }
}

class _AccessHandleRow extends StatelessWidget {
  const _AccessHandleRow({
    super.key,
    required this.handle,
    required this.active,
    required this.enabled,
    required this.onRemove,
  });

  final String handle;
  final bool active;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Container(
      constraints: BoxConstraints(minHeight: responsive.displayScaled(36)),
      padding: EdgeInsets.only(
        left: responsive.spacing(10),
        right: responsive.spacing(4),
      ),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(responsive.radius(9)),
        border: Border.all(color: theme.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '@$handle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? theme.body : theme.secondaryText,
                fontSize: responsive.bodySm,
                fontWeight: FontWeight.w400,
                fontFamily: 'monospace',
              ),
            ),
          ),
          AppIconButton(
            onPressed: enabled ? onRemove : null,
            semanticLabel: context.l10n.agentAccessRemoveHandle,
            tooltip: context.l10n.commonDelete,
            size: responsive.displayScaled(30),
            borderRadius: BorderRadius.circular(responsive.radius(7)),
            child: Icon(
              CupertinoIcons.xmark,
              color: enabled ? theme.secondaryText : theme.tertiaryText,
              size: responsive.displayScaled(13),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticInfoPanel extends StatefulWidget {
  const _DiagnosticInfoPanel({super.key, required this.agent});

  final AgentSummary agent;

  @override
  State<_DiagnosticInfoPanel> createState() => _DiagnosticInfoPanelState();
}

class _DiagnosticInfoPanelState extends State<_DiagnosticInfoPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final type = theme.typographyFor(
      responsive.isCompact
          ? AwikiMeTypographyMode.compact
          : AwikiMeTypographyMode.expanded,
    );
    final agent = widget.agent;
    final essentialRows = _essentialDiagnosticRows(context.l10n, agent);
    final moreRows = _expandedDiagnosticRows(context.l10n, agent);
    final errorText = _diagnosticErrorText(agent);
    final hasMore = moreRows.isNotEmpty;

    return Container(
      padding: EdgeInsets.all(responsive.spacing(16)),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(responsive.radius(12)),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.l10n.agentDiagnosticsTitle,
                      style: type.cardTitle.copyWith(color: theme.title),
                    ),
                    SizedBox(height: responsive.spacing(2)),
                    Text(
                      agent.isDaemon
                          ? context.l10n.agentDiagnosticsDaemonSubtitle
                          : context.l10n.agentDiagnosticsAgentSubtitle,
                      style: type.cardSubtitle.copyWith(
                        color: theme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.spacing(14)),
          _DiagnosticRows(rows: essentialRows),
          if (errorText != null) ...<Widget>[
            SizedBox(height: responsive.spacing(12)),
            _DiagnosticNotice(text: errorText),
          ],
          if (hasMore) ...<Widget>[
            SizedBox(height: responsive.spacing(12)),
            SelectionContainer.disabled(
              child: _DiagnosticMoreButton(
                expanded: _expanded,
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ),
            if (_expanded) ...<Widget>[
              SizedBox(height: responsive.spacing(10)),
              _DiagnosticRows(rows: moreRows, compact: true),
            ],
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.danger = false,
    this.isLoading = false,
    this.semanticsIdentifier,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final bool isLoading;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final foreground = danger
        ? theme.danger
        : primary
        ? theme.primaryForeground
        : theme.body;
    final background = danger
        ? CupertinoColors.transparent
        : primary
        ? theme.primary
        : theme.surface;
    final borderColor = danger
        ? CupertinoColors.transparent
        : primary
        ? theme.primary
        : theme.border;
    return AppPressable(
      onTap: isLoading ? null : onPressed,
      semanticLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      tooltip: label,
      enabled: onPressed != null && !isLoading,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(responsive.radius(8)),
      builder: (context, state, child) {
        return AnimatedOpacity(
          opacity: state.enabled
              ? state.pressed
                    ? 0.78
                    : state.hovered || state.focused
                    ? 0.90
                    : 1
              : 0.55,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      child: Container(
        constraints: BoxConstraints(
          minHeight: responsive.displayScaled(responsive.isCompact ? 38 : 32),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(12),
          vertical: responsive.spacing(7),
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(responsive.radius(8)),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isLoading)
              CupertinoActivityIndicator(radius: responsive.displayScaled(7))
            else
              Icon(icon, size: responsive.iconSm, color: foreground),
            SizedBox(width: responsive.spacing(6)),
            Text(
              label,
              style: theme.buttonLabel.copyWith(
                color: foreground,
                fontSize: responsive.bodySm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentErrorBanner extends StatelessWidget {
  const _AgentErrorBanner({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final resolvedMessage = localizeAgentUiMessage(context.l10n, message);
    final retryButton = onRetry == null
        ? null
        : AppPressable(
            onTap: onRetry,
            semanticLabel: context.l10n.commonRetry,
            tooltip: context.l10n.commonRetry,
            borderRadius: BorderRadius.circular(responsive.radius(8)),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: responsive.spacing(10),
                vertical: responsive.spacing(5),
              ),
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(responsive.radius(8)),
              ),
              child: Text(
                context.l10n.commonRetry,
                style: TextStyle(
                  color: AwikiMeColors.danger,
                  fontSize: responsive.metaSm,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          );
    return AwikiMeErrorNotice(
      message: resolvedMessage,
      compact: true,
      trailing: retryButton,
    );
  }
}

class _DiagnosticRows extends StatelessWidget {
  const _DiagnosticRows({required this.rows, this.compact = false});

  final List<_DiagnosticRowData> rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Column(
      children: <Widget>[
        for (var index = 0; index < rows.length; index++) ...<Widget>[
          if (index > 0)
            Padding(
              padding: EdgeInsets.symmetric(vertical: responsive.spacing(4)),
              child: Container(height: 1, color: theme.border),
            ),
          _DiagnosticInfoRow(row: rows[index], compact: compact),
        ],
      ],
    );
  }
}

class _DiagnosticInfoRow extends StatelessWidget {
  const _DiagnosticInfoRow({required this.row, required this.compact});

  final _DiagnosticRowData row;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: responsive.spacing(compact ? 3 : 5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: responsive.displayScaled(compact ? 88 : 96),
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: responsive.metaSm,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          SizedBox(width: responsive.spacing(10)),
          Expanded(
            child: Text(
              row.value,
              maxLines: row.isLong ? 3 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.body,
                fontSize: compact ? responsive.metaSm : responsive.bodySm,
                fontWeight: FontWeight.w400,
                height: 1.28,
                fontFamily: row.copyable ? 'monospace' : null,
              ),
            ),
          ),
          if (row.copyable) ...<Widget>[
            SizedBox(width: responsive.spacing(8)),
            _InlineCopyButton(text: row.copyText ?? row.value),
          ],
        ],
      ),
    );
  }
}

class _DiagnosticNotice extends StatelessWidget {
  const _DiagnosticNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: responsive.spacing(12),
        vertical: responsive.spacing(10),
      ),
      decoration: BoxDecoration(
        color: theme.warningContainer,
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: theme.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: responsive.spacing(1)),
            child: Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: theme.warning,
              size: responsive.iconSm,
            ),
          ),
          SizedBox(width: responsive.spacing(8)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: theme.body,
                fontSize: responsive.bodySm,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticMoreButton extends StatelessWidget {
  const _DiagnosticMoreButton({
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return AppPressable(
      onTap: onPressed,
      semanticLabel: expanded
          ? context.l10n.agentDiagnosticsCollapseDetails
          : context.l10n.agentDiagnosticsShowMoreDetails,
      tooltip: expanded
          ? context.l10n.agentDiagnosticsCollapse
          : context.l10n.agentDiagnosticsShowMore,
      borderRadius: BorderRadius.circular(responsive.radius(8)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(10),
          vertical: responsive.spacing(8),
        ),
        decoration: BoxDecoration(
          color: theme.subtleSurface,
          borderRadius: BorderRadius.circular(responsive.radius(8)),
          border: Border.all(color: theme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              expanded
                  ? context.l10n.agentDiagnosticsCollapse
                  : context.l10n.agentDiagnosticsShowMore,
              style: TextStyle(
                color: theme.body,
                fontSize: responsive.metaSm,
                fontWeight: FontWeight.w400,
              ),
            ),
            SizedBox(width: responsive.spacing(5)),
            Icon(
              expanded
                  ? CupertinoIcons.chevron_up
                  : CupertinoIcons.chevron_down,
              color: theme.secondaryText,
              size: responsive.iconSm * 0.78,
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticRowData {
  const _DiagnosticRowData({
    required this.label,
    required this.value,
    this.copyable = false,
    this.copyText,
    this.isLong = false,
  });

  final String label;
  final String value;
  final bool copyable;
  final String? copyText;
  final bool isLong;
}

List<_DiagnosticRowData> _essentialDiagnosticRows(
  AppLocalizations l10n,
  AgentSummary agent,
) {
  return <_DiagnosticRowData>[
    _DiagnosticRowData(
      label: 'DID',
      value: agent.agentDid,
      copyable: true,
      copyText: agent.agentDid,
      isLong: true,
    ),
    if (_nonEmpty(agent.handle) != null)
      _DiagnosticRowData(
        label: 'Handle',
        value: _nonEmpty(agent.handle)!,
        copyable: true,
        copyText: _nonEmpty(agent.handle)!,
      ),
    if (agent.isDaemon && _nonEmpty(agent.latest.version) != null)
      _DiagnosticRowData(
        label: l10n.agentDiagnosticCurrentVersion,
        value: _nonEmpty(agent.latest.version)!,
      ),
    if (agent.isDaemon && _nonEmpty(agent.latest.platform) != null)
      _DiagnosticRowData(
        label: l10n.agentDiagnosticPlatform,
        value: _nonEmpty(agent.latest.platform)!,
      ),
  ];
}

List<_DiagnosticRowData> _expandedDiagnosticRows(
  AppLocalizations l10n,
  AgentSummary agent,
) {
  final rows = <_DiagnosticRowData>[];
  final latest = agent.latest;
  void add(String label, Object? value, {String? key, bool isLong = false}) {
    final text = _nonEmpty(value);
    if (text == null) {
      return;
    }
    rows.add(
      _DiagnosticRowData(
        label: label,
        value: _redactDiagnosticValue(text, key: key ?? label),
        isLong: isLong || text.length > 48,
      ),
    );
  }

  if (agent.isDaemon) {
    add(
      l10n.agentDiagnosticLatestVersion,
      latest.latestVersion,
      key: 'latest_version',
    );
    add(
      l10n.agentDiagnosticMinSupportedVersion,
      latest.minSupportedVersion,
      key: 'min_supported_version',
    );
    add(l10n.agentDiagnosticService, latest.service, key: 'service');
    add(
      l10n.agentDiagnosticLastSeen,
      latest.lastSeenAt?.toLocal().toString(),
      key: 'last_seen',
    );
  }
  add(
    l10n.agentDiagnosticErrorCode,
    latest.lastErrorCode,
    key: 'last_error_code',
  );
  for (final entry in latest.diagnosticsSummary.entries) {
    if (!_shouldShowDiagnosticSummaryEntry(agent, entry.key, entry.value)) {
      continue;
    }
    add(
      _diagnosticLabel(l10n, entry.key),
      entry.value,
      key: entry.key,
      isLong: true,
    );
  }
  return rows;
}

String? _diagnosticErrorText(AgentSummary agent) {
  final summary = _nonEmpty(agent.latest.lastErrorSummary);
  if (summary == null) {
    return null;
  }
  return _redactDiagnosticValue(summary, key: 'last_error_summary');
}

bool _shouldShowDiagnosticSummaryEntry(
  AgentSummary agent,
  String key,
  Object? value,
) {
  final text = _nonEmpty(value);
  if (text == null) {
    return false;
  }
  final normalized = key.trim().toLowerCase();
  const daemonOwnedKeys = <String>{
    'version',
    'latest_version',
    'min_supported_version',
    'platform',
    'service',
    'service_installed',
    'installation_status',
    'download_base_url',
    'base_url',
  };
  if (agent.isRuntime && daemonOwnedKeys.contains(normalized)) {
    return false;
  }
  return true;
}

String _diagnosticLabel(AppLocalizations l10n, String key) {
  switch (key.trim().toLowerCase()) {
    case 'runner':
      return l10n.agentDiagnosticRunner;
    case 'profile_status':
      return l10n.agentDiagnosticProfileStatus;
    case 'installation_status':
      return l10n.agentDiagnosticInstallationStatus;
    case 'service_installed':
      return l10n.agentDiagnosticServiceInstalled;
    case 'config_summary':
      return l10n.agentDiagnosticConfigSummary;
    case 'hermes_profile':
      return l10n.agentDiagnosticHermesProfile;
    case 'runner_status':
      return l10n.agentDiagnosticRunnerStatus;
    case 'active_session_count':
      return l10n.agentDiagnosticActiveSessionCount;
    default:
      return key;
  }
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

class _InlineCopyButton extends StatelessWidget {
  const _InlineCopyButton({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return SelectionContainer.disabled(
      child: AppIconButton(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            AwikiMeToast.show(context, context.l10n.commonCopied);
          }
        },
        semanticLabel: context.l10n.commonCopy,
        tooltip: context.l10n.commonCopy,
        size: responsive.displayScaled(28),
        padding: EdgeInsets.all(responsive.spacing(5)),
        borderRadius: BorderRadius.circular(responsive.radius(7)),
        child: Icon(
          CupertinoIcons.doc_on_doc,
          color: theme.secondaryText,
          size: responsive.iconSm,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Text(
      text,
      style: TextStyle(color: theme.title, fontWeight: FontWeight.w400),
    );
  }
}

class _RunStatusPill extends StatelessWidget {
  const _RunStatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _runStatusColor(status).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: _runStatusColor(status),
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

Color _runStatusColor(String status) {
  switch (status.trim().toLowerCase()) {
    case 'succeeded':
    case 'finished':
      return AwikiMeColors.online;
    case 'failed':
      return AwikiMeColors.danger;
    case 'queued':
    case 'pending':
    case 'running':
      return AwikiMeColors.alert;
    default:
      return AwikiMePalette.mutedNeutral;
  }
}

String _redactDiagnosticValue(Object? value, {String? key}) {
  if (_isSensitiveDiagnosticKey(key)) {
    return '<redacted>';
  }
  var text = value?.toString() ?? '';
  text = text.replaceAllMapped(
    RegExp(
      r'\b(authorization)\s*:\s*bearer\s+([^\s,;]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}: Bearer <redacted>',
  );
  text = text.replaceAllMapped(
    RegExp(
      r'\b(token|jwt|private[_-]?key|api[_-]?key|secret|signature)\s*[:=]\s*([^\s,;}]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=<redacted>',
  );
  text = text.replaceAll(
    RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b'),
    '<redacted>',
  );
  text = text.replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]{8,}\b'), '<redacted>');
  text = text.replaceAll(
    RegExp(
      r'(/Users/[^\s,;:]+|/home/[^\s,;:]+|/tmp/[^\s,;:]+|/var/[^\s,;:]+|/private/[^\s,;:]+|[A-Za-z]:\\[^\s,;]+)',
    ),
    '<path>',
  );
  return text;
}

bool _isSensitiveDiagnosticKey(String? key) {
  final normalized = key?.toLowerCase().replaceAll('-', '_');
  if (normalized == null || normalized.isEmpty) {
    return false;
  }
  return normalized.contains('token') ||
      normalized.contains('jwt') ||
      normalized.contains('private_key') ||
      normalized.contains('api_key') ||
      normalized.contains('secret') ||
      normalized.contains('authorization') ||
      normalized.contains('prompt') ||
      normalized.contains('log') ||
      normalized.endsWith('_path') ||
      normalized == 'path';
}
