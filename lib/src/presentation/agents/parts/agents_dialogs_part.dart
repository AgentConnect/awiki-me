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
    peerHandle: _agentFullHandle(agent),
    peerName: title,
    avatarSeed: agent.handle ?? agent.agentDid,
  );
}

String? _agentFullHandle(AgentSummary agent) {
  final handle = _trimLeadingAt(agent.handle);
  if (handle == null || handle.isEmpty || !handle.contains('.')) {
    return null;
  }
  return handle.toLowerCase();
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
      daemon: daemon,
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

class _CreateRuntimeDialog extends ConsumerStatefulWidget {
  const _CreateRuntimeDialog({
    required this.daemon,
    required this.initialDisplayName,
    required this.handleDomain,
    required this.existingRuntimes,
    required this.runtimeCapability,
    required this.validateHandle,
  });

  final AgentSummary daemon;
  final String initialDisplayName;
  final String handleDomain;
  final List<AgentSummary> existingRuntimes;
  final _RuntimeCreateCapability runtimeCapability;
  final Future<HandleAvailability> Function(String handle, String domain)
  validateHandle;

  @override
  ConsumerState<_CreateRuntimeDialog> createState() =>
      _CreateRuntimeDialogState();
}

class _CreateRuntimeDialogState extends ConsumerState<_CreateRuntimeDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _handleController;
  final FocusNode _handleFocusNode = FocusNode();
  Timer? _handleValidationDebounce;
  bool _normalizingHandle = false;
  bool _hasSelection = true;
  bool _submitting = false;
  String? _createError;
  bool _initialSelectionApplied = false;
  late String _automaticName;
  Object? _openingEpoch;
  bool get _supportsInspection =>
      widget.runtimeCapability.inspectionVersion != null;
  RuntimeClientInspectionState get _inspection => _supportsInspection
      ? ref.read(runtimeClientInspectionProvider(widget.daemon.agentDid))
      : const RuntimeClientInspectionState();
  bool get _online {
    final state = ref.read(agentsProvider);
    final daemons = state.agents.where(
      (a) => a.agentDid == widget.daemon.agentDid,
    );
    return daemons.isNotEmpty && state.canCreateRuntimeAgent(daemons.first);
  }

  _RuntimeKindStatus _status(RuntimeAgentKind kind) {
    final supported = widget.runtimeCapability.statusFor(context.l10n, kind);
    if (!supported.enabled || !_supportsInspection) return supported;
    String label;
    String description;
    if (!_online) {
      label = context.l10n.agentClientOffline;
      description = context.l10n.agentClientOfflineHint;
    } else if (_inspection.loading) {
      label = context.l10n.agentClientChecking;
      description = supported.description;
    } else if (_inspection.failed ||
        widget.runtimeCapability.inspectionVersion != 1) {
      label = context.l10n.agentClientUnknown;
      description = context.l10n.agentClientRetryHint;
    } else {
      final item = _inspection.report?.clients[kind];
      if (item?.ready == true) {
        return _RuntimeKindStatus(
          enabled: true,
          reasonLabel: item!.version == null
              ? context.l10n.agentClientReady
              : '${context.l10n.agentClientReady} · ${item.version}',
          description: supported.description,
        );
      }
      label = switch (item?.status) {
        RuntimeClientInstallationStatus.missing =>
          context.l10n.agentClientMissing,
        RuntimeClientInstallationStatus.unavailable =>
          context.l10n.agentClientUnavailable,
        _ => context.l10n.agentClientUnknown,
      };
      description = switch (item?.reasonCode) {
        'not_found' => context.l10n.agentClientInstallHint,
        'not_executable' => context.l10n.agentClientPermissionHint,
        'gateway_module_missing' => context.l10n.agentClientGatewayHint,
        'custom_launcher' => context.l10n.agentClientCustomHint,
        'timeout' => context.l10n.agentClientTimeoutHint,
        'launch_failed' ||
        'version_failed' => context.l10n.agentClientLaunchHint,
        _ => context.l10n.agentClientRetryHint,
      };
    }
    return _RuntimeKindStatus(
      enabled: false,
      reasonLabel: label,
      description: description,
    );
  }

  void _detect({bool refresh = false}) {
    if (_supportsInspection &&
        widget.runtimeCapability.inspectionVersion == 1 &&
        _online) {
      unawaited(
        ref
            .read(
              runtimeClientInspectionProvider(widget.daemon.agentDid).notifier,
            )
            .inspect(refresh: refresh),
      );
    }
  }

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
    _openingEpoch = ref.read(sessionProvider).activeEpoch;
    _automaticName = widget.initialDisplayName;
    _hasSelection = !_supportsInspection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _detect();
    });
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
    if (_kind == kind && _hasSelection) {
      return;
    }
    setState(() {
      _kind = kind;
      _hasSelection = true;
      final suggested = _nextRuntimeDisplayName(widget.existingRuntimes, kind);
      if (_nameController.text == _automaticName) {
        _nameController.text = suggested;
      }
      _automaticName = suggested;
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

  Future<void> _submit() async {
    final kindStatus = _status(_kind);
    if (_submitting || !_hasSelection || !kindStatus.enabled) {
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
    if (_supportsInspection) {
      setState(() {
        _submitting = true;
        _createError = null;
      });
      try {
        final error = await ref
            .read(agentsProvider.notifier)
            .createRuntimeAgentConfirmed(
              widget.daemon.agentDid,
              options: RuntimeAgentCreateOptions(
                kind: _kind,
                handle: handle,
                displayName: displayName,
                workspaceMode: _workspaceMode,
                sandbox: _sandbox,
              ),
            );
        if (!mounted) return;
        if (error == null) {
          Navigator.of(context).pop();
          return;
        }
        if (error == 'creation_pending') {
          setState(() {
            _createError = context.l10n.agentClientCreatePending;
          });
          return;
        }
        setState(() {
          _submitting = false;
          _createError = switch (error) {
            'runtime_client_not_found' => context.l10n.agentClientInstallHint,
            'runtime_client_not_executable' =>
              context.l10n.agentClientPermissionHint,
            'runtime_client_gateway_module_missing' =>
              context.l10n.agentClientGatewayHint,
            'runtime_client_custom_launcher' =>
              context.l10n.agentClientCustomHint,
            'runtime_client_timeout' ||
            'acp_version_timeout' ||
            'acp_probe_timeout' => context.l10n.agentClientTimeoutHint,
            'acp_setup_required' => context.l10n.agentClientProtocolHint,
            'acp_question_tool_unsupported' || 'acp_version_unavailable' =>
              context.l10n.agentClientCompatibilityHint,
            _ => context.l10n.agentClientCreateFailed,
          };
        });
        _detect(refresh: true);
      } on TimeoutException {
        if (mounted) {
          setState(() {
            _createError = context.l10n.agentClientCreatePending;
          });
        }
      } on Object {
        if (mounted) {
          setState(() {
            _submitting = false;
            _createError = context.l10n.agentClientCreateFailed;
          });
        }
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
    ref.watch(agentsProvider.select((s) => s.agents));
    ref.listen(sessionProvider.select((s) => s.activeEpoch), (_, next) {
      if (next != _openingEpoch && mounted) Navigator.of(context).pop();
    });
    if (_supportsInspection) {
      final inspection = ref.watch(
        runtimeClientInspectionProvider(widget.daemon.agentDid),
      );
      if (!_initialSelectionApplied &&
          inspection.report != null &&
          !inspection.loading) {
        _initialSelectionApplied = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _hasSelection) return;
          for (final kind in AgentTypeCatalog.kinds) {
            if (_status(kind).enabled) {
              _selectKind(kind);
              break;
            }
          }
        });
      }
    }
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
    final kindStatus = _status(_kind);
    final canSubmit =
        !_submitting &&
        _hasSelection &&
        kindStatus.enabled &&
        _validateAgentDisplayName(context, displayName) == null &&
        _validateAgentHandle(context, handle) == null &&
        !_remoteHandleChecking &&
        remoteError == null;
    return AppDialogScaffold(
      maxWidth: 760,
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
                    selected: _hasSelection ? _kind : null,
                    statusFor: _status,
                    onSelected: (kind) {
                      if (!_submitting) _selectKind(kind);
                    },
                    checking: _supportsInspection && _inspection.loading,
                    showRefresh: _supportsInspection,
                    onRefresh:
                        _supportsInspection &&
                            widget.runtimeCapability.inspectionVersion == 1 &&
                            _online &&
                            !_submitting
                        ? () => _detect(refresh: true)
                        : null,
                    hint: _supportsInspection
                        ? context.l10n.agentClientHost(
                            widget.daemon.displayName,
                          )
                        : context.l10n.agentClientLegacy,
                    note: _supportsInspection
                        ? context.l10n.agentClientScope
                        : null,
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
          if (_createError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _createError!,
                style: TextStyle(
                  fontSize: responsive.metaSm,
                  color: AwikiMePalette.mutedNeutral,
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
                  label: _submitting
                      ? context.l10n.agentClientCreating
                      : context.l10n.groupCreateAction,
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
    required this.statusFor,
    required this.onSelected,
    required this.hint,
    this.note,
    this.checking = false,
    this.onRefresh,
    this.showRefresh = false,
  });

  final RuntimeAgentKind? selected;
  final _RuntimeKindStatus Function(RuntimeAgentKind) statusFor;
  final ValueChanged<RuntimeAgentKind> onSelected;
  final String hint;
  final String? note;
  final bool checking;
  final VoidCallback? onRefresh;
  final bool showRefresh;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.agentCreateType,
                style: TextStyle(
                  color: AwikiMePalette.mutedNeutral,
                  fontSize: responsive.metaSm,
                ),
              ),
            ),
            if (showRefresh || onRefresh != null || checking)
              CupertinoButton(
                key: const Key('agent-clients-refresh'),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                minimumSize: const Size(44, 44),
                onPressed: checking ? null : onRefresh,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (checking)
                      const CupertinoActivityIndicator(radius: 7)
                    else
                      const Icon(CupertinoIcons.refresh, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      checking
                          ? context.l10n.agentClientChecking
                          : context.l10n.agentClientRefresh,
                      style: TextStyle(fontSize: responsive.metaSm),
                    ),
                  ],
                ),
              ),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(bottom: responsive.spacing(10)),
          child: Text(
            hint,
            style: TextStyle(
              fontSize: responsive.metaSm,
              color: AwikiMePalette.mutedNeutral,
              height: 1.35,
            ),
          ),
        ),
        AgentTypeGrid(
          builder: (kind) => _RuntimeKindTile(
            kind: kind,
            selected: selected == kind,
            status: statusFor(kind),
            onTap: () => onSelected(kind),
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              note!,
              style: TextStyle(
                fontSize: responsive.metaSm,
                color: AwikiMePalette.mutedNeutral,
                height: 1.4,
              ),
            ),
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
    final accent = enabled
        ? AwikiMePalette.brandAccent
        : AwikiMePalette.messagePreview;
    return AppPressable(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      semanticLabel:
          '${kind.displayLabel}，${status.reasonLabel ?? status.description}',
      borderRadius: BorderRadius.circular(responsive.radius(10)),
      child: Container(
        padding: EdgeInsets.all(responsive.spacing(12)),
        decoration: BoxDecoration(
          color: selected && enabled
              ? AwikiMePalette.brandAccentSoft
              : AwikiMePalette.mist,
          borderRadius: BorderRadius.circular(responsive.radius(10)),
          border: Border.all(
            color: selected && enabled
                ? AwikiMePalette.brandAccent
                : AwikiMePalette.hairline,
          ),
        ),
        child: Row(
          children: <Widget>[
            AgentTypeIcon(kind: kind, size: 36),
            SizedBox(width: responsive.spacing(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: responsive.spacing(6),
                    runSpacing: responsive.spacing(4),
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        kind.displayLabel,
                        style: TextStyle(
                          color: enabled
                              ? AwikiMePalette.inkNeutral
                              : AwikiMePalette.mutedNeutral,
                          fontSize: responsive.bodyMd,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (status.reasonLabel != null) ...<Widget>[
                        Text(
                          status.reasonLabel ??
                              context.l10n.agentStatusDisabled,
                          style: TextStyle(
                            color: AwikiMePalette.messagePreview,
                            fontSize: responsive.metaSm,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: responsive.spacing(3)),
                  Text(
                    status.description,
                    style: TextStyle(
                      color: AwikiMePalette.mutedNeutral,
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
    this.inspectionVersion,
    required this.hasGenericCliSchema,
    required this.acpDrivers,
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
    final acp = _objectMap(config['acp']);
    final schemaVersion = _intValue(genericCli['capability_schema_version']);
    return _RuntimeCreateCapability(
      inspectionVersion: config.containsKey('runtime_client_detection')
          ? (_intValue(
                  _objectMap(
                    config['runtime_client_detection'],
                  )['schema_version'],
                ) ??
                -1)
          : null,
      hasGenericCliSchema: schemaVersion == 1,
      acpDrivers: acp['capability_schema_version'] == 1
          ? _stringSet(acp['supported_drivers'])
          : <String>{},
      supportedDrivers: _stringSet(genericCli['supported_drivers']),
      supportedWorkspaceModes: _stringSet(
        genericCli['supported_workspace_modes'],
      ),
      supportedSandboxModes: _stringSet(genericCli['supported_sandbox_modes']),
      routeSessionSupported: genericCli['route_session_supported'] == true,
      nativeResumeSupported: genericCli['native_resume_supported'] == true,
    );
  }

  final int? inspectionVersion;
  final bool hasGenericCliSchema;
  final Set<String> acpDrivers;
  final Set<String> supportedDrivers;
  final Set<String> supportedWorkspaceModes;
  final Set<String> supportedSandboxModes;
  final bool routeSessionSupported;
  final bool nativeResumeSupported;

  _RuntimeKindStatus statusFor(AppLocalizations l10n, RuntimeAgentKind kind) {
    if (kind == RuntimeAgentKind.hermes) {
      return _RuntimeKindStatus(
        enabled: true,
        description: AgentTypeCatalog.description(l10n, kind),
      );
    }
    if (kind.isAcp) {
      final supported = acpDrivers.contains(kind.driverId);
      return _RuntimeKindStatus(
        enabled: supported,
        description: supported
            ? AgentTypeCatalog.description(l10n, kind)
            : l10n.agentCreateUnsupportedDriver(kind.displayLabel),
        reasonLabel: supported ? null : l10n.agentStatusNeedsUpgrade,
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
      description: AgentTypeCatalog.description(l10n, kind),
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
        color: AwikiMePalette.mist,
        borderRadius: BorderRadius.circular(responsive.radius(10)),
        border: Border.all(color: AwikiMePalette.hairline),
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
              color: AwikiMePalette.brandAccent,
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
                    color: AwikiMePalette.inkNeutral,
                    fontSize: responsive.bodyMd,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                SizedBox(height: responsive.spacing(3)),
                Text(
                  context.l10n.agentCreateHostAccessDescription,
                  style: TextStyle(
                    color: AwikiMePalette.mutedNeutral,
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
            color: AwikiMePalette.mutedNeutral,
            fontSize: responsive.metaSm,
            fontWeight: FontWeight.w400,
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
          color: selected
              ? AwikiMePalette.brandAccentSoft
              : AwikiMePalette.mist,
          borderRadius: BorderRadius.circular(responsive.radius(9)),
          border: Border.all(
            color: selected
                ? AwikiMePalette.brandAccent
                : AwikiMePalette.hairline,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected
                  ? CupertinoIcons.largecircle_fill_circle
                  : CupertinoIcons.circle,
              color: selected
                  ? AwikiMePalette.brandAccent
                  : AwikiMePalette.messagePreview,
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
                      color: AwikiMePalette.inkNeutral,
                      fontSize: responsive.bodySm,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(2)),
                  Text(
                    option.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AwikiMePalette.mutedNeutral,
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
            color: AwikiMePalette.mutedNeutral,
            fontSize: responsive.metaSm,
            fontWeight: FontWeight.w400,
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
                      color: AwikiMePalette.mutedNeutral,
                      fontSize: responsive.bodyMd,
                      fontWeight: FontWeight.w400,
                    ),
                    child: prefix!,
                  ),
                ),
          padding: EdgeInsets.symmetric(
            horizontal: responsive.spacing(12),
            vertical: responsive.spacing(11),
          ),
          decoration: BoxDecoration(
            color: AwikiMePalette.mist,
            borderRadius: BorderRadius.circular(responsive.radius(9)),
            border: Border.all(
              color: hasError
                  ? AwikiMePalette.dangerRed
                  : AwikiMePalette.hairline,
            ),
          ),
          style: TextStyle(
            color: AwikiMePalette.inkNeutral,
            fontSize: responsive.bodyMd,
          ),
          placeholderStyle: TextStyle(
            color: AwikiMePalette.messagePreview,
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
              color: AwikiMePalette.dangerRed,
              fontSize: responsive.metaSm,
              fontWeight: FontWeight.w400,
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
        color: AwikiMePalette.mist,
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
                  ? AwikiMePalette.inkNeutral
                  : AwikiMePalette.mutedNeutral,
              fontSize: responsive.metaSm,
              fontWeight: FontWeight.w400,
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
                fontWeight: FontWeight.w400,
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
    return AwikiMePalette.mutedNeutral;
  }
  if (availability?.available == true) {
    return AwikiMePalette.successGreen;
  }
  if (availability?.available == false) {
    return AwikiMePalette.dangerRed;
  }
  if (fallbackMessage != null) {
    return AwikiMePalette.mutedNeutral;
  }
  return AwikiMePalette.mutedNeutral;
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
          color: AwikiMePalette.mist,
          borderRadius: BorderRadius.circular(responsive.radius(9)),
          border: Border.all(color: AwikiMePalette.hairline),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: AwikiMePalette.mutedNeutral,
            fontSize: responsive.bodyMd,
            fontWeight: FontWeight.w400,
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
  final deleteAction = ref.read(agentsProvider).deleteActionForAgent(agent);
  final isAccountRemoval = deleteAction == AgentDeleteAction.removeFromAccount;
  final confirmed = await _confirm(
    context,
    title: isAccountRemoval
        ? context.l10n.agentRemoveFromAccount
        : isDaemon
        ? context.l10n.agentDeleteDaemon
        : context.l10n.agentDeleteRuntime,
    message: isAccountRemoval
        ? (isDaemon
              ? context.l10n.agentRemoveDaemonFromAccountMessage
              : context.l10n.agentRemoveRuntimeFromAccountMessage)
        : isDaemon
        ? context.l10n.agentDeleteDaemonMessage
        : context.l10n.agentDeleteRuntimeMessage,
    actionLabel: isAccountRemoval
        ? context.l10n.commonRemove
        : context.l10n.commonDelete,
    destructive: true,
  );
  if (confirmed) {
    await ref.read(agentsProvider.notifier).deleteSelected();
  }
}

Future<void> _confirmPausePersonalAgent(
  BuildContext context,
  WidgetRef ref,
  AgentSummary daemon,
) async {
  final confirmed = await _confirm(
    context,
    title: context.l10n.personalAgentPauseTitle,
    message: context.l10n.personalAgentPauseMessage,
    actionLabel: context.l10n.commonPause,
  );
  if (confirmed) {
    await ref
        .read(agentsProvider.notifier)
        .pausePersonalAgentForDaemon(daemon.agentDid);
  }
}

Future<void> _confirmDeletePersonalAgent(
  BuildContext context,
  WidgetRef ref,
  AgentSummary daemon,
) async {
  final confirmed = await _confirm(
    context,
    title: context.l10n.personalAgentDeleteTitle,
    message: context.l10n.personalAgentDeleteMessage,
    actionLabel: context.l10n.commonDelete,
    destructive: true,
  );
  if (confirmed) {
    await ref
        .read(agentsProvider.notifier)
        .deletePersonalAgentForDaemon(daemon.agentDid);
  }
}

Future<void> _confirmRevokePersonalAgentAuthorization(
  BuildContext context,
  WidgetRef ref,
  AgentSummary daemon,
) async {
  final confirmed = await _confirm(
    context,
    title: context.l10n.personalAgentRevokeTitle,
    message: context.l10n.personalAgentRevokeMessage,
    actionLabel: context.l10n.commonRevoke,
    destructive: true,
  );
  if (confirmed) {
    await ref
        .read(agentsProvider.notifier)
        .revokePersonalAgentAuthorizationForDaemon(daemon.agentDid);
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
    (dialogContext) => AppConfirmationDialog(
      title: title,
      message: message,
      confirmLabel: actionLabel,
      destructive: destructive,
      onCancel: () => Navigator.of(dialogContext).pop(false),
      onConfirm: () => Navigator.of(dialogContext).pop(true),
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

Future<void> _showSkillOnboardingDialog(BuildContext context, WidgetRef ref) {
  return AppNavigator.showDialog<void>(
    context,
    (context) =>
        _SkillOnboardingDialog(onClose: () => Navigator.of(context).pop()),
  );
}

class _SkillOnboardingDialog extends ConsumerStatefulWidget {
  const _SkillOnboardingDialog({required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<_SkillOnboardingDialog> createState() =>
      _SkillOnboardingDialogState();
}

class _SkillOnboardingDialogState
    extends ConsumerState<_SkillOnboardingDialog> {
  late final TextEditingController _displayNameController;
  bool _initializedName = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedName) {
      _displayNameController.text = context.l10n.agentSkillDefaultDisplayName;
      _initializedName = true;
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final state = ref.watch(skillOnboardingProvider);
    final instruction = state.instruction;
    return AppDialogScaffold(
      maxWidth: 560,
      maxHeightFraction: 0.84,
      horizontalPadding: 16,
      verticalPadding: 20,
      borderRadius: BorderRadius.circular(responsive.radius(16)),
      padding: EdgeInsets.all(responsive.spacing(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppDialogHeader(
            title: context.l10n.agentSkillInstallTitle,
            onClose: widget.onClose,
            leading: Container(
              width: responsive.displayScaled(34),
              height: responsive.displayScaled(34),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(responsive.radius(8)),
              ),
              child: Icon(
                CupertinoIcons.command,
                color: const Color(0xFF0B65F8),
                size: responsive.iconMd,
              ),
            ),
          ),
          SizedBox(height: responsive.spacing(16)),
          Text(
            context.l10n.agentSkillDisplayName,
            style: TextStyle(
              color: const Color(0xFF66728A),
              fontSize: responsive.metaSm,
              fontWeight: FontWeight.w400,
            ),
          ),
          SizedBox(height: responsive.spacing(6)),
          CupertinoTextField(
            key: const Key('agent-skill-display-name-field'),
            controller: _displayNameController,
            enabled: !state.isLoading,
            maxLength: 40,
            placeholder: context.l10n.agentSkillDefaultDisplayName,
            padding: EdgeInsets.symmetric(
              horizontal: responsive.spacing(12),
              vertical: responsive.spacing(10),
            ),
          ),
          SizedBox(height: responsive.spacing(6)),
          Text(
            context.l10n.agentSkillDisplayNameHint,
            style: TextStyle(
              color: const Color(0xFF66728A),
              fontSize: responsive.metaSm,
            ),
          ),
          SizedBox(height: responsive.spacing(14)),
          if (state.isLoading)
            const Center(child: CupertinoActivityIndicator())
          else if (instruction == null)
            Text(
              state.error == null
                  ? context.l10n.agentSkillReadyToGenerate
                  : _skillOnboardingErrorText(context, state.error!),
              key: Key(
                state.error == null
                    ? 'agent-skill-ready-to-generate'
                    : 'agent-skill-expired',
              ),
              style: TextStyle(
                color: state.error == null
                    ? const Color(0xFF66728A)
                    : AwikiMeColors.danger,
                fontSize: responsive.bodySm,
                fontWeight: FontWeight.w400,
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _SkillGrantLine(
                      label: context.l10n.agentSkillControllerHandle,
                      value: instruction.controllerHandle,
                    ),
                    SizedBox(height: responsive.spacing(8)),
                    _SkillGrantLine(
                      label: context.l10n.agentSkillAgentHandle,
                      value: instruction.agentHandle,
                    ),
                    SizedBox(height: responsive.spacing(8)),
                    _TokenExpiryRow(
                      isExpired: instruction.isExpired(DateTime.now()),
                      expiresAt: instruction.expiresAt.toLocal(),
                    ),
                    SizedBox(height: responsive.spacing(12)),
                    Text(
                      context.l10n.agentSkillSecretNotice,
                      style: TextStyle(
                        color: const Color(0xFF66728A),
                        fontSize: responsive.metaSm,
                        height: 1.35,
                      ),
                    ),
                    SizedBox(height: responsive.spacing(10)),
                    _SkillPromptText(instruction: instruction),
                  ],
                ),
              ),
            ),
          if (instruction != null) ...<Widget>[
            SizedBox(height: responsive.spacing(14)),
            CupertinoButton.filled(
              key: const Key('agent-skill-copy-button'),
              onPressed: () =>
                  _copySkillOnboardingInstruction(context, instruction.prompt),
              padding: EdgeInsets.symmetric(vertical: responsive.spacing(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(CupertinoIcons.doc_on_doc),
                  SizedBox(width: responsive.spacing(8)),
                  Flexible(child: Text(context.l10n.agentSkillCopyInstruction)),
                ],
              ),
            ),
          ],
          SizedBox(height: responsive.spacing(14)),
          CupertinoButton(
            key: const Key('agent-skill-regenerate-button'),
            onPressed: state.isLoading
                ? null
                : () => ref
                      .read(skillOnboardingProvider.notifier)
                      .generate(displayName: _displayNameController.text),
            padding: EdgeInsets.symmetric(vertical: responsive.spacing(10)),
            child: Text(
              instruction == null
                  ? context.l10n.agentSkillGenerate
                  : context.l10n.agentSkillRegenerate,
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillGrantLine extends StatelessWidget {
  const _SkillGrantLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Row(
      children: <Widget>[
        SizedBox(
          width: responsive.displayScaled(126),
          child: Text(
            label,
            style: TextStyle(
              color: const Color(0xFF66728A),
              fontSize: responsive.metaSm,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFF25324A),
              fontSize: responsive.bodySm,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _SkillPromptText extends StatelessWidget {
  const _SkillPromptText({required this.instruction});

  final SkillOnboardingInstruction instruction;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      padding: EdgeInsets.all(responsive.spacing(12)),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: responsive.displayScaled(130),
              maxHeight: responsive.displayScaled(210),
            ),
            child: SingleChildScrollView(
              child: SelectionArea(
                child: Text(
                  instruction.prompt,
                  key: const Key('agent-skill-instruction-text'),
                  style: TextStyle(
                    color: const Color(0xFFE5E7EB),
                    fontSize: responsive.metaSm,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _copySkillOnboardingInstruction(
  BuildContext context,
  String prompt,
) async {
  await Clipboard.setData(ClipboardData(text: prompt));
  if (context.mounted) {
    AwikiMeToast.show(context, context.l10n.commonCopied);
  }
}

String _skillOnboardingErrorText(
  BuildContext context,
  SkillOnboardingError error,
) {
  return switch (error) {
    SkillOnboardingError.loginRequired => context.l10n.agentErrorLoginRequired,
    SkillOnboardingError.handleRequired =>
      context.l10n.agentErrorHandleUnavailable,
    SkillOnboardingError.invalidDisplayName =>
      context.l10n.agentSkillInvalidDisplayName,
    SkillOnboardingError.activeTokenLimit =>
      context.l10n.agentSkillActiveTokenLimit,
    SkillOnboardingError.rateLimited => context.l10n.agentSkillRateLimited,
    SkillOnboardingError.serverUpgradeRequired =>
      context.l10n.agentSkillServerUpgradeRequired,
    SkillOnboardingError.unsupportedTenant =>
      context.l10n.agentSkillUnsupportedTenant,
    SkillOnboardingError.invalidResponse =>
      context.l10n.agentSkillInvalidResponse,
    SkillOnboardingError.requestFailed => context.l10n.agentSkillRequestFailed,
  };
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
                color: AwikiMePalette.brandAccentSoft,
                borderRadius: BorderRadius.circular(responsive.radius(8)),
              ),
              child: Icon(
                CupertinoIcons.desktopcomputer,
                color: AwikiMePalette.brandAccent,
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
                      fontWeight: FontWeight.w400,
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
                      fontWeight: FontWeight.w400,
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
        color: AwikiMePalette.mist,
        borderRadius: BorderRadius.circular(responsive.radius(9)),
        border: Border.all(color: AwikiMePalette.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            CupertinoIcons.sparkles,
            color: AwikiMePalette.brandAccent,
            size: responsive.iconSm,
          ),
          SizedBox(width: responsive.spacing(8)),
          Expanded(
            child: Text(
              context.l10n.agentInstallSupportedTypes(
                AgentTypeCatalog.names(context.l10n),
              ),
              style: const TextStyle(
                color: AwikiMePalette.mutedNeutral,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w400,
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
        color: isExpired ? const Color(0xFFFFF3F3) : AwikiMePalette.mist,
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(
          color: isExpired ? const Color(0xFFFFD2D2) : AwikiMePalette.hairline,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isExpired
                ? CupertinoIcons.exclamationmark_circle_fill
                : CupertinoIcons.clock_fill,
            color: isExpired
                ? AwikiMeColors.danger
                : AwikiMePalette.mutedNeutral,
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
                    : AwikiMePalette.mutedNeutral,
                fontSize: responsive.metaSm,
                fontWeight: FontWeight.w400,
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
