part of '../agents_page.dart';

Future<void> _openRuntimeChat(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) {
  final title = AgentDisplayName.title(agent);
  return openDirectConversationForDid(
    context,
    ref,
    peerDid: agent.agentDid,
    peerHandle: _agentFullHandle(agent),
    peerName: title,
    avatarSeed: agent.handle ?? agent.agentDid,
  );
}

String? _agentFullHandle(AgentSummary agent) {
  final handle = _trimLeadingAt(agent.handle);
  if (handle == null || handle.isEmpty) {
    return null;
  }
  if (handle.contains('.')) {
    return handle.toLowerCase();
  }
  final domain = AwikiEnvironmentConfig.fromEnvironment().didDomain.trim();
  if (domain.isEmpty) {
    return handle.toLowerCase();
  }
  return '$handle.$domain'.toLowerCase();
}

String? _trimLeadingAt(String? value) {
  var text = value?.trim();
  if (text == null) {
    return null;
  }
  while (text!.startsWith('@')) {
    text = text.substring(1).trimLeft();
  }
  return text.trim();
}

Future<void> _showRenameAgentDialog(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) async {
  final controller = TextEditingController(text: AgentDisplayName.title(agent));
  final result = await showCupertinoDialog<String>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('改名'),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: CupertinoTextField(
          key: const Key('agent-rename-field'),
          controller: controller,
          autofocus: true,
          maxLength: 40,
          placeholder: '显示名称',
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  final displayName = result?.trim();
  if (displayName == null || displayName.isEmpty || displayName.length > 40) {
    return;
  }
  await ref.read(agentsProvider.notifier).renameSelected(displayName);
}

Future<void> _showCreateRuntimeDialog(
  BuildContext context,
  WidgetRef ref,
  AgentSummary daemon,
  List<AgentSummary> existingRuntimes,
) async {
  final result = await showCupertinoDialog<_RuntimeAgentCreationDraft>(
    context: context,
    builder: (dialogContext) => _CreateRuntimeDialog(
      initialDisplayName: _nextRuntimeDisplayName(
        existingRuntimes,
        RuntimeAgentKind.hermes,
      ),
      handleDomain: AwikiEnvironmentConfig.fromEnvironment().didDomain,
      existingRuntimes: existingRuntimes,
      runtimeCapability: _RuntimeCreateCapability.fromDaemon(daemon),
      validateHandle: (handle, domain) {
        return ref
            .read(onboardingSupportServiceProvider)
            .validateHandle(handle: handle, domain: domain);
      },
    ),
  );
  if (result == null) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  await ref
      .read(agentsProvider.notifier)
      .createRuntimeAgent(
        daemon.agentDid,
        options: RuntimeAgentCreateOptions(
          kind: result.kind,
          handle: result.handle,
          displayName: result.displayName,
          workspaceMode: result.workspaceMode,
          sandbox: result.sandbox,
        ),
      );
}

class _RuntimeAgentCreationDraft {
  const _RuntimeAgentCreationDraft({
    required this.kind,
    required this.displayName,
    required this.handle,
    required this.workspaceMode,
    required this.sandbox,
  });

  final RuntimeAgentKind kind;
  final String displayName;
  final String handle;
  final String workspaceMode;
  final String sandbox;
}

class _CreateRuntimeDialog extends StatefulWidget {
  const _CreateRuntimeDialog({
    required this.initialDisplayName,
    required this.handleDomain,
    required this.existingRuntimes,
    required this.runtimeCapability,
    required this.validateHandle,
  });

  final String initialDisplayName;
  final String handleDomain;
  final List<AgentSummary> existingRuntimes;
  final _RuntimeCreateCapability runtimeCapability;
  final Future<HandleAvailability> Function(String handle, String domain)
  validateHandle;

  @override
  State<_CreateRuntimeDialog> createState() => _CreateRuntimeDialogState();
}

class _CreateRuntimeDialogState extends State<_CreateRuntimeDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _handleController;
  final FocusNode _handleFocusNode = FocusNode();
  Timer? _handleValidationDebounce;
  bool _normalizingHandle = false;
  RuntimeAgentKind _kind = RuntimeAgentKind.hermes;
  String _workspaceMode = runtimeWorkspaceModeRouteRoot;
  String _sandbox = runtimeSandboxDangerFullAccess;
  String? _submittedNameError;
  String? _submittedHandleError;
  String? _remoteHandle;
  bool _remoteHandleChecking = false;
  HandleAvailability? _remoteAvailability;
  String? _remoteValidationError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialDisplayName)
      ..addListener(_onFieldChanged);
    _handleController = TextEditingController()
      ..addListener(_normalizeHandleInput);
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_onFieldChanged)
      ..dispose();
    _handleController
      ..removeListener(_normalizeHandleInput)
      ..dispose();
    _handleValidationDebounce?.cancel();
    _handleFocusNode.dispose();
    super.dispose();
  }

  void _selectKind(RuntimeAgentKind kind) {
    if (_kind == kind) {
      return;
    }
    setState(() {
      _kind = kind;
      _nameController.text = _nextRuntimeDisplayName(
        widget.existingRuntimes,
        kind,
      );
      _workspaceMode = runtimeWorkspaceModeRouteRoot;
      _sandbox = runtimeSandboxDangerFullAccess;
    });
  }

  void _onFieldChanged() {
    if (_submittedNameError != null || _submittedHandleError != null) {
      setState(() {
        _submittedNameError = null;
        _submittedHandleError = null;
      });
      return;
    }
    setState(() {});
  }

  void _normalizeHandleInput() {
    if (_normalizingHandle) {
      return;
    }
    final normalized = _normalizeAgentHandleInput(_handleController.text);
    if (normalized != _handleController.text) {
      _normalizingHandle = true;
      _handleController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
      _normalizingHandle = false;
    }
    _onFieldChanged();
    _scheduleHandleAvailabilityCheck();
  }

  void _scheduleHandleAvailabilityCheck() {
    _handleValidationDebounce?.cancel();
    final handle = _handleController.text.trim();
    if (_validateAgentHandle(handle) != null) {
      setState(() {
        _remoteHandle = null;
        _remoteHandleChecking = false;
        _remoteAvailability = null;
        _remoteValidationError = null;
      });
      return;
    }
    setState(() {
      _remoteHandle = handle;
      _remoteHandleChecking = true;
      _remoteAvailability = null;
      _remoteValidationError = null;
    });
    _handleValidationDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _checkHandleAvailability(handle),
    );
  }

  Future<void> _checkHandleAvailability(String handle) async {
    try {
      final availability = await widget.validateHandle(
        handle,
        widget.handleDomain,
      );
      if (!mounted || _remoteHandle != handle) {
        return;
      }
      setState(() {
        _remoteHandleChecking = false;
        _remoteAvailability = availability;
        _remoteValidationError = null;
        _submittedHandleError = null;
      });
    } catch (_) {
      if (!mounted || _remoteHandle != handle) {
        return;
      }
      setState(() {
        _remoteHandleChecking = false;
        _remoteAvailability = null;
        _remoteValidationError = '暂时无法校验可用性，创建时会再次确认';
        _submittedHandleError = null;
      });
    }
  }

  void _submit() {
    final kindStatus = widget.runtimeCapability.statusFor(_kind);
    if (!kindStatus.enabled) {
      return;
    }
    final displayName = _nameController.text.trim();
    final handle = _handleController.text.trim();
    final nameError = _validateAgentDisplayName(displayName);
    final handleError =
        _validateAgentHandle(handle) ??
        (_remoteHandleChecking ? '正在校验 Handle 可用性' : null) ??
        _remoteHandleError(handle);
    if (nameError != null || handleError != null) {
      setState(() {
        _submittedNameError = nameError;
        _submittedHandleError = handleError;
      });
      if (handleError != null) {
        _handleFocusNode.requestFocus();
      }
      return;
    }
    Navigator.of(context).pop(
      _RuntimeAgentCreationDraft(
        kind: _kind,
        displayName: displayName,
        handle: handle,
        workspaceMode: _workspaceMode,
        sandbox: _sandbox,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final dialogHorizontalInset = responsive.spacing(18);
    final dialogVerticalInset = responsive.spacing(22);
    final contentPadding = responsive.spacing(18);
    final handle = _handleController.text.trim();
    final displayName = _nameController.text.trim();
    final nameError =
        _submittedNameError ?? _softValidateAgentDisplayName(displayName);
    final remoteError = _remoteHandleError(handle);
    final handleError =
        _submittedHandleError ??
        _softValidateAgentHandle(handle) ??
        remoteError;
    final kindStatus = widget.runtimeCapability.statusFor(_kind);
    final canSubmit =
        kindStatus.enabled &&
        _validateAgentDisplayName(displayName) == null &&
        _validateAgentHandle(handle) == null &&
        !_remoteHandleChecking &&
        remoteError == null;
    final maxWidth = responsive.isPhone ? double.infinity : 430.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewInsets = MediaQuery.viewInsetsOf(context);
        final verticalInset =
            dialogVerticalInset * 2 + viewInsets.top + viewInsets.bottom;
        final maxHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight - verticalInset).clamp(
                0.0,
                constraints.maxHeight,
              )
            : double.infinity;
        return CupertinoPopupSurface(
          isSurfacePainted: false,
          child: Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                dialogHorizontalInset,
                dialogVerticalInset + viewInsets.top,
                dialogHorizontalInset,
                dialogVerticalInset + viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: maxHeight.toDouble(),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: CupertinoColors.white,
                    borderRadius: BorderRadius.circular(responsive.radius(14)),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x260B1220),
                        blurRadius: 34,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(contentPadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                '创建 Agent',
                                style: TextStyle(
                                  color: const Color(0xFF101B32),
                                  fontSize: responsive.titleLg,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            AppIconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              semanticLabel: '关闭',
                              tooltip: '关闭',
                              size: responsive.displayScaled(32),
                              backgroundColor: const Color(0xFFF5F7FB),
                              borderColor: const Color(0xFFE4E9F2),
                              child: Icon(
                                CupertinoIcons.xmark,
                                color: const Color(0xFF66728A),
                                size: responsive.iconSm,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: responsive.spacing(14)),
                        Flexible(
                          child: SingleChildScrollView(
                            key: const Key('agent-create-scroll-body'),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _AgentTypeSelector(
                                  selected: _kind,
                                  runtimeCapability: widget.runtimeCapability,
                                  onSelected: _selectKind,
                                ),
                                SizedBox(height: responsive.spacing(12)),
                                if (_kind.isGenericCli &&
                                    _shouldShowRuntimeAdvancedOptions()) ...<
                                  Widget
                                >[
                                  _RuntimeOptionSelector(
                                    title: '工作目录策略',
                                    value: _workspaceMode,
                                    options: const <_RuntimeOption>[
                                      _RuntimeOption(
                                        value: runtimeWorkspaceModeRouteRoot,
                                        label: '按会话目录',
                                        description: '每个联系人、群组或线程使用独立上下文目录。',
                                      ),
                                      _RuntimeOption(
                                        value: runtimeWorkspaceModeSharedRoot,
                                        label: '共享目录',
                                        description: '该身份共用一个目录，适合手工任务。',
                                      ),
                                      _RuntimeOption(
                                        value:
                                            runtimeWorkspaceModeWorktreePerTask,
                                        label: '每次任务 worktree',
                                        description: '每次运行使用独立工作树。',
                                      ),
                                    ],
                                    onChanged: (value) {
                                      setState(() => _workspaceMode = value);
                                    },
                                  ),
                                  SizedBox(height: responsive.spacing(12)),
                                  const _RuntimePermissionSummary(),
                                  SizedBox(height: responsive.spacing(12)),
                                ],
                                _AgentDialogField(
                                  fieldKey: const Key(
                                    'agent-create-name-field',
                                  ),
                                  label: '名称',
                                  controller: _nameController,
                                  placeholder: _kind.displayLabel,
                                  errorText: nameError,
                                  textInputAction: TextInputAction.next,
                                ),
                                SizedBox(height: responsive.spacing(12)),
                                _AgentDialogField(
                                  fieldKey: const Key(
                                    'agent-create-handle-field',
                                  ),
                                  label: 'Handle',
                                  controller: _handleController,
                                  placeholder: _kind.handlePlaceholder,
                                  errorText: handleError,
                                  focusNode: _handleFocusNode,
                                  prefix: const Text('@'),
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submit(),
                                ),
                                SizedBox(height: responsive.spacing(8)),
                                _HandlePreview(
                                  handle: handle,
                                  domain: widget.handleDomain,
                                  isValid: _validateAgentHandle(handle) == null,
                                  isChecking: _remoteHandleChecking,
                                  availability: _previewAvailability(handle),
                                  fallbackMessage: _remoteValidationError,
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: responsive.spacing(18)),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _DialogSecondaryButton(
                                label: '取消',
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ),
                            SizedBox(width: responsive.spacing(10)),
                            Expanded(
                              child: AppPrimaryButton(
                                label: '创建',
                                onPressed: canSubmit ? _submit : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String? _remoteHandleError(String handle) {
    if (handle.isEmpty || _validateAgentHandle(handle) != null) {
      return null;
    }
    final availability = _previewAvailability(handle);
    if (availability == null || availability.available) {
      return null;
    }
    if (availability.reason == 'unavailable') {
      return '这个 Handle 已被使用';
    }
    return availability.message?.trim().isNotEmpty == true
        ? availability.message
        : '这个 Handle 不可使用';
  }

  HandleAvailability? _previewAvailability(String handle) {
    if (handle.isEmpty || _remoteHandle != handle) {
      return null;
    }
    return _remoteAvailability;
  }
}

bool _shouldShowRuntimeAdvancedOptions() {
  // Generic CLI runtime creation still uses the existing option model, but the
  // product UI no longer asks users to choose these advanced settings.
  return false;
}

class _AgentTypeSelector extends StatelessWidget {
  const _AgentTypeSelector({
    required this.selected,
    required this.runtimeCapability,
    required this.onSelected,
  });

  final RuntimeAgentKind selected;
  final _RuntimeCreateCapability runtimeCapability;
  final ValueChanged<RuntimeAgentKind> onSelected;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Agent 类型',
          style: TextStyle(
            color: const Color(0xFF66728A),
            fontSize: responsive.metaSm,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: responsive.spacing(6)),
        _RuntimeKindTile(
          kind: RuntimeAgentKind.hermes,
          selected: selected == RuntimeAgentKind.hermes,
          status: runtimeCapability.statusFor(RuntimeAgentKind.hermes),
          onTap: () => onSelected(RuntimeAgentKind.hermes),
        ),
        SizedBox(height: responsive.spacing(8)),
        _RuntimeKindTile(
          kind: RuntimeAgentKind.codex,
          selected: selected == RuntimeAgentKind.codex,
          status: runtimeCapability.statusFor(RuntimeAgentKind.codex),
          onTap: () => onSelected(RuntimeAgentKind.codex),
        ),
        SizedBox(height: responsive.spacing(8)),
        _RuntimeKindTile(
          kind: RuntimeAgentKind.claudeCode,
          selected: selected == RuntimeAgentKind.claudeCode,
          status: runtimeCapability.statusFor(RuntimeAgentKind.claudeCode),
          onTap: () => onSelected(RuntimeAgentKind.claudeCode),
        ),
      ],
    );
  }
}

class _RuntimeKindTile extends StatelessWidget {
  const _RuntimeKindTile({
    required this.kind,
    required this.selected,
    required this.status,
    required this.onTap,
  });

  final RuntimeAgentKind kind;
  final bool selected;
  final _RuntimeKindStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final enabled = status.enabled;
    final accent = enabled ? const Color(0xFF0B65F8) : const Color(0xFF8A96AA);
    return AppPressable(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      semanticLabel: kind.displayLabel,
      borderRadius: BorderRadius.circular(responsive.radius(10)),
      child: Container(
        padding: EdgeInsets.all(responsive.spacing(12)),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(responsive.radius(10)),
          border: Border.all(
            color: selected ? const Color(0xFFB8C8E4) : const Color(0xFFDDE5F1),
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: responsive.displayScaled(32),
              height: responsive.displayScaled(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(responsive.radius(8)),
              ),
              child: Icon(
                _runtimeKindIcon(kind),
                color: accent,
                size: responsive.iconSm,
              ),
            ),
            SizedBox(width: responsive.spacing(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          kind.displayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: enabled
                                ? const Color(0xFF17213A)
                                : const Color(0xFF66728A),
                            fontSize: responsive.bodyMd,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!enabled) ...<Widget>[
                        SizedBox(width: responsive.spacing(6)),
                        Text(
                          status.reasonLabel ?? '未启用',
                          style: TextStyle(
                            color: const Color(0xFF8A96AA),
                            fontSize: responsive.metaSm,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: responsive.spacing(3)),
                  Text(
                    status.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF66728A),
                      fontSize: responsive.metaSm,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                CupertinoIcons.check_mark_circled_solid,
                color: accent,
                size: responsive.iconMd,
              ),
          ],
        ),
      ),
    );
  }
}

IconData _runtimeKindIcon(RuntimeAgentKind kind) => switch (kind) {
  RuntimeAgentKind.hermes => CupertinoIcons.sparkles,
  RuntimeAgentKind.codex => CupertinoIcons.chevron_left_slash_chevron_right,
  RuntimeAgentKind.claudeCode => CupertinoIcons.text_bubble,
};

class _RuntimeKindStatus {
  const _RuntimeKindStatus({
    required this.enabled,
    required this.description,
    this.reasonLabel,
  });

  final bool enabled;
  final String description;
  final String? reasonLabel;
}

class _RuntimeCreateCapability {
  const _RuntimeCreateCapability({
    required this.hasGenericCliSchema,
    required this.supportedDrivers,
    required this.supportedWorkspaceModes,
    required this.supportedSandboxModes,
    required this.routeSessionSupported,
    required this.nativeResumeSupported,
  });

  factory _RuntimeCreateCapability.fromDaemon(AgentSummary daemon) {
    final diagnostics = daemon.latest.diagnosticsSummary;
    final config = _objectMap(diagnostics['config_summary']);
    final genericCli = _objectMap(config['generic_cli']);
    final schemaVersion = _intValue(genericCli['capability_schema_version']);
    return _RuntimeCreateCapability(
      hasGenericCliSchema: schemaVersion == 1,
      supportedDrivers: _stringSet(genericCli['supported_drivers']),
      supportedWorkspaceModes: _stringSet(
        genericCli['supported_workspace_modes'],
      ),
      supportedSandboxModes: _stringSet(genericCli['supported_sandbox_modes']),
      routeSessionSupported: genericCli['route_session_supported'] == true,
      nativeResumeSupported: genericCli['native_resume_supported'] == true,
    );
  }

  final bool hasGenericCliSchema;
  final Set<String> supportedDrivers;
  final Set<String> supportedWorkspaceModes;
  final Set<String> supportedSandboxModes;
  final bool routeSessionSupported;
  final bool nativeResumeSupported;

  _RuntimeKindStatus statusFor(RuntimeAgentKind kind) {
    if (kind == RuntimeAgentKind.hermes) {
      return const _RuntimeKindStatus(
        enabled: true,
        description: '内置 Hermes Runtime Agent。',
      );
    }
    final driverId = kind.driverId;
    if (!hasGenericCliSchema) {
      return _RuntimeKindStatus(
        enabled: false,
        description:
            '${kind.displayLabel} 需要 daemon 提供 generic-cli capability。',
        reasonLabel: '需刷新',
      );
    }
    if (driverId == null || !supportedDrivers.contains(driverId)) {
      return _RuntimeKindStatus(
        enabled: false,
        description: '当前 daemon 不支持 ${kind.displayLabel} driver。',
        reasonLabel: '未支持',
      );
    }
    if (!routeSessionSupported || !nativeResumeSupported) {
      return _RuntimeKindStatus(
        enabled: false,
        description:
            '${kind.displayLabel} 需要 route session 和 native resume 支持。',
        reasonLabel: '需升级',
      );
    }
    if (!supportedWorkspaceModes.contains(runtimeWorkspaceModeRouteRoot)) {
      return _RuntimeKindStatus(
        enabled: false,
        description: '${kind.displayLabel} 需要按会话目录工作模式。',
        reasonLabel: '需升级',
      );
    }
    if (!supportedSandboxModes.contains(runtimeSandboxDangerFullAccess)) {
      return _RuntimeKindStatus(
        enabled: false,
        description: '${kind.displayLabel} 需要 daemon 支持宿主机全权限模式。',
        reasonLabel: '需升级',
      );
    }
    return _RuntimeKindStatus(
      enabled: true,
      description: '需要 daemon 上已安装并登录的 ${kind.displayLabel} CLI。',
    );
  }
}

class _RuntimePermissionSummary extends StatelessWidget {
  const _RuntimePermissionSummary();

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.spacing(12)),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(responsive.radius(10)),
        border: Border.all(color: const Color(0xFFDDE5F1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: responsive.displayScaled(28),
            height: responsive.displayScaled(28),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CupertinoColors.white,
              borderRadius: BorderRadius.circular(responsive.radius(8)),
            ),
            child: Icon(
              CupertinoIcons.command,
              color: const Color(0xFF0B65F8),
              size: responsive.iconSm,
            ),
          ),
          SizedBox(width: responsive.spacing(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '宿主机全权限',
                  style: TextStyle(
                    color: const Color(0xFF17213A),
                    fontSize: responsive.bodyMd,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: responsive.spacing(3)),
                Text(
                  '可按用户指令使用本机文件、命令、工具和网络。',
                  style: TextStyle(
                    color: const Color(0xFF66728A),
                    fontSize: responsive.metaSm,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return value.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
}

Set<String> _stringSet(Object? value) {
  if (value is! List) {
    return const <String>{};
  }
  return value
      .map((item) => item?.toString().trim())
      .whereType<String>()
      .where((item) => item.isNotEmpty)
      .toSet();
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '');
}

class _RuntimeOption {
  const _RuntimeOption({
    required this.value,
    required this.label,
    required this.description,
  });

  final String value;
  final String label;
  final String description;
}

class _RuntimeOptionSelector extends StatelessWidget {
  const _RuntimeOptionSelector({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String value;
  final List<_RuntimeOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: const Color(0xFF66728A),
            fontSize: responsive.metaSm,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: responsive.spacing(6)),
        Column(
          children: <Widget>[
            for (var index = 0; index < options.length; index++) ...<Widget>[
              _RuntimeOptionTile(
                option: options[index],
                selected: value == options[index].value,
                onTap: () => onChanged(options[index].value),
              ),
              if (index != options.length - 1)
                SizedBox(height: responsive.spacing(7)),
            ],
          ],
        ),
      ],
    );
  }
}

class _RuntimeOptionTile extends StatelessWidget {
  const _RuntimeOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _RuntimeOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onTap,
      semanticLabel: option.label,
      borderRadius: BorderRadius.circular(responsive.radius(9)),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(11),
          vertical: responsive.spacing(9),
        ),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(responsive.radius(9)),
          border: Border.all(
            color: selected ? const Color(0xFFB8C8E4) : const Color(0xFFDDE5F1),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected
                  ? CupertinoIcons.largecircle_fill_circle
                  : CupertinoIcons.circle,
              color: selected
                  ? const Color(0xFF0B65F8)
                  : const Color(0xFF98A4B8),
              size: responsive.iconSm,
            ),
            SizedBox(width: responsive.spacing(9)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF17213A),
                      fontSize: responsive.bodySm,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(2)),
                  Text(
                    option.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF66728A),
                      fontSize: responsive.metaSm,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentDialogField extends StatelessWidget {
  const _AgentDialogField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.placeholder,
    this.errorText,
    this.focusNode,
    this.prefix,
    this.textInputAction,
    this.onSubmitted,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String placeholder;
  final String? errorText;
  final FocusNode? focusNode;
  final Widget? prefix;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF66728A),
            fontSize: responsive.metaSm,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: responsive.spacing(6)),
        CupertinoTextField(
          key: fieldKey,
          controller: controller,
          focusNode: focusNode,
          placeholder: placeholder,
          prefix: prefix == null
              ? null
              : Padding(
                  padding: EdgeInsets.only(left: responsive.spacing(10)),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: const Color(0xFF66728A),
                      fontSize: responsive.bodyMd,
                      fontWeight: FontWeight.w600,
                    ),
                    child: prefix!,
                  ),
                ),
          padding: EdgeInsets.symmetric(
            horizontal: responsive.spacing(12),
            vertical: responsive.spacing(11),
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFD),
            borderRadius: BorderRadius.circular(responsive.radius(9)),
            border: Border.all(
              color: hasError
                  ? const Color(0xFFE14E4E)
                  : const Color(0xFFDDE5F1),
            ),
          ),
          style: TextStyle(
            color: const Color(0xFF101B32),
            fontSize: responsive.bodyMd,
          ),
          placeholderStyle: TextStyle(
            color: const Color(0xFF98A4B8),
            fontSize: responsive.bodyMd,
          ),
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
        ),
        if (hasError) ...<Widget>[
          SizedBox(height: responsive.spacing(5)),
          Text(
            errorText!,
            style: TextStyle(
              color: const Color(0xFFE14E4E),
              fontSize: responsive.metaSm,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _HandlePreview extends StatelessWidget {
  const _HandlePreview({
    required this.handle,
    required this.domain,
    required this.isValid,
    required this.isChecking,
    this.availability,
    this.fallbackMessage,
  });

  final String handle;
  final String domain;
  final bool isValid;
  final bool isChecking;
  final HandleAvailability? availability;
  final String? fallbackMessage;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final preview = handle.isEmpty ? '@handle.$domain' : '@$handle.$domain';
    final message = _handlePreviewMessage(
      handle: handle,
      isValid: isValid,
      isChecking: isChecking,
      availability: availability,
      fallbackMessage: fallbackMessage,
    );
    final color = _handlePreviewColor(
      isValid: isValid,
      isChecking: isChecking,
      availability: availability,
      fallbackMessage: fallbackMessage,
    );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: responsive.spacing(12),
        vertical: responsive.spacing(9),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FC),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '最终 Handle：$preview',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isValid
                  ? const Color(0xFF22304A)
                  : const Color(0xFF66728A),
              fontSize: responsive.metaSm,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (message != null) ...<Widget>[
            SizedBox(height: responsive.spacing(4)),
            Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: responsive.metaSm,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String? _handlePreviewMessage({
  required String handle,
  required bool isValid,
  required bool isChecking,
  required HandleAvailability? availability,
  required String? fallbackMessage,
}) {
  if (handle.isEmpty || !isValid) {
    return null;
  }
  if (isChecking) {
    return '正在校验可用性...';
  }
  if (availability != null) {
    if (availability.available) {
      return '这个 Handle 可以使用';
    }
    return availability.reason == 'unavailable'
        ? '这个 Handle 已被使用'
        : availability.message ?? '这个 Handle 不可使用';
  }
  return fallbackMessage;
}

Color _handlePreviewColor({
  required bool isValid,
  required bool isChecking,
  required HandleAvailability? availability,
  required String? fallbackMessage,
}) {
  if (!isValid || isChecking) {
    return const Color(0xFF66728A);
  }
  if (availability?.available == true) {
    return const Color(0xFF1B7F4B);
  }
  if (availability?.available == false) {
    return const Color(0xFFE14E4E);
  }
  if (fallbackMessage != null) {
    return const Color(0xFF66728A);
  }
  return const Color(0xFF66728A);
}

class _DialogSecondaryButton extends StatelessWidget {
  const _DialogSecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(responsive.radius(9)),
      scaleOnPress: true,
      child: Container(
        constraints: BoxConstraints(minHeight: responsive.controlHeight),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FB),
          borderRadius: BorderRadius.circular(responsive.radius(9)),
          border: Border.all(color: const Color(0xFFE1E7F0)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: const Color(0xFF4B5870),
            fontSize: responsive.bodyMd,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _nextRuntimeDisplayName(
  List<AgentSummary> runtimes,
  RuntimeAgentKind kind,
) {
  final count = runtimes
      .where((runtime) => runtime.runtime?.trim().toLowerCase() == kind.runtime)
      .length;
  return '${kind.displayLabel}${count + 1}';
}

String _normalizeAgentHandleInput(String value) {
  return value.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
}

String? _softValidateAgentDisplayName(String value) {
  return value.isEmpty ? null : _validateAgentDisplayName(value);
}

String? _validateAgentDisplayName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '请输入智能体名称';
  }
  if (trimmed.length > 40) {
    return '名称最多 40 个字符';
  }
  return null;
}

String? _softValidateAgentHandle(String value) {
  return value.isEmpty ? null : _validateAgentHandle(value);
}

String? _validateAgentHandle(String value) {
  final handle = value.trim();
  if (handle.isEmpty) {
    return '请输入 Handle';
  }
  if (handle.length > 63) {
    return 'Handle 最多 63 个字符';
  }
  if (!RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(handle)) {
    return '仅支持小写字母、数字和连字符，且首尾必须是字母或数字';
  }
  if (handle.contains('--')) {
    return 'Handle 不能包含连续连字符';
  }
  return null;
}

Future<void> _showRetryRunDialog(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) async {
  final controller = TextEditingController();
  final result = await showCupertinoDialog<String>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('重试 Run'),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: CupertinoTextField(
          key: const Key('agent-retry-run-field'),
          controller: controller,
          autofocus: true,
          placeholder: 'run_id',
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('重试'),
        ),
      ],
    ),
  );
  controller.dispose();
  final runId = result?.trim();
  if (runId == null || runId.isEmpty) {
    return;
  }
  await ref.read(agentsProvider.notifier).retryRun(agent, runId);
}

Future<void> _confirmResetRuntimeSession(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) async {
  final confirmed = await _confirm(
    context,
    title: '重置 Session',
    message: '仅归档本地 session mapping，不删除聊天历史。',
    actionLabel: '重置',
  );
  if (confirmed) {
    await ref.read(agentsProvider.notifier).resetRuntimeSession(agent);
  }
}

Future<void> _confirmUpgradeDaemon(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) async {
  final confirmed = await _confirm(
    context,
    title: '升级代理',
    message: '代理会下载 latest 版本并重启服务。',
    actionLabel: '升级',
  );
  if (confirmed) {
    final started = await ref
        .read(agentsProvider.notifier)
        .upgradeDaemon(agent.agentDid);
    if (started) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showInfo(AppMessage.daemonUpgradeStarted());
    }
  }
}

Future<void> _confirmDeleteAgent(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) async {
  final isDaemon = agent.isDaemon;
  final confirmed = await _confirm(
    context,
    title: isDaemon ? '删除代理' : '删除智能体',
    message: isDaemon
        ? '删除后会停止宿主机上的代理服务，并移除它创建的智能体。本地数据会归档保留，不会继续使用。'
        : '删除后该智能体会从列表中移除。本地数据会归档保留，不会继续使用。',
    actionLabel: '删除',
    destructive: true,
  );
  if (confirmed) {
    await ref.read(agentsProvider.notifier).deleteSelected();
  }
}

Future<void> _confirmPauseMessageAgent(
  BuildContext context,
  WidgetRef ref,
  AgentSummary daemon,
) async {
  final confirmed = await _confirm(
    context,
    title: '暂停处理消息',
    message: '暂停后，消息处理 Agent 不再读取和处理新消息；runtime 和授权仍会保留，可以重新启用。',
    actionLabel: '暂停',
  );
  if (confirmed) {
    await ref
        .read(agentsProvider.notifier)
        .pauseMessageAgentForDaemon(daemon.agentDid);
  }
}

Future<void> _confirmDeleteMessageAgent(
  BuildContext context,
  WidgetRef ref,
  AgentSummary daemon,
) async {
  final confirmed = await _confirm(
    context,
    title: '删除消息处理 Agent',
    message: '删除前会先暂停消息处理，然后归档对应 runtime。Daemon 和授权不会被删除。',
    actionLabel: '删除',
    destructive: true,
  );
  if (confirmed) {
    await ref
        .read(agentsProvider.notifier)
        .deleteMessageAgentForDaemon(daemon.agentDid);
  }
}

Future<void> _confirmRevokeMessageAgentAuthorization(
  BuildContext context,
  WidgetRef ref,
  AgentSummary daemon,
) async {
  final confirmed = await _confirm(
    context,
    title: '撤销 Daemon 消息授权',
    message: '撤销需要先通过签名 DID Document 更新移除 daemon-key-1。未完成更新时会失败，不会把暂停误认为撤销成功。',
    actionLabel: '撤销授权',
    destructive: true,
  );
  if (confirmed) {
    await ref
        .read(agentsProvider.notifier)
        .revokeMessageAgentAuthorizationForDaemon(daemon.agentDid);
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  bool destructive = false,
}) async {
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: destructive,
          isDefaultAction: !destructive,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
  return result == true;
}

void _showInstallCommand(
  BuildContext context,
  WidgetRef ref,
  InstallCommand command,
) {
  showCupertinoDialog<void>(
    context: context,
    builder: (context) => _InstallCommandDialog(
      command: command,
      onClose: () {
        Navigator.of(context).pop();
        ref.read(agentsProvider.notifier).clearInstallCommand();
      },
    ),
  );
}

class _InstallCommandDialog extends StatelessWidget {
  const _InstallCommandDialog({required this.command, required this.onClose});

  final InstallCommand command;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final expiresAt = command.token.expiresAt?.toLocal();
    final isExpired =
        command.token.expiresAt != null &&
        !command.token.expiresAt!.isAfter(DateTime.now().toUtc());
    final media = MediaQuery.of(context);
    final availableWidth = media.size.width - 32;
    final maxDialogWidth = availableWidth < 520 ? availableWidth : 520.0;
    final maxDialogHeight = media.size.height * 0.82;
    return SafeArea(
      minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Center(
        child: CupertinoPopupSurface(
          isSurfacePainted: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxDialogWidth,
              maxHeight: maxDialogHeight,
            ),
            child: Padding(
              padding: EdgeInsets.all(responsive.spacing(20)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: responsive.displayScaled(34),
                        height: responsive.displayScaled(34),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(
                            responsive.radius(8),
                          ),
                        ),
                        child: Icon(
                          CupertinoIcons.desktopcomputer,
                          color: const Color(0xFF0B65F8),
                          size: responsive.iconMd,
                        ),
                      ),
                      SizedBox(width: responsive.spacing(10)),
                      Expanded(
                        child: Text(
                          '到宿主机安装代理',
                          style: TextStyle(
                            color: const Color(0xFF101B32),
                            fontSize: responsive.titleXl,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(width: responsive.spacing(8)),
                      AppIconButton(
                        onPressed: onClose,
                        semanticLabel: '关闭',
                        tooltip: '关闭',
                        size: responsive.displayScaled(30),
                        backgroundColor: const Color(0xFFF4F6FA),
                        borderRadius: BorderRadius.circular(
                          responsive.radius(8),
                        ),
                        child: Icon(
                          CupertinoIcons.xmark,
                          color: const Color(0xFF66728A),
                          size: responsive.iconSm,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: responsive.spacing(16)),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const _SupportedAgentTypeHint(),
                          SizedBox(height: responsive.spacing(12)),
                          _CommandText(
                            command.command,
                            onCopy: () async {
                              await Clipboard.setData(
                                ClipboardData(text: command.command),
                              );
                              if (context.mounted) {
                                AwikiMeToast.show(context, '已复制');
                              }
                            },
                          ),
                          SizedBox(height: responsive.spacing(12)),
                          _TokenExpiryRow(
                            isExpired: isExpired,
                            expiresAt: expiresAt,
                          ),
                        ],
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

class _SupportedAgentTypeHint extends StatelessWidget {
  const _SupportedAgentTypeHint();

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      padding: EdgeInsets.all(responsive.spacing(12)),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(responsive.radius(9)),
        border: Border.all(color: const Color(0xFFE2EAF6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            CupertinoIcons.sparkles,
            color: const Color(0xFF0B65F8),
            size: responsive.iconSm,
          ),
          SizedBox(width: responsive.spacing(8)),
          const Expanded(
            child: Text(
              '支持的 Agent 类型：Hermes。安装宿主代理后，可在 Daemon 下创建 Hermes Runtime Agent。',
              style: TextStyle(
                color: Color(0xFF4B5870),
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

class _TokenExpiryRow extends StatelessWidget {
  const _TokenExpiryRow({required this.isExpired, required this.expiresAt});

  final bool isExpired;
  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      padding: EdgeInsets.all(responsive.spacing(10)),
      decoration: BoxDecoration(
        color: isExpired ? const Color(0xFFFFF3F3) : const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(
          color: isExpired ? const Color(0xFFFFD2D2) : const Color(0xFFE2EAF6),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isExpired
                ? CupertinoIcons.exclamationmark_circle_fill
                : CupertinoIcons.clock_fill,
            color: isExpired ? AwikiMeColors.danger : const Color(0xFF66728A),
            size: responsive.iconSm,
          ),
          SizedBox(width: responsive.spacing(8)),
          Expanded(
            child: Text(
              '有效期至: ${_formatTokenExpiry(expiresAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isExpired
                    ? AwikiMeColors.danger
                    : const Color(0xFF4B5870),
                fontSize: responsive.metaSm,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTokenExpiry(DateTime? expiresAt) {
  if (expiresAt == null) {
    return '--:--';
  }
  final hour = expiresAt.hour.toString().padLeft(2, '0');
  final minute = expiresAt.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _CommandText extends StatelessWidget {
  const _CommandText(this.value, {required this.onCopy});

  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.spacing(12)),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Stack(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(right: responsive.displayScaled(46)),
            child: SelectableText(
              key: const Key('agent-install-command-text'),
              _wrapCommand(value),
              style: TextStyle(
                color: const Color(0xFFE5E7EB),
                fontSize: responsive.metaSm,
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: AppIconButton(
              key: const Key('agent-install-copy-button'),
              onPressed: onCopy,
              semanticLabel: '复制安装命令',
              tooltip: '复制安装命令',
              size: responsive.displayScaled(34),
              backgroundColor: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(responsive.radius(8)),
              child: Icon(
                CupertinoIcons.doc_on_doc,
                color: const Color(0xFFCBD5E1),
                size: responsive.iconSm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _wrapCommand(String command) {
  final normalized = command.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) {
    return normalized;
  }
  final parts = normalized.split(' ');
  final lines = <String>[];
  final buffer = StringBuffer();
  for (final part in parts) {
    final nextLength = buffer.isEmpty
        ? part.length
        : buffer.length + 1 + part.length;
    if (buffer.isNotEmpty && nextLength > 52) {
      lines.add(buffer.toString());
      buffer
        ..clear()
        ..write('  ')
        ..write(part);
    } else {
      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }
      buffer.write(part);
    }
  }
  if (buffer.isNotEmpty) {
    lines.add(buffer.toString());
  }
  return lines.join('\n');
}
