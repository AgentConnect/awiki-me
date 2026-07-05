part of '../agents_page.dart';

Future<void> _openRuntimeChat(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) {
  final title = localizeAgentTitle(context.l10n, agent);
  return openDirectConversationForDid(
    context,
    ref,
    peerDid: agent.agentDid,
    peerHandle: _agentFullHandle(ref, agent),
    peerName: title,
    avatarSeed: agent.handle ?? agent.agentDid,
  );
}

String? _agentFullHandle(WidgetRef ref, AgentSummary agent) {
  final handle = _trimLeadingAt(agent.handle);
  if (handle == null || handle.isEmpty) {
    return null;
  }
  if (handle.contains('.')) {
    return handle.toLowerCase();
  }
  final domain = ref.read(awikiEnvironmentConfigProvider).didDomain.trim();
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
  final displayName = await showAgentRenameDialog(context, agent);
  if (displayName == null) {
    return;
  }
  await ref
      .read(agentsProvider.notifier)
      .renameAgent(agentDid: agent.agentDid, displayName: displayName);
}

Future<void> _showCreateRuntimeDialog(
  BuildContext context,
  WidgetRef ref,
  AgentSummary daemon,
  List<AgentSummary> existingRuntimes,
) async {
  final result = await AppNavigator.showDialog<_RuntimeAgentCreationDraft>(
    context,
    (dialogContext) => _CreateRuntimeDialog(
      initialDisplayName: _nextRuntimeDisplayName(
        existingRuntimes,
        RuntimeAgentKind.hermes,
      ),
      handleDomain: ref.read(awikiEnvironmentConfigProvider).didDomain,
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
    if (_validateAgentHandle(context, handle) != null) {
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
        _remoteValidationError =
            context.l10n.agentCreateHandleAvailabilityPending;
        _submittedHandleError = null;
      });
    }
  }

  void _submit() {
    final kindStatus = widget.runtimeCapability.statusFor(context.l10n, _kind);
    if (!kindStatus.enabled) {
      return;
    }
    final displayName = _nameController.text.trim();
    final handle = _handleController.text.trim();
    final nameError = _validateAgentDisplayName(context, displayName);
    final handleError =
        _validateAgentHandle(context, handle) ??
        (_remoteHandleChecking
            ? context.l10n.agentCreateHandleChecking
            : null) ??
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
    final contentPadding = responsive.spacing(18);
    final handle = _handleController.text.trim();
    final displayName = _nameController.text.trim();
    final nameError =
        _submittedNameError ??
        _softValidateAgentDisplayName(context, displayName);
    final remoteError = _remoteHandleError(handle);
    final handleError =
        _submittedHandleError ??
        _softValidateAgentHandle(context, handle) ??
        remoteError;
    final kindStatus = widget.runtimeCapability.statusFor(context.l10n, _kind);
    final canSubmit =
        kindStatus.enabled &&
        _validateAgentDisplayName(context, displayName) == null &&
        _validateAgentHandle(context, handle) == null &&
        !_remoteHandleChecking &&
        remoteError == null;
    return AppDialogScaffold(
      maxWidth: 430,
      maxHeightFraction: 0.9,
      horizontalPadding: responsive.spacing(18),
      verticalPadding: responsive.spacing(22),
      borderRadius: BorderRadius.circular(responsive.radius(16)),
      avoidViewInsets: true,
      padding: EdgeInsets.all(contentPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppDialogHeader(
            title: context.l10n.agentCreateTitle,
            onClose: () => Navigator.of(context).pop(),
          ),
          SizedBox(height: responsive.spacing(14)),
          Flexible(
            child: SingleChildScrollView(
              key: const Key('agent-create-scroll-body'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                      _shouldShowRuntimeAdvancedOptions()) ...<Widget>[
                    _RuntimeOptionSelector(
                      title: context.l10n.agentCreateWorkspacePolicy,
                      value: _workspaceMode,
                      options: <_RuntimeOption>[
                        _RuntimeOption(
                          value: runtimeWorkspaceModeRouteRoot,
                          label: context.l10n.agentCreateWorkspaceRouteRoot,
                          description: context
                              .l10n
                              .agentCreateWorkspaceRouteRootDescription,
                        ),
                        _RuntimeOption(
                          value: runtimeWorkspaceModeSharedRoot,
                          label: context.l10n.agentCreateWorkspaceSharedRoot,
                          description: context
                              .l10n
                              .agentCreateWorkspaceSharedRootDescription,
                        ),
                        _RuntimeOption(
                          value: runtimeWorkspaceModeWorktreePerTask,
                          label:
                              context.l10n.agentCreateWorkspaceWorktreePerTask,
                          description: context
                              .l10n
                              .agentCreateWorkspaceWorktreePerTaskDescription,
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
                    fieldKey: const Key('agent-create-name-field'),
                    label: context.l10n.agentNameField,
                    controller: _nameController,
                    placeholder: _kind.displayLabel,
                    errorText: nameError,
                    textInputAction: TextInputAction.next,
                  ),
                  SizedBox(height: responsive.spacing(12)),
                  _AgentDialogField(
                    fieldKey: const Key('agent-create-handle-field'),
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
                    isValid: _validateAgentHandle(context, handle) == null,
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
                  label: context.l10n.commonCancel,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              SizedBox(width: responsive.spacing(10)),
              Expanded(
                child: AppPrimaryButton(
                  label: context.l10n.groupCreateAction,
                  onPressed: canSubmit ? _submit : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _remoteHandleError(String handle) {
    if (handle.isEmpty || _validateAgentHandle(context, handle) != null) {
      return null;
    }
    final availability = _previewAvailability(handle);
    if (availability == null || availability.available) {
      return null;
    }
    if (availability.reason == 'unavailable') {
      return context.l10n.agentCreateHandleUnavailableUsed;
    }
    return availability.message?.trim().isNotEmpty == true
        ? availability.message
        : context.l10n.agentCreateHandleUnavailable;
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
          context.l10n.agentCreateType,
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
          status: runtimeCapability.statusFor(
            context.l10n,
            RuntimeAgentKind.hermes,
          ),
          onTap: () => onSelected(RuntimeAgentKind.hermes),
        ),
        SizedBox(height: responsive.spacing(8)),
        _RuntimeKindTile(
          kind: RuntimeAgentKind.codex,
          selected: selected == RuntimeAgentKind.codex,
          status: runtimeCapability.statusFor(
            context.l10n,
            RuntimeAgentKind.codex,
          ),
          onTap: () => onSelected(RuntimeAgentKind.codex),
        ),
        SizedBox(height: responsive.spacing(8)),
        _RuntimeKindTile(
          kind: RuntimeAgentKind.claudeCode,
          selected: selected == RuntimeAgentKind.claudeCode,
          status: runtimeCapability.statusFor(
            context.l10n,
            RuntimeAgentKind.claudeCode,
          ),
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
                          status.reasonLabel ??
                              context.l10n.agentStatusDisabled,
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

  _RuntimeKindStatus statusFor(AppLocalizations l10n, RuntimeAgentKind kind) {
    if (kind == RuntimeAgentKind.hermes) {
      return _RuntimeKindStatus(
        enabled: true,
        description: l10n.agentCreateHermesDescription,
      );
    }
    final driverId = kind.driverId;
    if (!hasGenericCliSchema) {
      return _RuntimeKindStatus(
        enabled: false,
        description: l10n.agentCreateNeedsGenericCliCapability(
          kind.displayLabel,
        ),
        reasonLabel: l10n.agentStatusRefreshNeeded,
      );
    }
    if (driverId == null || !supportedDrivers.contains(driverId)) {
      return _RuntimeKindStatus(
        enabled: false,
        description: l10n.agentCreateUnsupportedDriver(kind.displayLabel),
        reasonLabel: l10n.agentStatusUnsupported,
      );
    }
    if (!routeSessionSupported || !nativeResumeSupported) {
      return _RuntimeKindStatus(
        enabled: false,
        description: l10n.agentCreateNeedsRouteSession(kind.displayLabel),
        reasonLabel: l10n.agentStatusNeedsUpgrade,
      );
    }
    if (!supportedWorkspaceModes.contains(runtimeWorkspaceModeRouteRoot)) {
      return _RuntimeKindStatus(
        enabled: false,
        description: l10n.agentCreateNeedsRouteWorkspace(kind.displayLabel),
        reasonLabel: l10n.agentStatusNeedsUpgrade,
      );
    }
    if (!supportedSandboxModes.contains(runtimeSandboxDangerFullAccess)) {
      return _RuntimeKindStatus(
        enabled: false,
        description: l10n.agentCreateNeedsHostAccess(kind.displayLabel),
        reasonLabel: l10n.agentStatusNeedsUpgrade,
      );
    }
    return _RuntimeKindStatus(
      enabled: true,
      description: l10n.agentCreateRequiresSignedInCli(kind.displayLabel),
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
                  context.l10n.agentCreateHostAccessTitle,
                  style: TextStyle(
                    color: const Color(0xFF17213A),
                    fontSize: responsive.bodyMd,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: responsive.spacing(3)),
                Text(
                  context.l10n.agentCreateHostAccessDescription,
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
      l10n: context.l10n,
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
            context.l10n.agentCreateHandlePreview(preview),
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
  required AppLocalizations l10n,
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
    return l10n.agentCreateHandleAvailabilityChecking;
  }
  if (availability != null) {
    if (availability.available) {
      return l10n.agentCreateHandleAvailable;
    }
    return availability.reason == 'unavailable'
        ? l10n.agentCreateHandleUnavailableUsed
        : availability.message ?? l10n.agentCreateHandleUnavailable;
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

String? _softValidateAgentDisplayName(BuildContext context, String value) {
  return value.isEmpty ? null : _validateAgentDisplayName(context, value);
}

String? _validateAgentDisplayName(BuildContext context, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return context.l10n.agentNameRequired;
  }
  if (trimmed.length > 40) {
    return context.l10n.agentNameTooLong(40);
  }
  return null;
}

String? _softValidateAgentHandle(BuildContext context, String value) {
  return value.isEmpty ? null : _validateAgentHandle(context, value);
}

String? _validateAgentHandle(BuildContext context, String value) {
  final handle = value.trim();
  if (handle.isEmpty) {
    return context.l10n.agentCreateHandleRequired;
  }
  if (handle.length > 63) {
    return context.l10n.agentCreateHandleTooLong(63);
  }
  if (!RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(handle)) {
    return context.l10n.agentCreateHandleInvalidPattern;
  }
  if (handle.contains('--')) {
    return context.l10n.agentCreateHandleNoDoubleHyphen;
  }
  return null;
}

Future<void> _confirmUpgradeDaemon(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) async {
  final confirmed = await _confirm(
    context,
    title: context.l10n.agentUpgradeTitle,
    message: context.l10n.agentUpgradeMessage,
    actionLabel: context.l10n.agentUpgrade,
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
    title: isDaemon
        ? context.l10n.agentDeleteDaemon
        : context.l10n.agentDeleteRuntime,
    message: isDaemon
        ? context.l10n.agentDeleteDaemonMessage
        : context.l10n.agentDeleteRuntimeMessage,
    actionLabel: context.l10n.commonDelete,
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
    title: context.l10n.messageAgentPauseTitle,
    message: context.l10n.messageAgentPauseMessage,
    actionLabel: context.l10n.commonPause,
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
    title: context.l10n.messageAgentDeleteTitle,
    message: context.l10n.messageAgentDeleteMessage,
    actionLabel: context.l10n.commonDelete,
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
    title: context.l10n.messageAgentRevokeTitle,
    message: context.l10n.messageAgentRevokeMessage,
    actionLabel: context.l10n.commonRevoke,
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
  final result = await AppNavigator.showDialog<bool>(
    context,
    (dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(context.l10n.commonCancel),
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
  AppNavigator.showDialog<void>(
    context,
    (context) => _InstallCommandDialog(
      command: command,
      onClose: () {
        Navigator.of(context).pop();
        ref.read(agentsProvider.notifier).clearInstallCommand();
      },
    ),
  );
}

class _InstallCommandDialog extends StatefulWidget {
  const _InstallCommandDialog({required this.command, required this.onClose});

  final InstallCommand command;
  final VoidCallback onClose;

  @override
  State<_InstallCommandDialog> createState() => _InstallCommandDialogState();
}

class _InstallCommandDialogState extends State<_InstallCommandDialog> {
  bool _cleanupExpanded = false;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final command = widget.command;
    final expiresAt = command.token.expiresAt?.toLocal();
    final isExpired =
        command.token.expiresAt != null &&
        !command.token.expiresAt!.isAfter(DateTime.now().toUtc());
    return AppDialogScaffold(
      maxWidth: 520,
      maxHeightFraction: 0.82,
      horizontalPadding: 16,
      verticalPadding: 20,
      borderRadius: BorderRadius.circular(responsive.radius(16)),
      padding: EdgeInsets.all(responsive.spacing(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppDialogHeader(
            title: context.l10n.agentInstallTitle,
            onClose: widget.onClose,
            leading: Container(
              width: responsive.displayScaled(34),
              height: responsive.displayScaled(34),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(responsive.radius(8)),
              ),
              child: Icon(
                CupertinoIcons.desktopcomputer,
                color: const Color(0xFF0B65F8),
                size: responsive.iconMd,
              ),
            ),
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
                    copyLabel: context.l10n.agentCopyInstallCommand,
                    onCopy: () async {
                      await Clipboard.setData(
                        ClipboardData(text: command.command),
                      );
                      if (context.mounted) {
                        AwikiMeToast.show(context, context.l10n.commonCopied);
                      }
                    },
                  ),
                  SizedBox(height: responsive.spacing(12)),
                  _TokenExpiryRow(isExpired: isExpired, expiresAt: expiresAt),
                  SizedBox(height: responsive.spacing(10)),
                  _CleanupHostDisclosure(
                    expanded: _cleanupExpanded,
                    command: command.cleanupCommand,
                    onToggle: () {
                      setState(() {
                        _cleanupExpanded = !_cleanupExpanded;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CleanupHostDisclosure extends StatelessWidget {
  const _CleanupHostDisclosure({
    required this.expanded,
    required this.command,
    required this.onToggle,
  });

  final bool expanded;
  final String command;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF4),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFFF4E4B8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CupertinoButton(
            key: const Key('agent-cleanup-host-toggle'),
            padding: EdgeInsets.symmetric(
              horizontal: responsive.spacing(12),
              vertical: responsive.spacing(10),
            ),
            minimumSize: Size.zero,
            onPressed: onToggle,
            child: Row(
              children: <Widget>[
                Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  color: const Color(0xFF9A6700),
                  size: responsive.iconSm,
                ),
                SizedBox(width: responsive.spacing(8)),
                Expanded(
                  child: Text(
                    context.l10n.agentCleanupHostToggle,
                    style: TextStyle(
                      color: const Color(0xFF5F4714),
                      fontSize: responsive.metaSm,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
                SizedBox(width: responsive.spacing(8)),
                Icon(
                  expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  color: const Color(0xFF7A5A12),
                  size: responsive.displayScaled(13),
                ),
              ],
            ),
          ),
          if (expanded) ...<Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                responsive.spacing(12),
                0,
                responsive.spacing(12),
                responsive.spacing(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    context.l10n.agentCleanupHostWarning,
                    key: const Key('agent-cleanup-host-warning'),
                    style: TextStyle(
                      color: const Color(0xFF73520B),
                      fontSize: responsive.metaSm,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(10)),
                  _CommandText(
                    command,
                    copyLabel: context.l10n.agentCopyCleanupCommand,
                    copyButtonKey: const Key('agent-cleanup-copy-button'),
                    textKey: const Key('agent-cleanup-command-text'),
                    scrollKey: const Key('agent-cleanup-command-scroll'),
                    rowKey: const Key('agent-cleanup-command-row'),
                    onCopy: () async {
                      await Clipboard.setData(ClipboardData(text: command));
                      if (context.mounted) {
                        AwikiMeToast.show(context, context.l10n.commonCopied);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
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
          Expanded(
            child: Text(
              context.l10n.agentInstallSupportedTypes,
              style: const TextStyle(
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
              context.l10n.agentInstallTokenExpiresAt(
                _formatTokenExpiry(expiresAt),
              ),
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

class _CommandText extends StatefulWidget {
  const _CommandText(
    this.value, {
    required this.onCopy,
    required this.copyLabel,
    this.copyButtonKey = const Key('agent-install-copy-button'),
    this.textKey = const Key('agent-install-command-text'),
    this.scrollKey = const Key('agent-install-command-scroll'),
    this.rowKey = const Key('agent-install-command-row'),
  });

  final String value;
  final VoidCallback onCopy;
  final String copyLabel;
  final Key copyButtonKey;
  final Key textKey;
  final Key scrollKey;
  final Key rowKey;

  @override
  State<_CommandText> createState() => _CommandTextState();
}

class _CommandTextState extends State<_CommandText> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _singleLineCommand(widget.value));
  }

  @override
  void didUpdateWidget(covariant _CommandText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) {
      return;
    }
    final next = _singleLineCommand(widget.value);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
      child: Row(
        key: widget.rowKey,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            key: widget.scrollKey,
            child: CupertinoTextField(
              key: widget.textKey,
              controller: _controller,
              readOnly: true,
              showCursor: false,
              maxLines: 1,
              minLines: 1,
              enableInteractiveSelection: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.text,
              textAlignVertical: TextAlignVertical.center,
              padding: EdgeInsets.symmetric(
                horizontal: responsive.displayScaled(1),
                vertical: responsive.displayScaled(6),
              ),
              decoration: null,
              style: TextStyle(
                color: const Color(0xFFE5E7EB),
                fontSize: responsive.metaSm,
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          ),
          SizedBox(width: responsive.spacing(10)),
          AppIconButton(
            key: widget.copyButtonKey,
            onPressed: widget.onCopy,
            semanticLabel: widget.copyLabel,
            tooltip: widget.copyLabel,
            size: responsive.displayScaled(34),
            backgroundColor: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(responsive.radius(8)),
            child: Icon(
              CupertinoIcons.doc_on_doc,
              color: const Color(0xFFCBD5E1),
              size: responsive.iconSm,
            ),
          ),
        ],
      ),
    );
  }
}

String _singleLineCommand(String command) =>
    command.trim().replaceAll(RegExp(r'\s+'), ' ');
