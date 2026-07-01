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
          _whitelistError = '这个 Handle 已在白名单中。';
        } else {
          _blacklistError = '这个 Handle 已在黑名单中。';
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
      return const _ParsedAccessHandle(error: '请输入 Handle。');
    }
    if (RegExp(r'[\s,，;；]').hasMatch(trimmed)) {
      return const _ParsedAccessHandle(error: '每次只能添加一个 Handle。');
    }
    final normalized = trimmed.replaceFirst(RegExp(r'^@+'), '').toLowerCase();
    if (normalized.isEmpty ||
        normalized.contains('@') ||
        normalized.contains('://') ||
        normalized.startsWith('did:')) {
      return const _ParsedAccessHandle(error: '请输入短 Handle 或完整 Handle。');
    }
    return _ParsedAccessHandle(handle: normalized);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final saving = widget.isSaving || _savingLocally;
    return Container(
      padding: EdgeInsets.all(responsive.spacing(16)),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFFE4EAF3)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F0B1220),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: responsive.displayScaled(34),
                height: responsive.displayScaled(34),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F5FF),
                  borderRadius: BorderRadius.circular(responsive.radius(9)),
                ),
                child: Icon(
                  CupertinoIcons.lock_shield,
                  color: const Color(0xFF0B65F8),
                  size: responsive.iconMd,
                ),
              ),
              SizedBox(width: responsive.spacing(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '访问权限',
                      style: TextStyle(
                        color: const Color(0xFF101B32),
                        fontSize: responsive.bodyMd,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: responsive.spacing(2)),
                    Text(
                      '配置 Handle 对于智能体的控制权限',
                      style: TextStyle(
                        color: const Color(0xFF66728A),
                        fontSize: responsive.metaSm,
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
                  title: '白名单',
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
                  title: '黑名单',
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

class _AccessModeToggle extends StatelessWidget {
  const _AccessModeToggle({required this.activeMode, required this.onChanged});

  final AgentInvocationPolicyMode activeMode;
  final ValueChanged<AgentInvocationPolicyMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final blacklistActive = activeMode == AgentInvocationPolicyMode.blacklist;
    final enabled = onChanged != null;
    const whitelistColor = Color(0xFF0B65F8);
    const blacklistColor = Color(0xFFB42318);
    final accentColor = blacklistActive ? blacklistColor : whitelistColor;
    final nextMode = blacklistActive
        ? AgentInvocationPolicyMode.whitelist
        : AgentInvocationPolicyMode.blacklist;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '白名单',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: !blacklistActive ? whitelistColor : const Color(0xFF8A96AA),
            fontSize: responsive.metaSm,
            fontWeight: !blacklistActive ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        SizedBox(width: responsive.spacing(6)),
        AppPressable(
          key: const Key('agent-access-mode-toggle'),
          onTap: enabled ? () => onChanged!(nextMode) : null,
          enabled: enabled,
          semanticLabel: blacklistActive ? '切换到白名单模式' : '切换到黑名单模式',
          tooltip: blacklistActive ? '当前黑名单模式' : '当前白名单模式',
          borderRadius: BorderRadius.circular(99),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            width: responsive.displayScaled(46),
            height: responsive.displayScaled(24),
            padding: EdgeInsets.all(responsive.displayScaled(3)),
            decoration: BoxDecoration(
              color: enabled ? accentColor : const Color(0xFFD9E1EC),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: enabled
                    ? accentColor.withValues(alpha: 0.35)
                    : const Color(0xFFC7D0DE),
              ),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              alignment: blacklistActive
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Container(
                width: responsive.displayScaled(18),
                height: responsive.displayScaled(18),
                decoration: const BoxDecoration(
                  color: CupertinoColors.white,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Color(0x260B1220),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: responsive.spacing(6)),
        Text(
          '黑名单',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: blacklistActive ? blacklistColor : const Color(0xFF8A96AA),
            fontSize: responsive.metaSm,
            fontWeight: blacklistActive ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
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
    final accentColor = switch (mode) {
      AgentInvocationPolicyMode.whitelist => const Color(0xFF0B65F8),
      AgentInvocationPolicyMode.blacklist => const Color(0xFFB42318),
    };
    final activeBackground = switch (mode) {
      AgentInvocationPolicyMode.whitelist => const Color(0xFFF7FAFF),
      AgentInvocationPolicyMode.blacklist => const Color(0xFFFFF8F7),
    };
    final activeBorder = switch (mode) {
      AgentInvocationPolicyMode.whitelist => const Color(0xFFBFD5FF),
      AgentInvocationPolicyMode.blacklist => const Color(0xFFF3B8B4),
    };
    final statusColor = active ? accentColor : const Color(0xFF6F7C91);
    final textColor = active
        ? const Color(0xFF40506B)
        : const Color(0xFF7D8899);
    final fieldFill = enabled ? CupertinoColors.white : const Color(0xFFEFF3F8);
    final fieldBorder = enabled
        ? const Color(0xFFDDE5F1)
        : const Color(0xFFD4DCE9);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.all(responsive.spacing(12)),
      decoration: BoxDecoration(
        color: active ? activeBackground : const Color(0xFFF0F3F8),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(
          color: active ? activeBorder : const Color(0xFFD5DDE9),
        ),
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
                    color: textColor,
                    fontSize: responsive.metaSm,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: responsive.spacing(7),
                  vertical: responsive.spacing(3),
                ),
                decoration: BoxDecoration(
                  color: active
                      ? statusColor.withValues(alpha: 0.12)
                      : const Color(0xFFE0E6F0),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  active ? '已启用' : '已禁用',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: responsive.metaSm,
                    fontWeight: FontWeight.w700,
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
                  placeholder: 'bob 或 bob.example.com',
                  padding: EdgeInsets.symmetric(
                    horizontal: responsive.spacing(11),
                    vertical: responsive.spacing(9),
                  ),
                  decoration: BoxDecoration(
                    color: fieldFill,
                    borderRadius: BorderRadius.circular(responsive.radius(8)),
                    border: Border.all(color: fieldBorder),
                  ),
                  style: TextStyle(
                    color: enabled
                        ? const Color(0xFF101B32)
                        : const Color(0xFF7D8899),
                    fontSize: responsive.bodySm,
                    height: 1.2,
                  ),
                  placeholderStyle: TextStyle(
                    color: enabled
                        ? const Color(0xFF98A4B8)
                        : const Color(0xFFADB7C7),
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
              errorText!,
              style: TextStyle(
                color: AwikiMeColors.danger,
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
    return AppPressable(
      onTap: enabled ? onPressed : null,
      enabled: enabled,
      semanticLabel: '添加 Handle',
      tooltip: '添加',
      borderRadius: BorderRadius.circular(responsive.radius(8)),
      child: Container(
        width: responsive.displayScaled(42),
        height: responsive.displayScaled(38),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFF0B65F8) : const Color(0xFFE8EDF5),
          borderRadius: BorderRadius.circular(responsive.radius(8)),
        ),
        alignment: Alignment.center,
        child: Icon(
          CupertinoIcons.plus,
          color: enabled ? CupertinoColors.white : const Color(0xFF8A96AA),
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
    if (handles.isEmpty) {
      return Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: responsive.displayScaled(36)),
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: responsive.spacing(10)),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF5F8FC) : const Color(0xFFE7ECF4),
          borderRadius: BorderRadius.circular(responsive.radius(8)),
          border: Border.all(
            color: active ? const Color(0xFFE4EAF3) : const Color(0xFFD3DCE8),
          ),
        ),
        child: Text(
          '暂无 Handle',
          style: TextStyle(
            color: active ? const Color(0xFF8A96AA) : const Color(0xFF9CA7B8),
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
    return Container(
      constraints: BoxConstraints(minHeight: responsive.displayScaled(36)),
      padding: EdgeInsets.only(
        left: responsive.spacing(10),
        right: responsive.spacing(4),
      ),
      decoration: BoxDecoration(
        color: active ? CupertinoColors.white : const Color(0xFFE8EDF5),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(
          color: active ? const Color(0xFFE4EAF3) : const Color(0xFFD2DAE7),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '@$handle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active
                    ? const Color(0xFF17233A)
                    : const Color(0xFF7D8899),
                fontSize: responsive.bodySm,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          AppIconButton(
            onPressed: enabled ? onRemove : null,
            semanticLabel: '删除 Handle',
            tooltip: '删除',
            size: responsive.displayScaled(30),
            borderRadius: BorderRadius.circular(responsive.radius(7)),
            child: Icon(
              CupertinoIcons.xmark,
              color: enabled
                  ? const Color(0xFF68758D)
                  : const Color(0xFFADB7C7),
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
    final agent = widget.agent;
    final essentialRows = _essentialDiagnosticRows(agent);
    final moreRows = _expandedDiagnosticRows(agent);
    final errorText = _diagnosticErrorText(agent);
    final hasMore = moreRows.isNotEmpty;

    return Container(
      padding: EdgeInsets.all(responsive.spacing(16)),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(responsive.radius(10)),
        border: Border.all(color: const Color(0xFFE4EAF3)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F0B1220),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: responsive.displayScaled(34),
                height: responsive.displayScaled(34),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F5FF),
                  borderRadius: BorderRadius.circular(responsive.radius(9)),
                ),
                child: Icon(
                  CupertinoIcons.info_circle,
                  color: const Color(0xFF0B65F8),
                  size: responsive.iconMd,
                ),
              ),
              SizedBox(width: responsive.spacing(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '诊断信息',
                      style: TextStyle(
                        color: const Color(0xFF101B32),
                        fontSize: responsive.bodyMd,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: responsive.spacing(2)),
                    Text(
                      agent.isDaemon ? '代理运行与身份信息' : '智能体身份信息',
                      style: TextStyle(
                        color: const Color(0xFF66728A),
                        fontSize: responsive.metaSm,
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
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
    this.semanticsIdentifier,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      tooltip: label,
      enabled: onPressed != null,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(8),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: danger ? const Color(0xFFFFEBEB) : const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 17,
              color: danger ? AwikiMeColors.danger : const Color(0xFF0B65F8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: danger ? AwikiMeColors.danger : const Color(0xFF0B65F8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
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
    final retryButton = onRetry == null
        ? null
        : AppPressable(
            onTap: onRetry,
            semanticLabel: '重试',
            tooltip: '重试',
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
                '重试',
                style: TextStyle(
                  color: AwikiMeColors.danger,
                  fontSize: responsive.metaSm,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
    return AwikiMeErrorNotice(
      message: message,
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
    return Column(
      children: <Widget>[
        for (var index = 0; index < rows.length; index++) ...<Widget>[
          if (index > 0)
            Padding(
              padding: EdgeInsets.symmetric(vertical: responsive.spacing(4)),
              child: Container(height: 1, color: const Color(0xFFEFF3F8)),
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
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: responsive.spacing(compact ? 3 : 5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: responsive.displayScaled(compact ? 96 : 112),
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF66728A),
                fontSize: responsive.metaSm,
                fontWeight: FontWeight.w600,
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
                color: const Color(0xFF18243A),
                fontSize: compact ? responsive.metaSm : responsive.bodySm,
                fontWeight: FontWeight.w500,
                height: 1.28,
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
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: responsive.spacing(12),
        vertical: responsive.spacing(10),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6EA),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFFF6D7A8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: responsive.spacing(1)),
            child: Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: const Color(0xFFB26900),
              size: responsive.iconSm,
            ),
          ),
          SizedBox(width: responsive.spacing(8)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: const Color(0xFF6F4B16),
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
    return AppPressable(
      onTap: onPressed,
      semanticLabel: expanded ? '收起诊断详情' : '查看更多诊断',
      tooltip: expanded ? '收起' : '查看更多',
      borderRadius: BorderRadius.circular(responsive.radius(8)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(10),
          vertical: responsive.spacing(8),
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FC),
          borderRadius: BorderRadius.circular(responsive.radius(8)),
          border: Border.all(color: const Color(0xFFE5EAF2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              expanded ? '收起' : '查看更多',
              style: TextStyle(
                color: const Color(0xFF40506B),
                fontSize: responsive.metaSm,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: responsive.spacing(5)),
            Icon(
              expanded
                  ? CupertinoIcons.chevron_up
                  : CupertinoIcons.chevron_down,
              color: const Color(0xFF66728A),
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

List<_DiagnosticRowData> _essentialDiagnosticRows(AgentSummary agent) {
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
        label: '当前版本',
        value: _nonEmpty(agent.latest.version)!,
      ),
    if (agent.isDaemon && _nonEmpty(agent.latest.platform) != null)
      _DiagnosticRowData(label: '平台', value: _nonEmpty(agent.latest.platform)!),
  ];
}

List<_DiagnosticRowData> _expandedDiagnosticRows(AgentSummary agent) {
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
    add('最新版本', latest.latestVersion, key: 'latest_version');
    add('最低可用版本', latest.minSupportedVersion, key: 'min_supported_version');
    add('服务', latest.service, key: 'service');
    add('最近上报', latest.lastSeenAt?.toLocal().toString(), key: 'last_seen');
  }
  add('错误代码', latest.lastErrorCode, key: 'last_error_code');
  for (final entry in latest.diagnosticsSummary.entries) {
    if (!_shouldShowDiagnosticSummaryEntry(agent, entry.key, entry.value)) {
      continue;
    }
    add(_diagnosticLabel(entry.key), entry.value, key: entry.key, isLong: true);
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

String _diagnosticLabel(String key) {
  switch (key.trim().toLowerCase()) {
    case 'runner':
      return '运行器';
    case 'profile_status':
      return '配置状态';
    case 'installation_status':
      return '安装状态';
    case 'service_installed':
      return '服务安装';
    case 'config_summary':
      return '配置摘要';
    case 'hermes_profile':
      return 'Hermes 配置';
    case 'runner_status':
      return '运行状态';
    case 'active_session_count':
      return '活跃会话';
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
    return SelectionContainer.disabled(
      child: AppIconButton(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            AwikiMeToast.show(context, '已复制');
          }
        },
        semanticLabel: '复制',
        tooltip: '复制',
        size: responsive.displayScaled(28),
        padding: EdgeInsets.all(responsive.spacing(5)),
        backgroundColor: CupertinoColors.white,
        borderRadius: BorderRadius.circular(responsive.radius(7)),
        child: Icon(
          CupertinoIcons.doc_on_doc,
          color: const Color(0xFF44506A),
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
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF101B32),
        fontWeight: FontWeight.w700,
      ),
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
          fontWeight: FontWeight.w700,
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
      return const Color(0xFF66728A);
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
