part of 'agents_page.dart';

class MessageAgentSettingsPage extends ConsumerStatefulWidget {
  const MessageAgentSettingsPage({super.key, this.initialDaemonDid});

  final String? initialDaemonDid;

  @override
  ConsumerState<MessageAgentSettingsPage> createState() =>
      _MessageAgentSettingsPageState();
}

class _MessageAgentSettingsPageState
    extends ConsumerState<MessageAgentSettingsPage> {
  String? _selectedDaemonDid;

  @override
  void initState() {
    super.initState();
    _selectedDaemonDid = widget.initialDaemonDid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(ref.read(agentsProvider.notifier).ensureLoaded());
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentsProvider);
    final enabled = ref.watch(agentImEnabledProvider);
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final daemons = state.daemonAgents;
    final selectedDaemon = _selectedDaemon(state, daemons);
    final selectedDid = selectedDaemon?.agentDid;
    final messageAgent = selectedDid == null
        ? null
        : state.messageAgentRuntimeFor(selectedDid);
    final selectionLabel = selectedDaemon == null
        ? '未选择运行 Daemon'
        : '当前运行 Daemon：${localizeAgentTitle(context.l10n, selectedDaemon)}';
    final isEnablePending =
        selectedDid != null &&
        state.isActionPending(
          AgentActionKeys.bootstrapMessageAgent(selectedDid),
        );
    final isManagementPending =
        selectedDid != null &&
        (state.isActionPending(
              AgentActionKeys.pauseMessageAgent(selectedDid),
            ) ||
            state.isActionPending(
              AgentActionKeys.deleteMessageAgent(selectedDid),
            ) ||
            state.isActionPending(
              AgentActionKeys.revokeMessageAgent(selectedDid),
            ));

    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: AwikiAdaptiveScaffold(
        maxWidth: 960,
        includeBottomSafeArea: true,
        child: SafeArea(
          bottom: false,
          child: SelectionArea(
            child: ListView(
              key: const Key('message-agent-settings-page'),
              padding: EdgeInsets.fromLTRB(
                responsive.spacing(16),
                responsive.spacing(14),
                responsive.spacing(16),
                responsive.spacing(24),
              ),
              children: <Widget>[
                AwikiMeTopBar(
                  title: '消息处理 Agent',
                  padding: EdgeInsets.zero,
                  leading: TopBarActionButton(
                    onTap: () => Navigator.of(context).maybePop(),
                    semanticsLabel: '返回',
                    tooltip: '返回',
                    child: const AwikiAssetIcon(
                      assetName: 'assets/icons/icon_left.svg',
                      color: AwikiMeColors.primaryDark,
                      size: 22,
                    ),
                  ),
                ),
                SizedBox(height: responsive.spacing(16)),
                if (state.error != null) ...<Widget>[
                  _AgentErrorBanner(message: state.error!),
                  SizedBox(height: responsive.spacing(12)),
                ],
                _MessageAgentHeroCard(
                  enabled: enabled,
                  daemon: selectedDaemon,
                  messageAgent: messageAgent,
                  isEnablePending: isEnablePending,
                  isManagementPending: isManagementPending,
                  onEnable: selectedDaemon == null
                      ? null
                      : () => ref
                            .read(agentsProvider.notifier)
                            .bootstrapMessageAgent(
                              daemonDid: selectedDaemon.agentDid,
                            ),
                  onPause: selectedDaemon == null
                      ? null
                      : () => _confirmPauseMessageAgent(
                          context,
                          ref,
                          selectedDaemon,
                        ),
                  onDelete: selectedDaemon == null
                      ? null
                      : () => _confirmDeleteMessageAgent(
                          context,
                          ref,
                          selectedDaemon,
                        ),
                  onRevoke: selectedDaemon == null
                      ? null
                      : () => _confirmRevokeMessageAgentAuthorization(
                          context,
                          ref,
                          selectedDaemon,
                        ),
                  onRefresh: selectedDaemon == null
                      ? null
                      : () => ref
                            .read(agentsProvider.notifier)
                            .refreshDaemonStatus(selectedDaemon.agentDid),
                ),
                SizedBox(height: responsive.spacing(16)),
                E2eMarker(
                  selectedDid == null
                      ? 'message-agent-selected-daemon:none'
                      : 'message-agent-selected-daemon:$selectedDid',
                ),
                e2eSemantics(
                  identifier: 'message-agent-selected-daemon-label',
                  label: selectionLabel,
                  child: Text(
                    selectionLabel,
                    style: TextStyle(
                      color: const Color(0xFF66728A),
                      fontSize: responsive.metaSm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(height: responsive.spacing(8)),
                _MessageAgentDaemonSelector(
                  daemons: daemons,
                  selectedDaemonDid: selectedDaemon?.agentDid,
                  state: state,
                  onSelect: (daemonDid) => setState(() {
                    _selectedDaemonDid = daemonDid;
                  }),
                  onRefresh: (daemon) => ref
                      .read(agentsProvider.notifier)
                      .refreshDaemonStatus(daemon.agentDid),
                ),
                SizedBox(height: responsive.spacing(16)),
                _MessageAgentLimitsCard(enabled: enabled),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AgentSummary? _selectedDaemon(AgentsState state, List<AgentSummary> daemons) {
    final wanted = _selectedDaemonDid ?? widget.initialDaemonDid;
    if (wanted != null) {
      for (final daemon in daemons) {
        if (daemon.agentDid == wanted) {
          return daemon;
        }
      }
    }
    if (daemons.isNotEmpty) {
      return daemons.first;
    }
    return null;
  }
}

class _MessageAgentHeroCard extends StatelessWidget {
  const _MessageAgentHeroCard({
    required this.enabled,
    required this.daemon,
    required this.messageAgent,
    required this.isEnablePending,
    required this.isManagementPending,
    required this.onEnable,
    required this.onPause,
    required this.onDelete,
    required this.onRevoke,
    required this.onRefresh,
  });

  final bool enabled;
  final AgentSummary? daemon;
  final AgentSummary? messageAgent;
  final bool isEnablePending;
  final bool isManagementPending;
  final VoidCallback? onEnable;
  final VoidCallback? onPause;
  final VoidCallback? onDelete;
  final VoidCallback? onRevoke;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final daemon = this.daemon;
    final diagnostics =
        daemon?.latest.diagnosticsSummary ?? const <String, Object?>{};
    final hasBootstrapKey =
        daemon != null && _daemonHasBootstrapPublicKey(daemon, diagnostics);
    final daemonReady = daemon != null && _messageAgentDaemonReady(daemon);
    final messageAgent = this.messageAgent;
    final isBusy = isEnablePending || isManagementPending;
    final canEnable = enabled && daemonReady && hasBootstrapKey && !isBusy;
    final canManage = enabled && daemonReady && messageAgent != null && !isBusy;
    final stateLabel = _messageAgentStateLabel(
      enabled: enabled,
      daemon: daemon,
      hasBootstrapKey: hasBootstrapKey,
      messageAgent: messageAgent,
      isBusy: isBusy,
    );
    const provider = defaultMessageAgentRuntimeProvider;
    return AppCardSection(
      padding: EdgeInsets.all(responsive.spacing(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: responsive.displayScaled(42),
                height: responsive.displayScaled(42),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F7F4),
                  borderRadius: BorderRadius.circular(responsive.radius(12)),
                ),
                child: Icon(
                  CupertinoIcons.bubble_left_bubble_right,
                  color: const Color(0xFF1B7A43),
                  size: responsive.iconLg,
                ),
              ),
              SizedBox(width: responsive.spacing(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '消息处理 Agent',
                      style: TextStyle(
                        color: const Color(0xFF101B32),
                        fontSize: responsive.titleLg,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: responsive.spacing(4)),
                    Text(
                      enabled
                          ? '读取普通 direct text，为你整理并生成草稿；发送前必须由你确认。'
                          : '实验功能未开启，当前不会发送 bootstrap 或授权请求。',
                      style: TextStyle(
                        color: const Color(0xFF66728A),
                        fontSize: responsive.bodySm,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: responsive.spacing(10)),
              _MessageAgentStatePill(
                text: stateLabel,
                active: enabled && (messageAgent != null || hasBootstrapKey),
              ),
            ],
          ),
          SizedBox(height: responsive.spacing(16)),
          _MessageAgentFactGrid(
            rows: <_MessageAgentFact>[
              _MessageAgentFact(
                '运行 Daemon',
                daemon == null
                    ? '未选择'
                    : localizeAgentTitle(context.l10n, daemon),
              ),
              _MessageAgentFact('引擎', provider.displayLabel),
              const _MessageAgentFact('处理范围', '普通 direct text'),
              _MessageAgentFact(
                'Daemon 状态',
                daemon == null ? '无可用 Daemon' : daemon.latest.status,
              ),
              _MessageAgentFact(
                'Daemon 版本',
                daemon == null ? '未知' : _daemonRuntimeSummary(context, daemon),
              ),
              _MessageAgentFact(
                '安全 bootstrap',
                hasBootstrapKey ? '已上报公钥' : '等待刷新状态',
              ),
              _MessageAgentFact(
                '授权状态',
                messageAgent == null
                    ? '尚未绑定'
                    : '已绑定 ${messageAgent.displayName}',
              ),
            ],
          ),
          SizedBox(height: responsive.spacing(14)),
          _MessageAgentPermissionSummary(enabled: enabled),
          if (!enabled ||
              daemon == null ||
              !daemonReady ||
              !hasBootstrapKey) ...<Widget>[
            SizedBox(height: responsive.spacing(12)),
            _MessageAgentReadinessNotice(
              enabled: enabled,
              daemon: daemon,
              daemonReady: daemonReady,
              hasBootstrapKey: hasBootstrapKey,
            ),
          ],
          SizedBox(height: responsive.spacing(14)),
          Wrap(
            spacing: responsive.spacing(8),
            runSpacing: responsive.spacing(8),
            children: <Widget>[
              _ActionButton(
                icon: CupertinoIcons.check_mark_circled,
                label: isEnablePending ? '启用中' : '启用消息处理 Agent',
                semanticsIdentifier: 'message-agent-enable-action',
                onPressed: canEnable ? onEnable : null,
              ),
              _ActionButton(
                icon: CupertinoIcons.pause_circle,
                label: '暂停处理消息',
                semanticsIdentifier: 'message-agent-pause-action',
                onPressed: canManage ? onPause : null,
              ),
              _ActionButton(
                icon: CupertinoIcons.trash,
                label: '删除消息处理 Agent',
                semanticsIdentifier: 'message-agent-delete-action',
                danger: true,
                onPressed: canManage ? onDelete : null,
              ),
              _ActionButton(
                icon: CupertinoIcons.lock_slash,
                label: '撤销 Daemon 消息授权',
                semanticsIdentifier: 'message-agent-revoke-action',
                danger: true,
                onPressed: canManage ? onRevoke : null,
              ),
              _ActionButton(
                icon: CupertinoIcons.refresh,
                label: '刷新 Daemon 状态',
                semanticsIdentifier: 'message-agent-refresh-action',
                onPressed: daemon == null || isBusy ? null : onRefresh,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageAgentDaemonSelector extends StatelessWidget {
  const _MessageAgentDaemonSelector({
    required this.daemons,
    required this.selectedDaemonDid,
    required this.state,
    required this.onSelect,
    required this.onRefresh,
  });

  final List<AgentSummary> daemons;
  final String? selectedDaemonDid;
  final AgentsState state;
  final ValueChanged<String> onSelect;
  final ValueChanged<AgentSummary> onRefresh;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppCardSection(
      padding: EdgeInsets.all(responsive.spacing(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '选择运行 Daemon',
            style: TextStyle(
              color: const Color(0xFF101B32),
              fontSize: responsive.bodyMd,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: responsive.spacing(6)),
          Text(
            'Message Agent 会运行在你选择的 Daemon 内。',
            style: TextStyle(
              color: const Color(0xFF66728A),
              fontSize: responsive.bodySm,
            ),
          ),
          SizedBox(height: responsive.spacing(12)),
          if (daemons.isEmpty)
            Text(
              '暂无可用 Daemon，请先在智能体页创建或安装 Daemon。',
              style: TextStyle(
                color: const Color(0xFF66728A),
                fontSize: responsive.bodySm,
              ),
            )
          else
            Column(
              children: <Widget>[
                for (final daemon in daemons)
                  Padding(
                    padding: EdgeInsets.only(bottom: responsive.spacing(8)),
                    child: _MessageAgentDaemonOption(
                      daemon: daemon,
                      selected: daemon.agentDid == selectedDaemonDid,
                      isRefreshing: state.isStatusQueryPending(daemon.agentDid),
                      onTap: () => onSelect(daemon.agentDid),
                      onRefresh: () => onRefresh(daemon),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MessageAgentDaemonOption extends StatelessWidget {
  const _MessageAgentDaemonOption({
    required this.daemon,
    required this.selected,
    required this.isRefreshing,
    required this.onTap,
    required this.onRefresh,
  });

  final AgentSummary daemon;
  final bool selected;
  final bool isRefreshing;
  final VoidCallback onTap;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final hasBootstrapKey = _daemonHasBootstrapPublicKey(
      daemon,
      daemon.latest.diagnosticsSummary,
    );
    final status = _messageAgentDaemonReady(daemon)
        ? hasBootstrapKey
              ? 'Ready · 已上报公钥'
              : 'Ready · 等待 bootstrap 公钥'
        : '${daemon.latest.status} · 需刷新或检查 Daemon';
    return AppPressableTile(
      onTap: onTap,
      selected: selected,
      semanticLabel: '选择 ${localizeAgentTitle(context.l10n, daemon)}',
      semanticsIdentifier: 'message-agent-daemon-option:${daemon.agentDid}',
      borderRadius: BorderRadius.circular(responsive.radius(10)),
      backgroundColor: const Color(0xFFF8FAFD),
      selectedBackgroundColor: const Color(0xFFEAF2FF),
      border: Border.all(
        color: selected ? const Color(0xFF9DC2FF) : const Color(0xFFE5EAF2),
      ),
      child: Padding(
        padding: EdgeInsets.all(responsive.spacing(12)),
        child: Row(
          children: <Widget>[
            Icon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              color: selected
                  ? const Color(0xFF0B65F8)
                  : const Color(0xFF8A96AA),
              size: responsive.iconMd,
            ),
            SizedBox(width: responsive.spacing(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    localizeAgentTitle(context.l10n, daemon),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF101B32),
                      fontSize: responsive.bodySm,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(3)),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF66728A),
                      fontSize: responsive.metaSm,
                    ),
                  ),
                ],
              ),
            ),
            _DaemonRefreshIconButton(
              isLoading: isRefreshing,
              size: responsive.displayScaled(30),
              onPressed: isRefreshing ? null : onRefresh,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageAgentReadinessNotice extends StatelessWidget {
  const _MessageAgentReadinessNotice({
    required this.enabled,
    required this.daemon,
    required this.daemonReady,
    required this.hasBootstrapKey,
  });

  final bool enabled;
  final AgentSummary? daemon;
  final bool daemonReady;
  final bool hasBootstrapKey;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final text = !enabled
        ? 'AWIKI_AGENT_IM_ENABLED=false，入口只显示状态，不会发送 bootstrap、binding 或身份授权请求。'
        : daemon == null
        ? '没有可用 Daemon。请先安装并启动 Daemon。'
        : !daemonReady
        ? '当前 Daemon 未 ready，请刷新状态或检查 Daemon 运行情况。'
        : !hasBootstrapKey
        ? '运行 Daemon 尚未上报安全 bootstrap 公钥，请先刷新 Daemon 状态。'
        : '可以启用。';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.spacing(12)),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFFFFE0A6)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: const Color(0xFF7A4E00),
          fontSize: responsive.bodySm,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MessageAgentLimitsCard extends StatelessWidget {
  const _MessageAgentLimitsCard({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppCardSection(
      padding: EdgeInsets.all(responsive.spacing(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '安全边界',
            style: TextStyle(
              color: const Color(0xFF101B32),
              fontSize: responsive.bodyMd,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: responsive.spacing(10)),
          const _MessageAgentLimitRow(
            icon: CupertinoIcons.doc_text,
            text: '只读取可处理的普通 direct text；不处理 E2EE 明文（Direct / Group）。',
          ),
          const _MessageAgentLimitRow(
            icon: CupertinoIcons.pencil_outline,
            text: '只生成草稿和需要确认的 action；不会自动发送消息。',
          ),
          const _MessageAgentLimitRow(
            icon: CupertinoIcons.lock_shield,
            text: 'runtime 不持有 DID 主私钥，不直连 message-service。',
          ),
          if (!enabled)
            const _MessageAgentLimitRow(
              icon: CupertinoIcons.slash_circle,
              text: '实验功能关闭时不会触发授权、bootstrap 或 delegated key 操作。',
            ),
        ],
      ),
    );
  }
}

class _MessageAgentLimitRow extends StatelessWidget {
  const _MessageAgentLimitRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Padding(
      padding: EdgeInsets.only(bottom: responsive.spacing(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: const Color(0xFF1B7A43), size: responsive.iconSm),
          SizedBox(width: responsive.spacing(8)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: const Color(0xFF344056),
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

bool _messageAgentDaemonReady(AgentSummary daemon) {
  final status = daemon.latest.status.trim().toLowerCase();
  return status == 'ready' || status == 'needs_upgrade';
}

String _messageAgentStateLabel({
  required bool enabled,
  required AgentSummary? daemon,
  required bool hasBootstrapKey,
  required AgentSummary? messageAgent,
  required bool isBusy,
}) {
  if (!enabled) {
    return '实验功能关闭';
  }
  if (isBusy) {
    return '处理中';
  }
  if (daemon == null) {
    return '无 Daemon';
  }
  if (!_messageAgentDaemonReady(daemon)) {
    return 'Daemon 未就绪';
  }
  if (!hasBootstrapKey) {
    return '未就绪';
  }
  if (messageAgent != null) {
    return '已启用';
  }
  return '可启用';
}
