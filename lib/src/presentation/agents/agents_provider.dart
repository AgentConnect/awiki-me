import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/config/awiki_environment_config.dart';
import '../../application/models/product_local_models.dart';
import '../../core/app_error_classifier.dart';
import '../../core/performance_logger.dart';
import '../../data/agent/user_service_agent_inventory_adapter.dart';
import '../../data/services/awiki_onboarding_utility_client.dart';
import '../../domain/entities/agent/agent_bootstrap.dart';
import '../../domain/entities/agent/agent_command.dart';
import '../../domain/entities/agent/agent_control_payloads.dart';
import '../../domain/entities/agent/agent_invocation_policy.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/agent/agent_status.dart';
import '../../domain/entities/agent/install_command.dart';
import '../../domain/entities/agent/message_agent_runtime_provider.dart';
import '../../domain/entities/session_identity.dart';
import '../app_shell/providers/session_provider.dart';
import 'agent_display_name.dart';

const agentStatusQueryTimeout = Duration(seconds: 10);
const agentRuntimeCreationTimeout = Duration(seconds: 45);
const agentStatusRefreshMinimumIndicatorDuration = Duration(milliseconds: 1500);
const agentDaemonUpgradeAckTimeout = Duration(seconds: 20);
const agentDaemonUpgradeCancelAckTimeout = Duration(seconds: 12);
const agentListLoadTimeout = Duration(seconds: 15);
const agentLocalCacheReadTimeout = Duration(milliseconds: 1200);
const agentLocalCacheWriteTimeout = Duration(milliseconds: 2500);
const agentStatusRequestSendTimeout = Duration(seconds: 8);
const agentActionTimeout = Duration(seconds: 15);
const agentMessageAgentBootstrapActionTimeout = Duration(seconds: 105);
const agentStatusQueryPollInterval = Duration(milliseconds: 700);
const agentStatusQueryPollAttempts = 18;
const agentStatusPayloadLookupTimeout = Duration(milliseconds: 1200);
const agentDeletionRefreshAttempts = 4;
const agentDeletionRefreshDelay = Duration(seconds: 2);

final class AgentActionKeys {
  const AgentActionKeys._();

  static const installCommand = 'install-command';

  static String createRuntime(String daemonDid) => 'create-runtime:$daemonDid';

  static String bootstrapMessageAgent(String daemonDid) =>
      'message-agent-bootstrap:$daemonDid';

  static String pauseMessageAgent(String daemonDid) =>
      'message-agent-pause:$daemonDid';

  static String deleteMessageAgent(String daemonDid) =>
      'message-agent-delete:$daemonDid';

  static String revokeMessageAgent(String daemonDid) =>
      'message-agent-revoke:$daemonDid';

  static String resetRuntime(String runtimeDid) => 'runtime-reset:$runtimeDid';

  static String retryRun(String runtimeDid) => 'runtime-retry:$runtimeDid';

  static String rename(String agentDid) => 'rename:$agentDid';

  static String delete(String agentDid) => 'delete:$agentDid';

  static String upgradeDaemon(String daemonDid) => 'daemon-upgrade:$daemonDid';

  static String unbind(String agentDid) => 'unbind:$agentDid';
}

enum PendingRuntimeCreationState { creating, waitingForStatus }

class PendingRuntimeCreation {
  const PendingRuntimeCreation({
    required this.requestId,
    required this.daemonAgentDid,
    required this.handle,
    required this.displayName,
    required this.runtime,
    required this.createdAt,
    this.state = PendingRuntimeCreationState.creating,
  });

  final String requestId;
  final String daemonAgentDid;
  final String handle;
  final String displayName;
  final String runtime;
  final DateTime createdAt;
  final PendingRuntimeCreationState state;

  bool get isWaitingForStatus =>
      state == PendingRuntimeCreationState.waitingForStatus;

  PendingRuntimeCreation copyWith({PendingRuntimeCreationState? state}) {
    return PendingRuntimeCreation(
      requestId: requestId,
      daemonAgentDid: daemonAgentDid,
      handle: handle,
      displayName: displayName,
      runtime: runtime,
      createdAt: createdAt,
      state: state ?? this.state,
    );
  }
}

class DaemonUpgradeProgress {
  const DaemonUpgradeProgress({
    required this.stage,
    required this.message,
    this.targetVersion,
    this.sourceUrl,
    this.route,
    this.attempt,
    this.sourceIndex,
    this.sourceCount,
    this.downloadedBytes,
    this.totalBytes,
    this.percent,
    this.speedBytesPerSecond,
  });

  final String stage;
  final String message;
  final String? targetVersion;
  final String? sourceUrl;
  final String? route;
  final int? attempt;
  final int? sourceIndex;
  final int? sourceCount;
  final int? downloadedBytes;
  final int? totalBytes;
  final double? percent;
  final int? speedBytesPerSecond;

  String get displayMessage {
    final text = message.trim();
    if (text.isNotEmpty) {
      return text;
    }
    return switch (stage) {
      'manifest' => '正在获取版本信息',
      'selecting_source' => '正在选择下载线路',
      'downloading' => '正在下载安装包',
      'retrying_source' => '下载中断，正在重试',
      'verifying' => '正在校验安装包',
      'extracting' => '正在解压安装包',
      'installing' => '正在安装新版本',
      'restarting' => '正在重启代理服务',
      _ => '正在升级',
    };
  }

  String get compactLabel {
    final p = percent;
    if (p != null && p > 0 && p < 100) {
      return '$displayMessage ${p.round()}%';
    }
    if (p != null && p >= 100) {
      return '$displayMessage 100%';
    }
    return displayMessage;
  }

  bool get hasDownloadDetail {
    return downloadedBytes != null ||
        totalBytes != null ||
        speedBytesPerSecond != null ||
        sourceUrl != null ||
        route != null;
  }

  static DaemonUpgradeProgress started() {
    return const DaemonUpgradeProgress(stage: 'requested', message: '正在发送升级请求');
  }

  static DaemonUpgradeProgress waitingForDaemonConfirmation() {
    return const DaemonUpgradeProgress(
      stage: 'waiting_for_daemon',
      message: '升级请求已发送，正在等待代理确认',
    );
  }

  static DaemonUpgradeProgress? fromPayload(Map<String, Object?> payload) {
    final progress = _readMap(payload['progress']);
    if (progress.isEmpty) {
      return null;
    }
    final stage = _string(progress['stage']) ?? 'upgrading';
    final message = _string(progress['message']) ?? '';
    return DaemonUpgradeProgress(
      stage: stage,
      message: message,
      targetVersion: _string(progress['target_version']),
      sourceUrl: _string(progress['source_url']),
      route: _string(progress['route']),
      attempt: _int(progress['attempt']),
      sourceIndex: _int(progress['source_index']),
      sourceCount: _int(progress['source_count']),
      downloadedBytes: _int(progress['downloaded_bytes']),
      totalBytes: _int(progress['total_bytes']),
      percent: _double(progress['percent']),
      speedBytesPerSecond: _int(progress['speed_bytes_per_sec']),
    );
  }
}

class PendingDaemonUpgrade {
  const PendingDaemonUpgrade({
    required this.commandId,
    required this.requestedAt,
    this.acknowledged = false,
  });

  final String commandId;
  final DateTime requestedAt;
  final bool acknowledged;

  PendingDaemonUpgrade acknowledge() {
    if (acknowledged) {
      return this;
    }
    return PendingDaemonUpgrade(
      commandId: commandId,
      requestedAt: requestedAt,
      acknowledged: true,
    );
  }
}

class PendingDaemonUpgradeCancel {
  const PendingDaemonUpgradeCancel({
    required this.commandId,
    this.upgradeCommandId,
  });

  final String commandId;
  final String? upgradeCommandId;
}

final agentImEnabledProvider = Provider<bool>(
  (ref) => AwikiEnvironmentConfig.fromEnvironment().agentImEnabled,
);

class AgentsState {
  const AgentsState({
    this.agents = const <AgentSummary>[],
    this.selectedAgentDid,
    this.isLoading = false,
    this.pendingActionKeys = const <String>{},
    this.installCommand,
    this.error,
    this.pendingStatusQueryAtByDaemon = const <String, DateTime>{},
    this.pendingDaemonUpgrades = const <String, PendingDaemonUpgrade>{},
    this.cancellingDaemonUpgrades =
        const <String, PendingDaemonUpgradeCancel>{},
    this.seenControlEventIds = const <String>{},
    this.invocationPolicies = const <String, AgentInvocationPolicy>{},
    this.loadingInvocationPolicies = const <String>{},
    this.savingInvocationPolicies = const <String>{},
    this.invocationPolicyErrors = const <String, String>{},
    this.statusQueryErrors = const <String, String>{},
    this.debugLastError,
    this.daemonUpgradeErrors = const <String, String>{},
    this.daemonUpgradeProgress = const <String, DaemonUpgradeProgress>{},
    this.pendingRuntimeCreations = const <PendingRuntimeCreation>[],
    this.pendingDeletionAgentDids = const <String>{},
  });

  final List<AgentSummary> agents;
  final String? selectedAgentDid;
  final bool isLoading;
  final Set<String> pendingActionKeys;
  final InstallCommand? installCommand;
  final String? error;
  final Map<String, DateTime> pendingStatusQueryAtByDaemon;
  final Map<String, PendingDaemonUpgrade> pendingDaemonUpgrades;
  final Map<String, PendingDaemonUpgradeCancel> cancellingDaemonUpgrades;
  final Set<String> seenControlEventIds;
  final Map<String, AgentInvocationPolicy> invocationPolicies;
  final Set<String> loadingInvocationPolicies;
  final Set<String> savingInvocationPolicies;
  final Map<String, String> invocationPolicyErrors;
  final Map<String, String> statusQueryErrors;
  final String? debugLastError;
  final Map<String, String> daemonUpgradeErrors;
  final Map<String, DaemonUpgradeProgress> daemonUpgradeProgress;
  final List<PendingRuntimeCreation> pendingRuntimeCreations;
  final Set<String> pendingDeletionAgentDids;

  AgentSummary? get selectedAgent {
    final selectedDid = selectedAgentDid;
    if (selectedDid == null) {
      return agents.isEmpty ? null : agents.first;
    }
    for (final agent in agents) {
      if (agent.agentDid == selectedDid) {
        return agent;
      }
    }
    return agents.isEmpty ? null : agents.first;
  }

  bool get isActing => pendingActionKeys.isNotEmpty;

  bool isActionPending(String actionKey) {
    return pendingActionKeys.contains(actionKey);
  }

  List<AgentSummary> get daemonAgents =>
      agents.where((agent) => agent.isDaemon).toList();

  List<AgentSummary> runtimesFor(String daemonDid) => agents
      .where((agent) => agent.isRuntime && agent.daemonAgentDid == daemonDid)
      .toList();

  AgentSummary? messageAgentRuntimeFor(String daemonDid) {
    for (final runtime in runtimesFor(daemonDid)) {
      if (_isMessageAgentRuntime(runtime)) {
        return runtime;
      }
    }
    return null;
  }

  List<PendingRuntimeCreation> pendingRuntimeCreationsFor(String daemonDid) =>
      pendingRuntimeCreations
          .where((item) => item.daemonAgentDid == daemonDid)
          .toList();

  AgentSummary? daemonForRuntime(AgentSummary runtime) {
    final daemonDid = runtime.daemonAgentDid;
    if (daemonDid == null) {
      return null;
    }
    for (final agent in agents) {
      if (agent.agentDid == daemonDid && agent.isDaemon) {
        return agent;
      }
    }
    return null;
  }

  bool canDeleteAgent(AgentSummary agent) {
    if (_canUnbindUnfinishedDaemonInstall(agent)) {
      return true;
    }
    final daemon = agent.isDaemon ? agent : daemonForRuntime(agent);
    return daemon != null && _daemonAcceptsControlCommands(daemon);
  }

  bool isStatusQueryPending(String daemonDid) {
    return pendingStatusQueryAtByDaemon.containsKey(daemonDid);
  }

  bool isDaemonUpgradePending(String daemonDid) {
    return pendingDaemonUpgrades.containsKey(daemonDid);
  }

  bool isDaemonUpgradeCancelling(String daemonDid) {
    return cancellingDaemonUpgrades.containsKey(daemonDid);
  }

  bool isDeletingAgent(String agentDid) {
    return pendingDeletionAgentDids.contains(agentDid);
  }

  AgentsState copyWith({
    List<AgentSummary>? agents,
    String? selectedAgentDid,
    bool clearSelection = false,
    bool? isLoading,
    Set<String>? pendingActionKeys,
    InstallCommand? installCommand,
    bool clearInstallCommand = false,
    String? error,
    bool clearError = false,
    Map<String, DateTime>? pendingStatusQueryAtByDaemon,
    Map<String, PendingDaemonUpgrade>? pendingDaemonUpgrades,
    Map<String, PendingDaemonUpgradeCancel>? cancellingDaemonUpgrades,
    Set<String>? seenControlEventIds,
    Map<String, AgentInvocationPolicy>? invocationPolicies,
    Set<String>? loadingInvocationPolicies,
    Set<String>? savingInvocationPolicies,
    Map<String, String>? invocationPolicyErrors,
    Map<String, String>? statusQueryErrors,
    String? debugLastError,
    Map<String, String>? daemonUpgradeErrors,
    Map<String, DaemonUpgradeProgress>? daemonUpgradeProgress,
    List<PendingRuntimeCreation>? pendingRuntimeCreations,
    Set<String>? pendingDeletionAgentDids,
  }) {
    return AgentsState(
      agents: agents ?? this.agents,
      selectedAgentDid: clearSelection
          ? null
          : (selectedAgentDid ?? this.selectedAgentDid),
      isLoading: isLoading ?? this.isLoading,
      pendingActionKeys: pendingActionKeys ?? this.pendingActionKeys,
      installCommand: clearInstallCommand
          ? null
          : (installCommand ?? this.installCommand),
      error: clearError ? null : (error ?? this.error),
      pendingStatusQueryAtByDaemon:
          pendingStatusQueryAtByDaemon ?? this.pendingStatusQueryAtByDaemon,
      pendingDaemonUpgrades:
          pendingDaemonUpgrades ?? this.pendingDaemonUpgrades,
      cancellingDaemonUpgrades:
          cancellingDaemonUpgrades ?? this.cancellingDaemonUpgrades,
      seenControlEventIds: seenControlEventIds ?? this.seenControlEventIds,
      invocationPolicies: invocationPolicies ?? this.invocationPolicies,
      loadingInvocationPolicies:
          loadingInvocationPolicies ?? this.loadingInvocationPolicies,
      savingInvocationPolicies:
          savingInvocationPolicies ?? this.savingInvocationPolicies,
      invocationPolicyErrors:
          invocationPolicyErrors ?? this.invocationPolicyErrors,
      statusQueryErrors: statusQueryErrors ?? this.statusQueryErrors,
      debugLastError: clearError
          ? null
          : (debugLastError ?? this.debugLastError),
      daemonUpgradeErrors: daemonUpgradeErrors ?? this.daemonUpgradeErrors,
      daemonUpgradeProgress:
          daemonUpgradeProgress ?? this.daemonUpgradeProgress,
      pendingRuntimeCreations:
          pendingRuntimeCreations ?? this.pendingRuntimeCreations,
      pendingDeletionAgentDids:
          pendingDeletionAgentDids ?? this.pendingDeletionAgentDids,
    );
  }
}

class AgentsController extends StateNotifier<AgentsState> {
  AgentsController(this.ref) : super(const AgentsState());

  final Ref ref;
  final Map<String, Timer> _statusQueryTimeouts = <String, Timer>{};
  final Map<String, Timer> _statusQueryClearTimers = <String, Timer>{};
  final Map<String, Timer> _statusQueryPollTimers = <String, Timer>{};
  final Map<String, String> _statusQueryCommandIds = <String, String>{};
  final Map<String, Timer> _runtimeCreationTimeouts = <String, Timer>{};
  final Map<String, Timer> _daemonUpgradeAckTimeouts = <String, Timer>{};
  final Map<String, Timer> _daemonUpgradeCancelAckTimeouts = <String, Timer>{};
  final Map<String, Timer> _deletionRefreshTimers = <String, Timer>{};
  Future<void>? _loadOperation;
  String? _loadOperationOwner;
  int? _loadOperationEpoch;
  String? _loadedCacheOwner;
  int _stateEpoch = 0;

  Future<void> ensureLoaded() {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      AwikiPerformanceLogger.log('agents.ensure_loaded.no_session');
      state = const AgentsState();
      _loadedCacheOwner = null;
      _stateEpoch += 1;
      return Future<void>.value();
    }
    final cacheOwner = _agentCacheOwner(session);
    final activeLoad = _loadOperation;
    if (activeLoad != null &&
        _loadOperationOwner == cacheOwner &&
        _loadOperationEpoch == _stateEpoch) {
      AwikiPerformanceLogger.log('agents.ensure_loaded.reuse');
      return activeLoad;
    }
    if (_loadedCacheOwner == cacheOwner) {
      AwikiPerformanceLogger.log('agents.ensure_loaded.cached');
      return Future<void>.value();
    }
    AwikiPerformanceLogger.log('agents.ensure_loaded.load');
    return load();
  }

  Future<void> load() async {
    final session = ref.read(sessionProvider).session;
    final cacheOwner = session == null ? null : _agentCacheOwner(session);
    final epoch = _stateEpoch;
    final activeLoad = _loadOperation;
    if (activeLoad != null &&
        _loadOperationOwner == cacheOwner &&
        _loadOperationEpoch == epoch) {
      return activeLoad;
    }
    final operation = _load();
    _loadOperation = operation;
    _loadOperationOwner = cacheOwner;
    _loadOperationEpoch = epoch;
    try {
      await operation;
    } finally {
      if (identical(_loadOperation, operation)) {
        _loadOperation = null;
        _loadOperationOwner = null;
        _loadOperationEpoch = null;
      }
    }
  }

  Future<void> _load() async {
    final totalWatch = Stopwatch()..start();
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      state = const AgentsState();
      _loadedCacheOwner = null;
      _stateEpoch += 1;
      return;
    }
    final startedEpoch = _stateEpoch;
    final cacheOwner = _agentCacheOwner(session);
    state = state.copyWith(isLoading: true, clearError: true);
    await AwikiPerformanceLogger.async(
      'agents.load.cache',
      () => _loadCached(cacheOwner),
    );
    if (!_isCurrentCacheOwner(cacheOwner, epoch: startedEpoch)) {
      return;
    }
    try {
      final remoteAgents = await AwikiPerformanceLogger.async(
        'agents.load.remote_list',
        () => ref
            .read(agentControlServiceProvider)
            .listAgents()
            .timeout(agentListLoadTimeout),
      );
      final agents = await AwikiPerformanceLogger.async(
        'agents.load.order',
        () async => _stableAgentOrder(
          await _mergeLatestDaemonStatusPayloads(remoteAgents),
        ),
        fields: <String, Object?>{'remote': remoteAgents.length},
      );
      if (!_isCurrentCacheOwner(cacheOwner, epoch: startedEpoch)) {
        return;
      }
      final pendingRuntimeCreations = _pendingCreationsAfterAgents(agents);
      final pendingDaemonUpgrades = _pendingDaemonUpgradesAfterAgents(agents);
      final cancellingDaemonUpgrades = _cancellingDaemonUpgradesAfterAgents(
        agents,
        pendingDaemonUpgrades,
      );
      final daemonUpgradeErrors = _daemonUpgradeErrorsAfterAgents(agents);
      final daemonUpgradeProgress = _daemonUpgradeProgressAfterAgents(
        agents,
        pendingDaemonUpgrades,
      );
      final pendingDeletionAgentDids = _pendingDeletionAfterAgents(agents);
      state = state.copyWith(
        agents: agents,
        selectedAgentDid: _nextSelection(agents),
        isLoading: false,
        pendingRuntimeCreations: pendingRuntimeCreations,
        pendingDaemonUpgrades: pendingDaemonUpgrades,
        cancellingDaemonUpgrades: cancellingDaemonUpgrades,
        daemonUpgradeErrors: daemonUpgradeErrors,
        daemonUpgradeProgress: daemonUpgradeProgress,
        pendingDeletionAgentDids: pendingDeletionAgentDids,
        clearError: true,
      );
      _loadedCacheOwner = cacheOwner;
      await _saveCacheBestEffort(cacheOwner, agents);
      final selectedAgent = state.selectedAgent;
      if (selectedAgent != null && selectedAgent.isRuntime) {
        unawaited(loadInvocationPolicy(selectedAgent.agentDid));
      }
      for (final daemon in agents.where((agent) => agent.isDaemon)) {
        if (_shouldAutoRefresh(daemon)) {
          unawaited(refreshDaemonStatus(daemon.agentDid, fromAutoLoad: true));
        }
      }
      totalWatch.stop();
      AwikiPerformanceLogger.log(
        'agents.load',
        elapsed: totalWatch.elapsed,
        fields: <String, Object?>{'agents': agents.length},
      );
    } catch (error) {
      if (_isCurrentCacheOwner(cacheOwner, epoch: startedEpoch)) {
        state = state.copyWith(
          isLoading: false,
          error: _agentErrorMessage(error),
          debugLastError: error.toString(),
        );
      }
    }
  }

  void select(String agentDid) {
    state = state.copyWith(selectedAgentDid: agentDid);
    if (_agentByDid(agentDid)?.isRuntime == true) {
      unawaited(loadInvocationPolicy(agentDid));
    }
  }

  void clearSelection() {
    state = state.copyWith(clearSelection: true);
  }

  Future<void> createDaemonInstallCommand() async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      state = state.copyWith(error: '请先登录。');
      return;
    }
    final controllerHandle = session.handle?.trim().toLowerCase();
    if (controllerHandle == null || controllerHandle.isEmpty) {
      state = state.copyWith(error: '当前账号没有可用 handle，暂时不能生成 Daemon 安装命令。');
      return;
    }
    await _runAction(AgentActionKeys.installCommand, () async {
      final command = await ref
          .read(agentControlServiceProvider)
          .createDaemonInstallCommand(
            controllerDid: session.did,
            controllerHandle: controllerHandle,
            clientPlatform: awikiClientPlatform(),
          );
      state = state.copyWith(installCommand: command, clearError: true);
    });
  }

  Future<void> refreshDaemonStatus(
    String daemonDid, {
    bool fromAutoLoad = false,
  }) async {
    final now = DateTime.now().toUtc();
    if (state.isStatusQueryPending(daemonDid)) {
      return;
    }
    final commandId = agentCommandId('cmd_agent_status');
    if (!fromAutoLoad) {
      _statusQueryClearTimers.remove(daemonDid)?.cancel();
      _statusQueryCommandIds[daemonDid] = commandId;
      state = state.copyWith(
        pendingStatusQueryAtByDaemon: <String, DateTime>{
          ...state.pendingStatusQueryAtByDaemon,
          daemonDid: now,
        },
        statusQueryErrors: _withoutStringKey(
          state.statusQueryErrors,
          daemonDid,
        ),
        clearError: true,
      );
      _scheduleStatusQueryTimeout(daemonDid, commandId);
      _pollDaemonStatusPayload(daemonDid: daemonDid, commandId: commandId);
    }
    try {
      await ref
          .read(agentControlServiceProvider)
          .refreshDaemonStatus(daemonDid, commandId: commandId)
          .timeout(agentStatusRequestSendTimeout);
      if (!fromAutoLoad) {
        state = state.copyWith(clearError: true);
      }
    } catch (error) {
      _cancelStatusQueryTracking(daemonDid);
      final nextPending = fromAutoLoad
          ? state.pendingStatusQueryAtByDaemon
          : _withoutKey(state.pendingStatusQueryAtByDaemon, daemonDid);
      if (!fromAutoLoad) {
        final isUpgrading = state.pendingDaemonUpgrades.containsKey(daemonDid);
        state = state.copyWith(
          pendingStatusQueryAtByDaemon: nextPending,
          statusQueryErrors: isUpgrading
              ? state.statusQueryErrors
              : <String, String>{
                  ...state.statusQueryErrors,
                  daemonDid: _agentStatusRefreshErrorMessage(error),
                },
        );
      } else if (!identical(nextPending, state.pendingStatusQueryAtByDaemon)) {
        state = state.copyWith(pendingStatusQueryAtByDaemon: nextPending);
      }
    }
  }

  Future<void> createHermesRuntime(
    String daemonDid, {
    required String handle,
    required String displayName,
  }) {
    return createRuntimeAgent(
      daemonDid,
      options: RuntimeAgentCreateOptions(
        kind: RuntimeAgentKind.hermes,
        handle: handle,
        displayName: displayName,
      ),
    );
  }

  Future<void> createRuntimeAgent(
    String daemonDid, {
    required RuntimeAgentCreateOptions options,
  }) async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      state = state.copyWith(error: '请先登录。');
      return;
    }
    await _runAction(AgentActionKeys.createRuntime(daemonDid), () async {
      final requestId = agentCommandId('app_req');
      final pending = PendingRuntimeCreation(
        requestId: requestId,
        daemonAgentDid: daemonDid,
        handle: options.handle,
        displayName: options.displayName,
        runtime: options.kind.runtime,
        createdAt: DateTime.now().toUtc(),
      );
      _runtimeCreationTimeouts.remove(requestId)?.cancel();
      state = state.copyWith(
        pendingRuntimeCreations: _upsertPendingRuntimeCreation(
          state.pendingRuntimeCreations,
          pending,
        ),
        selectedAgentDid: daemonDid,
        clearError: true,
      );
      _scheduleRuntimeCreationTimeout(requestId);
      try {
        await ref
            .read(agentControlServiceProvider)
            .createRuntimeAgent(
              daemonAgentDid: daemonDid,
              controllerDid: session.did,
              options: options,
              clientRequestId: requestId,
            );
      } catch (_) {
        _runtimeCreationTimeouts.remove(requestId)?.cancel();
        state = state.copyWith(
          pendingRuntimeCreations: _removePendingRuntimeCreation(
            state.pendingRuntimeCreations,
            requestId,
          ),
        );
        rethrow;
      }
      state = state.copyWith(
        pendingRuntimeCreations: _markPendingRuntimeCreationWaiting(
          state.pendingRuntimeCreations,
          requestId,
        ),
      );
      unawaited(load());
    });
  }

  Future<void> bootstrapMessageAgent({
    required String daemonDid,
    UserSubkeyPackage? userSubkeyPackage,
    String? appInstanceId,
  }) async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      state = state.copyWith(error: '请先登录。');
      return;
    }
    if (!ref.read(agentImEnabledProvider)) {
      state = state.copyWith(error: '消息处理 Agent 功能未开启。');
      return;
    }
    await ensureLoaded();
    final daemon = _agentByDid(daemonDid);
    if (daemon == null || !daemon.isDaemon) {
      state = state.copyWith(error: '请选择运行 Daemon。');
      return;
    }
    final daemonBootstrapPublicKey = _daemonBootstrapPublicKey(daemon);
    if (daemonBootstrapPublicKey == null) {
      state = state.copyWith(error: '运行 Daemon 尚未上报安全 bootstrap 公钥，请先刷新状态。');
      return;
    }
    final resolvedAppInstanceId =
        appInstanceId ?? _defaultAppInstanceId(session.credentialName);
    final existingMessageAgent = state.messageAgentRuntimeFor(daemonDid);
    await _runAction(
      AgentActionKeys.bootstrapMessageAgent(daemonDid),
      () async {
        final subkeyPackage =
            userSubkeyPackage ??
            await ref
                .read(identityCorePortProvider)
                .ensureDaemonSubkeyPackage(session.credentialName);
        if (existingMessageAgent != null) {
          await ref
              .read(messageAgentBindingPortProvider)
              .ensureBinding(
                userDid: subkeyPackage.userDid,
                daemonAgentDid: daemonDid,
                messageAgentDid: existingMessageAgent.agentDid,
                runtimeProvider: appMessageHandlerRuntimeProvider,
                runtimeProfile: const <String, Object?>{
                  'profile': appMessageHandlerRuntimeProfile,
                },
                delegatedKeyVerificationMethod:
                    subkeyPackage.verificationMethod,
              );
          return;
        }
        await ref
            .read(agentControlServiceProvider)
            .ensureMessageAgentBootstrap(
              daemonAgentDid: daemonDid,
              controllerDid: session.did,
              appInstanceId: resolvedAppInstanceId,
              userSubkeyPackage: subkeyPackage,
              daemonBootstrapPublicKey: daemonBootstrapPublicKey,
              userHandle: session.handle,
            );
      },
      timeout: agentMessageAgentBootstrapActionTimeout,
    );
  }

  Future<void> resetRuntimeSession(AgentSummary runtime) async {
    final daemonDid = runtime.daemonAgentDid;
    if (daemonDid == null) {
      return;
    }
    await _runAction(AgentActionKeys.resetRuntime(runtime.agentDid), () {
      return ref
          .read(agentControlServiceProvider)
          .resetRuntimeSession(
            daemonAgentDid: daemonDid,
            runtimeAgentDid: runtime.agentDid,
          );
    });
  }

  Future<void> retryRun(AgentSummary runtime, String runId) async {
    final daemonDid = runtime.daemonAgentDid;
    final normalizedRunId = runId.trim();
    if (daemonDid == null || normalizedRunId.isEmpty) {
      return;
    }
    await _runAction(AgentActionKeys.retryRun(runtime.agentDid), () {
      return ref
          .read(agentControlServiceProvider)
          .retryRun(
            daemonAgentDid: daemonDid,
            runtimeAgentDid: runtime.agentDid,
            runId: normalizedRunId,
          );
    });
  }

  Future<bool> upgradeDaemon(String daemonDid) async {
    if (state.isDaemonUpgradePending(daemonDid)) {
      return false;
    }
    final actionKey = AgentActionKeys.upgradeDaemon(daemonDid);
    if (state.isActionPending(actionKey)) {
      return false;
    }
    final requestedAt = DateTime.now().toUtc();
    final commandId = agentCommandId('cmd_daemon_upgrade');
    state = state.copyWith(
      pendingDaemonUpgrades: <String, PendingDaemonUpgrade>{
        ...state.pendingDaemonUpgrades,
        daemonDid: PendingDaemonUpgrade(
          commandId: commandId,
          requestedAt: requestedAt,
        ),
      },
      cancellingDaemonUpgrades: _withoutMapKey(
        state.cancellingDaemonUpgrades,
        daemonDid,
      ),
      daemonUpgradeProgress: <String, DaemonUpgradeProgress>{
        ...state.daemonUpgradeProgress,
        daemonDid: DaemonUpgradeProgress.started(),
      },
      daemonUpgradeErrors: _withoutStringKey(
        state.daemonUpgradeErrors,
        daemonDid,
      ),
      statusQueryErrors: _withoutStringKey(state.statusQueryErrors, daemonDid),
      pendingActionKeys: _withSetValue(state.pendingActionKeys, actionKey),
      clearError: true,
    );
    _scheduleDaemonUpgradeAckTimeout(daemonDid, commandId);
    try {
      await ref
          .read(agentControlServiceProvider)
          .upgradeDaemon(daemonDid, commandId: commandId)
          .timeout(agentActionTimeout);
      if (!mounted || !state.pendingDaemonUpgrades.containsKey(daemonDid)) {
        return true;
      }
      state = state.copyWith(
        pendingActionKeys: _withoutSetValue(state.pendingActionKeys, actionKey),
        clearError: true,
      );
      return true;
    } catch (error) {
      _cancelDaemonUpgradeTimers(daemonDid);
      state = state.copyWith(
        pendingActionKeys: _withoutSetValue(state.pendingActionKeys, actionKey),
        pendingDaemonUpgrades: _withoutMapKey(
          state.pendingDaemonUpgrades,
          daemonDid,
        ),
        daemonUpgradeProgress: _withoutDaemonUpgradeProgressKey(
          state.daemonUpgradeProgress,
          daemonDid,
        ),
        daemonUpgradeErrors: <String, String>{
          ...state.daemonUpgradeErrors,
          daemonDid: _agentErrorMessage(error),
        },
        error: _agentErrorMessage(error),
      );
      return false;
    } finally {
      if (mounted && state.isActionPending(actionKey)) {
        state = state.copyWith(
          pendingActionKeys: _withoutSetValue(
            state.pendingActionKeys,
            actionKey,
          ),
        );
      }
    }
  }

  Future<bool> cancelDaemonUpgrade(String daemonDid) async {
    if (!state.isDaemonUpgradePending(daemonDid) ||
        state.isDaemonUpgradeCancelling(daemonDid)) {
      return false;
    }
    final pendingUpgrade = state.pendingDaemonUpgrades[daemonDid];
    final commandId = agentCommandId('cmd_daemon_upgrade_cancel');
    state = state.copyWith(
      cancellingDaemonUpgrades: <String, PendingDaemonUpgradeCancel>{
        ...state.cancellingDaemonUpgrades,
        daemonDid: PendingDaemonUpgradeCancel(
          commandId: commandId,
          upgradeCommandId: pendingUpgrade?.commandId,
        ),
      },
      clearError: true,
    );
    _scheduleDaemonUpgradeCancelAckTimeout(daemonDid, commandId);
    try {
      await ref
          .read(agentControlServiceProvider)
          .cancelDaemonUpgrade(
            daemonDid,
            commandId: commandId,
            upgradeCommandId: pendingUpgrade?.commandId,
          )
          .timeout(agentActionTimeout);
      if (!mounted || !state.cancellingDaemonUpgrades.containsKey(daemonDid)) {
        return true;
      }
      return true;
    } catch (error) {
      _cancelDaemonUpgradeCancelTimer(daemonDid);
      state = state.copyWith(
        cancellingDaemonUpgrades: _withoutMapKey(
          state.cancellingDaemonUpgrades,
          daemonDid,
        ),
        daemonUpgradeErrors: <String, String>{
          ...state.daemonUpgradeErrors,
          daemonDid: _agentErrorMessage(error),
        },
        error: _agentErrorMessage(error),
      );
      return false;
    }
  }

  Future<void> unbindSelected() async {
    final selected = state.selectedAgent;
    if (selected == null) {
      return;
    }
    await _runAction(AgentActionKeys.unbind(selected.agentDid), () async {
      await ref
          .read(agentControlServiceProvider)
          .unbindAgent(selected.agentDid);
      await load();
    });
  }

  Future<void> deleteSelected() async {
    final selected = state.selectedAgent;
    if (selected == null) {
      return;
    }
    if (state.isDeletingAgent(selected.agentDid)) {
      return;
    }
    if (selected.isDaemon && _canUnbindUnfinishedDaemonInstall(selected)) {
      await _runAction(AgentActionKeys.unbind(selected.agentDid), () async {
        await ref
            .read(agentControlServiceProvider)
            .unbindAgent(selected.agentDid);
        await load();
      });
      return;
    }
    final actionKey = AgentActionKeys.delete(selected.agentDid);
    if (state.isActionPending(actionKey)) {
      return;
    }
    final daemon = selected.isDaemon
        ? selected
        : state.daemonForRuntime(selected);
    if (daemon == null || !_daemonAcceptsControlCommands(daemon)) {
      state = state.copyWith(error: '代理当前不可达，暂时不能删除。');
      return;
    }
    final deletingDids = selected.isDaemon
        ? {
            selected.agentDid,
            ...state
                .runtimesFor(selected.agentDid)
                .map((agent) => agent.agentDid),
          }
        : {selected.agentDid};
    state = state.copyWith(
      pendingActionKeys: _withSetValue(state.pendingActionKeys, actionKey),
      pendingDeletionAgentDids: <String>{
        ...state.pendingDeletionAgentDids,
        ...deletingDids,
      },
      clearError: true,
    );
    try {
      if (selected.isDaemon) {
        await ref
            .read(agentControlServiceProvider)
            .deleteDaemon(selected.agentDid)
            .timeout(agentActionTimeout);
      } else {
        await ref
            .read(agentControlServiceProvider)
            .deleteRuntimeAgent(
              daemonAgentDid: daemon.agentDid,
              runtimeAgentDid: selected.agentDid,
            )
            .timeout(agentActionTimeout);
      }
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        pendingActionKeys: _withoutSetValue(state.pendingActionKeys, actionKey),
        clearError: true,
      );
      _scheduleDeletionRefresh(daemon.agentDid);
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        pendingActionKeys: _withoutSetValue(state.pendingActionKeys, actionKey),
        pendingDeletionAgentDids: _withoutStringKeys(
          state.pendingDeletionAgentDids,
          deletingDids,
        ),
        error: _agentErrorMessage(error),
        debugLastError: error.toString(),
      );
    } finally {
      if (mounted && state.isActionPending(actionKey)) {
        state = state.copyWith(
          pendingActionKeys: _withoutSetValue(
            state.pendingActionKeys,
            actionKey,
          ),
        );
      }
    }
  }

  Future<void> pauseMessageAgentForDaemon(String daemonDid) async {
    final target = _messageAgentTargetForDaemon(daemonDid);
    if (target == null) {
      state = state.copyWith(error: '当前 Daemon 尚未创建消息处理 Agent。');
      return;
    }
    await _runAction(AgentActionKeys.pauseMessageAgent(daemonDid), () async {
      await ref
          .read(agentControlServiceProvider)
          .pauseMessageAgent(
            daemonAgentDid: daemonDid,
            messageAgentDid: target.agentDid,
          );
    });
  }

  Future<void> deleteMessageAgentForDaemon(String daemonDid) async {
    final target = _messageAgentTargetForDaemon(daemonDid);
    if (target == null) {
      state = state.copyWith(error: '当前 Daemon 尚未创建消息处理 Agent。');
      return;
    }
    if (state.isDeletingAgent(target.agentDid)) {
      return;
    }
    final actionKey = AgentActionKeys.deleteMessageAgent(daemonDid);
    if (state.isActionPending(actionKey)) {
      return;
    }
    state = state.copyWith(
      pendingActionKeys: _withSetValue(state.pendingActionKeys, actionKey),
      pendingDeletionAgentDids: <String>{
        ...state.pendingDeletionAgentDids,
        target.agentDid,
      },
      clearError: true,
    );
    try {
      await ref
          .read(agentControlServiceProvider)
          .deleteMessageAgent(
            daemonAgentDid: daemonDid,
            messageAgentDid: target.agentDid,
          )
          .timeout(agentActionTimeout);
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        pendingActionKeys: _withoutSetValue(state.pendingActionKeys, actionKey),
        clearError: true,
      );
      _scheduleDeletionRefresh(daemonDid);
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        pendingActionKeys: _withoutSetValue(state.pendingActionKeys, actionKey),
        pendingDeletionAgentDids: _withoutStringKeys(
          state.pendingDeletionAgentDids,
          {target.agentDid},
        ),
        error: _agentErrorMessage(error),
        debugLastError: error.toString(),
      );
    } finally {
      if (mounted && state.isActionPending(actionKey)) {
        state = state.copyWith(
          pendingActionKeys: _withoutSetValue(
            state.pendingActionKeys,
            actionKey,
          ),
        );
      }
    }
  }

  Future<void> revokeMessageAgentAuthorizationForDaemon(
    String daemonDid,
  ) async {
    final target = _messageAgentTargetForDaemon(daemonDid);
    if (target == null) {
      state = state.copyWith(error: '当前 Daemon 尚未创建消息处理 Agent。');
      return;
    }
    await _runAction(AgentActionKeys.revokeMessageAgent(daemonDid), () async {
      await ref
          .read(agentControlServiceProvider)
          .revokeMessageAgentAuthorization(
            daemonAgentDid: daemonDid,
            messageAgentDid: target.agentDid,
          );
    });
  }

  Future<void> renameSelected(String displayName) async {
    final selected = state.selectedAgent;
    if (selected == null) {
      return;
    }
    await _runAction(AgentActionKeys.rename(selected.agentDid), () async {
      await ref
          .read(agentControlServiceProvider)
          .updateDisplayName(
            agentDid: selected.agentDid,
            displayName: displayName,
          );
      await load();
    });
  }

  Future<void> loadInvocationPolicy(String agentDid) async {
    final normalized = agentDid.trim();
    if (normalized.isEmpty ||
        _agentByDid(normalized)?.isRuntime != true ||
        state.invocationPolicies.containsKey(normalized) ||
        state.loadingInvocationPolicies.contains(normalized)) {
      return;
    }
    state = state.copyWith(
      loadingInvocationPolicies: <String>{
        ...state.loadingInvocationPolicies,
        normalized,
      },
      invocationPolicyErrors: _withoutStringKey(
        state.invocationPolicyErrors,
        normalized,
      ),
    );
    try {
      final policy = await ref
          .read(agentControlServiceProvider)
          .getInvocationPolicy(normalized);
      state = state.copyWith(
        invocationPolicies: <String, AgentInvocationPolicy>{
          ...state.invocationPolicies,
          normalized: policy,
        },
        loadingInvocationPolicies: _withoutSetValue(
          state.loadingInvocationPolicies,
          normalized,
        ),
      );
    } catch (error) {
      state = state.copyWith(
        loadingInvocationPolicies: _withoutSetValue(
          state.loadingInvocationPolicies,
          normalized,
        ),
        invocationPolicyErrors: <String, String>{
          ...state.invocationPolicyErrors,
          normalized: _agentErrorMessage(error),
        },
      );
    }
  }

  Future<bool> saveInvocationPolicy(
    String agentDid,
    AgentInvocationPolicy policy,
  ) async {
    final normalized = agentDid.trim();
    if (normalized.isEmpty ||
        _agentByDid(normalized)?.isRuntime != true ||
        state.savingInvocationPolicies.contains(normalized)) {
      return false;
    }
    state = state.copyWith(
      savingInvocationPolicies: <String>{
        ...state.savingInvocationPolicies,
        normalized,
      },
      invocationPolicyErrors: _withoutStringKey(
        state.invocationPolicyErrors,
        normalized,
      ),
    );
    try {
      final saved = await ref
          .read(agentControlServiceProvider)
          .updateInvocationPolicy(agentDid: normalized, policy: policy);
      state = state.copyWith(
        invocationPolicies: <String, AgentInvocationPolicy>{
          ...state.invocationPolicies,
          normalized: saved,
        },
        savingInvocationPolicies: _withoutSetValue(
          state.savingInvocationPolicies,
          normalized,
        ),
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        savingInvocationPolicies: _withoutSetValue(
          state.savingInvocationPolicies,
          normalized,
        ),
        invocationPolicyErrors: <String, String>{
          ...state.invocationPolicyErrors,
          normalized: _agentErrorMessage(error),
        },
      );
      return false;
    }
  }

  void clearInstallCommand() {
    state = state.copyWith(clearInstallCommand: true);
  }

  void clear() {
    _loadedCacheOwner = null;
    _stateEpoch += 1;
    _cancelStatusTimers();
    state = const AgentsState();
  }

  void applyControlPayload(Map<String, Object?> payload) {
    if (payload['schema'] != AgentControlPayloads.statusSchema) {
      return;
    }
    final eventId = _string(payload['event_id']);
    if (eventId != null && state.seenControlEventIds.contains(eventId)) {
      return;
    }
    final merged = _mergeControlPayload(state.agents, payload);
    final pendingRuntimeCreations =
        _pendingCreationsAfterControlPayloadAndAgents(
          state.pendingRuntimeCreations,
          payload,
          merged,
        );
    final daemonDid =
        _string(payload['daemon_agent_did']) ??
        _string(_readMap(payload['daemon'])['agent_did']);
    if (_isStaleDaemonUpgradeCommandPayload(payload, daemonDid)) {
      return;
    }
    final nextPending = _pendingAfterStatusPayload(daemonDid);
    final nextPendingDaemonUpgrades = _pendingDaemonUpgradesAfterPayload(
      payload,
      daemonDid,
      merged,
    );
    if (daemonDid != null) {
      _statusQueryTimeouts.remove(daemonDid)?.cancel();
      _statusQueryPollTimers.remove(daemonDid)?.cancel();
      _statusQueryCommandIds.remove(daemonDid);
    }
    final nextDaemonUpgradeErrors = _daemonUpgradeErrorsAfterPayload(
      payload,
      daemonDid,
    );
    final nextDaemonUpgradeProgress = _daemonUpgradeProgressAfterPayload(
      payload,
      daemonDid,
      nextPendingDaemonUpgrades,
    );
    final nextPendingDeletionAgentDids = _pendingDeletionAfterAgents(merged);
    state = state.copyWith(
      agents: merged,
      selectedAgentDid: _nextSelection(merged),
      pendingRuntimeCreations: pendingRuntimeCreations,
      pendingStatusQueryAtByDaemon: nextPending,
      pendingDaemonUpgrades: nextPendingDaemonUpgrades,
      cancellingDaemonUpgrades: _cancellingDaemonUpgradesAfterPayload(
        payload,
        daemonDid,
        nextPendingDaemonUpgrades,
      ),
      daemonUpgradeErrors: nextDaemonUpgradeErrors,
      daemonUpgradeProgress: nextDaemonUpgradeProgress,
      pendingDeletionAgentDids: nextPendingDeletionAgentDids,
      statusQueryErrors: daemonDid == null
          ? state.statusQueryErrors
          : _withoutStringKey(state.statusQueryErrors, daemonDid),
      seenControlEventIds: eventId == null
          ? state.seenControlEventIds
          : _rememberControlEventId(state.seenControlEventIds, eventId),
      clearError: true,
    );
    final session = ref.read(sessionProvider).session;
    if (session != null) {
      unawaited(_saveCacheBestEffort(_agentCacheOwner(session), merged));
    }
  }

  bool _isStaleDaemonUpgradeCommandPayload(
    Map<String, Object?> payload,
    String? daemonDid,
  ) {
    if (daemonDid == null) {
      return false;
    }
    final result = _readMap(payload['result']);
    if (_string(result['command']) != 'daemon.upgrade') {
      return false;
    }
    final pending = state.pendingDaemonUpgrades[daemonDid];
    if (pending == null) {
      return false;
    }
    return !_commandIdMatches(
      _string(payload['command_id']),
      pending.commandId,
    );
  }

  Future<void> _runAction(
    String actionKey,
    Future<void> Function() action, {
    Duration timeout = agentActionTimeout,
  }) async {
    if (state.isActionPending(actionKey)) {
      return;
    }
    state = state.copyWith(
      pendingActionKeys: _withSetValue(state.pendingActionKeys, actionKey),
      clearError: true,
    );
    try {
      await action().timeout(timeout);
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        pendingActionKeys: _withoutSetValue(state.pendingActionKeys, actionKey),
        clearError: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        pendingActionKeys: _withoutSetValue(state.pendingActionKeys, actionKey),
        error: _agentErrorMessage(error),
        debugLastError: error.toString(),
      );
    } finally {
      if (mounted && state.isActionPending(actionKey)) {
        state = state.copyWith(
          pendingActionKeys: _withoutSetValue(
            state.pendingActionKeys,
            actionKey,
          ),
        );
      }
    }
  }

  void _scheduleDeletionRefresh(String daemonDid, {int attempt = 0}) {
    _deletionRefreshTimers.remove(daemonDid)?.cancel();
    if (!mounted ||
        attempt >= agentDeletionRefreshAttempts ||
        !_hasPendingDeletionForDaemon(daemonDid)) {
      _finishDeletionRefresh(daemonDid);
      return;
    }
    final delay = attempt == 0 ? Duration.zero : agentDeletionRefreshDelay;
    _deletionRefreshTimers[daemonDid] = Timer(delay, () {
      _deletionRefreshTimers.remove(daemonDid);
      unawaited(_runDeletionRefreshAttempt(daemonDid, attempt));
    });
  }

  Future<void> _runDeletionRefreshAttempt(String daemonDid, int attempt) async {
    if (!mounted || !_hasPendingDeletionForDaemon(daemonDid)) {
      return;
    }
    try {
      await refreshDaemonStatus(daemonDid, fromAutoLoad: true);
    } catch (_) {
      // Refresh errors are surfaced by refreshDaemonStatus when user-facing.
    }
    if (!mounted || !_hasPendingDeletionForDaemon(daemonDid)) {
      return;
    }
    _scheduleDeletionRefresh(daemonDid, attempt: attempt + 1);
  }

  void _finishDeletionRefresh(String daemonDid) {
    if (!mounted) {
      return;
    }
    final remaining = _pendingDeletionAfterAgents(state.agents);
    if (!identical(remaining, state.pendingDeletionAgentDids)) {
      state = state.copyWith(pendingDeletionAgentDids: remaining);
    }
  }

  bool _hasPendingDeletionForDaemon(String daemonDid) {
    if (state.pendingDeletionAgentDids.contains(daemonDid)) {
      return true;
    }
    return state
        .runtimesFor(daemonDid)
        .any(
          (agent) => state.pendingDeletionAgentDids.contains(agent.agentDid),
        );
  }

  void _scheduleStatusQueryTimeout(String daemonDid, String commandId) {
    _statusQueryTimeouts.remove(daemonDid)?.cancel();
    _statusQueryTimeouts[daemonDid] = Timer(agentStatusQueryTimeout, () {
      _statusQueryTimeouts.remove(daemonDid);
      _handleStatusQueryTimeout(daemonDid, commandId);
    });
  }

  Future<void> handleStatusQueryTimeoutForTest(String daemonDid) {
    _statusQueryTimeouts.remove(daemonDid)?.cancel();
    return _handleStatusQueryTimeout(
      daemonDid,
      _statusQueryCommandIds[daemonDid],
    );
  }

  Future<void> _handleStatusQueryTimeout(
    String daemonDid,
    String? commandId,
  ) async {
    if (!mounted ||
        !state.pendingStatusQueryAtByDaemon.containsKey(daemonDid)) {
      return;
    }
    _statusQueryPollTimers.remove(daemonDid)?.cancel();
    _statusQueryCommandIds.remove(daemonDid);
    state = state.copyWith(
      pendingStatusQueryAtByDaemon: _withoutKey(
        state.pendingStatusQueryAtByDaemon,
        daemonDid,
      ),
      statusQueryErrors: state.pendingDaemonUpgrades.containsKey(daemonDid)
          ? state.statusQueryErrors
          : <String, String>{
              ...state.statusQueryErrors,
              daemonDid: '状态同步仍在等待，请稍后刷新查看。',
            },
    );
    if (commandId != null) {
      unawaited(
        _applyDaemonStatusPayloadFromStore(
          daemonDid: daemonDid,
          commandId: commandId,
        ),
      );
    }
  }

  void _pollDaemonStatusPayload({
    required String daemonDid,
    required String commandId,
  }) {
    _statusQueryPollTimers.remove(daemonDid)?.cancel();
    var attempts = 0;
    var lookupInFlight = false;
    _statusQueryPollTimers[daemonDid] = Timer.periodic(
      agentStatusQueryPollInterval,
      (timer) async {
        if (!mounted ||
            !state.pendingStatusQueryAtByDaemon.containsKey(daemonDid)) {
          timer.cancel();
          if (identical(_statusQueryPollTimers[daemonDid], timer)) {
            _statusQueryPollTimers.remove(daemonDid);
          }
          return;
        }
        if (lookupInFlight) {
          return;
        }
        lookupInFlight = true;
        attempts += 1;
        final applied =
            await _applyDaemonStatusPayloadFromStore(
              daemonDid: daemonDid,
              commandId: commandId,
            ).whenComplete(() {
              lookupInFlight = false;
            });
        if (!mounted) {
          timer.cancel();
          return;
        }
        final exhausted = attempts >= agentStatusQueryPollAttempts;
        if (applied ||
            !state.pendingStatusQueryAtByDaemon.containsKey(daemonDid) ||
            exhausted) {
          timer.cancel();
          if (identical(_statusQueryPollTimers[daemonDid], timer)) {
            _statusQueryPollTimers.remove(daemonDid);
          }
          if (!applied && exhausted) {
            unawaited(_handleStatusQueryTimeout(daemonDid, commandId));
          }
        }
      },
    );
  }

  Future<bool> _applyDaemonStatusPayloadFromStore({
    required String daemonDid,
    required String commandId,
  }) async {
    final payload = await ref
        .read(agentControlStatusStoreProvider)
        .findDaemonStatusPayload(
          daemonAgentDid: daemonDid,
          requestId: commandId,
        )
        .timeout(agentStatusPayloadLookupTimeout, onTimeout: () => null);
    if (!mounted || payload == null) {
      return false;
    }
    applyControlPayload(payload);
    return true;
  }

  void _scheduleRuntimeCreationTimeout(String requestId) {
    _runtimeCreationTimeouts.remove(requestId)?.cancel();
    _runtimeCreationTimeouts[requestId] = Timer(
      agentRuntimeCreationTimeout,
      () {
        _runtimeCreationTimeouts.remove(requestId);
        if (!mounted) {
          return;
        }
        state = state.copyWith(
          pendingRuntimeCreations: _markPendingRuntimeCreationWaiting(
            state.pendingRuntimeCreations,
            requestId,
          ),
        );
      },
    );
  }

  void _scheduleDaemonUpgradeAckTimeout(String daemonDid, String commandId) {
    _daemonUpgradeAckTimeouts.remove(daemonDid)?.cancel();
    _daemonUpgradeAckTimeouts[daemonDid] = Timer(
      agentDaemonUpgradeAckTimeout,
      () {
        _daemonUpgradeAckTimeouts.remove(daemonDid);
        _handleDaemonUpgradeAckTimeout(daemonDid, commandId);
      },
    );
  }

  void _handleDaemonUpgradeAckTimeout(String daemonDid, String commandId) {
    if (!mounted) {
      return;
    }
    final pending = state.pendingDaemonUpgrades[daemonDid];
    if (pending == null ||
        pending.commandId != commandId ||
        pending.acknowledged) {
      return;
    }
    state = state.copyWith(
      daemonUpgradeProgress: <String, DaemonUpgradeProgress>{
        ...state.daemonUpgradeProgress,
        daemonDid: DaemonUpgradeProgress.waitingForDaemonConfirmation(),
      },
      pendingActionKeys: _withoutSetValue(
        state.pendingActionKeys,
        AgentActionKeys.upgradeDaemon(daemonDid),
      ),
    );
    unawaited(refreshDaemonStatus(daemonDid, fromAutoLoad: true));
  }

  void _scheduleDaemonUpgradeCancelAckTimeout(
    String daemonDid,
    String commandId,
  ) {
    _daemonUpgradeCancelAckTimeouts.remove(daemonDid)?.cancel();
    _daemonUpgradeCancelAckTimeouts[daemonDid] = Timer(
      agentDaemonUpgradeCancelAckTimeout,
      () {
        _daemonUpgradeCancelAckTimeouts.remove(daemonDid);
        _handleDaemonUpgradeCancelAckTimeout(daemonDid, commandId);
      },
    );
  }

  void _handleDaemonUpgradeCancelAckTimeout(
    String daemonDid,
    String commandId,
  ) {
    if (!mounted) {
      return;
    }
    final cancelling = state.cancellingDaemonUpgrades[daemonDid];
    if (cancelling == null || cancelling.commandId != commandId) {
      return;
    }
    state = state.copyWith(
      cancellingDaemonUpgrades: _withoutMapKey(
        state.cancellingDaemonUpgrades,
        daemonDid,
      ),
      daemonUpgradeErrors: <String, String>{
        ...state.daemonUpgradeErrors,
        daemonDid: '取消请求已发送，但代理暂未响应。请刷新状态确认升级结果。',
      },
    );
  }

  void handleDaemonUpgradeAckTimeoutForTest(
    String daemonDid,
    String commandId,
  ) {
    _daemonUpgradeAckTimeouts.remove(daemonDid)?.cancel();
    _handleDaemonUpgradeAckTimeout(daemonDid, commandId);
  }

  void handleDaemonUpgradeCancelAckTimeoutForTest(
    String daemonDid,
    String commandId,
  ) {
    _daemonUpgradeCancelAckTimeouts.remove(daemonDid)?.cancel();
    _handleDaemonUpgradeCancelAckTimeout(daemonDid, commandId);
  }

  Map<String, DateTime> _pendingAfterStatusPayload(String? daemonDid) {
    if (daemonDid == null) {
      return state.pendingStatusQueryAtByDaemon;
    }
    final pendingAt = state.pendingStatusQueryAtByDaemon[daemonDid];
    if (pendingAt == null) {
      _statusQueryClearTimers.remove(daemonDid)?.cancel();
      return state.pendingStatusQueryAtByDaemon;
    }
    final elapsed = DateTime.now().toUtc().difference(pendingAt);
    final remaining = agentStatusRefreshMinimumIndicatorDuration - elapsed;
    if (remaining > Duration.zero) {
      _scheduleStatusQueryClear(daemonDid, pendingAt, remaining);
      return state.pendingStatusQueryAtByDaemon;
    }
    _statusQueryClearTimers.remove(daemonDid)?.cancel();
    return _withoutKey(state.pendingStatusQueryAtByDaemon, daemonDid);
  }

  Map<String, PendingDaemonUpgrade> _pendingDaemonUpgradesAfterPayload(
    Map<String, Object?> payload,
    String? daemonDid,
    List<AgentSummary> merged,
  ) {
    if (daemonDid == null ||
        !state.pendingDaemonUpgrades.containsKey(daemonDid)) {
      return state.pendingDaemonUpgrades;
    }
    final result = _readMap(payload['result']);
    final command = _string(result['command']);
    final commandId = _string(payload['command_id']);
    final payloadState = _string(payload['state'])?.toLowerCase();
    final resultStatus = _string(result['status'])?.toLowerCase();
    if (command == 'daemon.upgrade') {
      final pending = state.pendingDaemonUpgrades[daemonDid];
      if (pending != null && !_commandIdMatches(commandId, pending.commandId)) {
        return state.pendingDaemonUpgrades;
      }
      if (pending != null) {
        _cancelDaemonUpgradeAckTimer(daemonDid);
      }
      if (payloadState == 'cancelled' ||
          resultStatus == 'cancelled' ||
          payloadState == 'failed' ||
          resultStatus == 'failed' ||
          result['error_code'] != null) {
        return _withoutMapKey(state.pendingDaemonUpgrades, daemonDid);
      }
      if (_isFinalDaemonUpgradeSuccess(payload, result)) {
        return _withoutMapKey(state.pendingDaemonUpgrades, daemonDid);
      }
      return _acknowledgePendingDaemonUpgrade(
        state.pendingDaemonUpgrades,
        daemonDid,
        commandId,
      );
    }
    final daemon = merged.where((agent) => agent.agentDid == daemonDid);
    if (daemon.isEmpty) {
      return _withoutMapKey(state.pendingDaemonUpgrades, daemonDid);
    }
    final latest = daemon.first.latest;
    final latestStatus = latest.status.trim().toLowerCase();
    if (latestStatus == 'failed' ||
        latestStatus == 'error' ||
        latestStatus == 'gateway_error' ||
        (!latest.needsUpgrade &&
            latestStatus != 'upgrading' &&
            latestStatus != 'restart_scheduled')) {
      return _withoutMapKey(state.pendingDaemonUpgrades, daemonDid);
    }
    return state.pendingDaemonUpgrades;
  }

  Map<String, PendingDaemonUpgradeCancel> _cancellingDaemonUpgradesAfterPayload(
    Map<String, Object?> payload,
    String? daemonDid,
    Map<String, PendingDaemonUpgrade> nextPendingDaemonUpgrades,
  ) {
    if (daemonDid == null ||
        !state.cancellingDaemonUpgrades.containsKey(daemonDid)) {
      return state.cancellingDaemonUpgrades;
    }
    final result = _readMap(payload['result']);
    final command = _string(result['command']);
    if (command == 'daemon.upgrade.cancel') {
      final commandId = _string(payload['command_id']);
      final cancelling = state.cancellingDaemonUpgrades[daemonDid];
      if (cancelling != null &&
          !_commandIdMatches(commandId, cancelling.commandId)) {
        return state.cancellingDaemonUpgrades;
      }
      _cancelDaemonUpgradeCancelTimer(daemonDid);
      final status = _string(result['status'])?.toLowerCase();
      final payloadState = _string(payload['state'])?.toLowerCase();
      if (status == 'not_running' ||
          status == 'not_cancellable' ||
          status == 'cancelled' ||
          payloadState == 'failed' ||
          payloadState == 'cancelled' ||
          result['error_code'] != null) {
        return _withoutMapKey(state.cancellingDaemonUpgrades, daemonDid);
      }
      return state.cancellingDaemonUpgrades;
    }
    if (command == 'daemon.upgrade') {
      final commandId = _string(payload['command_id']);
      final pending = state.pendingDaemonUpgrades[daemonDid];
      if (pending != null && !_commandIdMatches(commandId, pending.commandId)) {
        return state.cancellingDaemonUpgrades;
      }
      final status = _string(result['status'])?.toLowerCase();
      final payloadState = _string(payload['state'])?.toLowerCase();
      if (!nextPendingDaemonUpgrades.containsKey(daemonDid) ||
          status == 'cancelled' ||
          status == 'failed' ||
          payloadState == 'cancelled' ||
          payloadState == 'failed' ||
          result['error_code'] != null ||
          _isFinalDaemonUpgradeSuccess(payload, result)) {
        _cancelDaemonUpgradeCancelTimer(daemonDid);
        return _withoutMapKey(state.cancellingDaemonUpgrades, daemonDid);
      }
    }
    if (_daemonStatusShowsUpgradeResolved(payload)) {
      _cancelDaemonUpgradeCancelTimer(daemonDid);
      return _withoutMapKey(state.cancellingDaemonUpgrades, daemonDid);
    }
    return state.cancellingDaemonUpgrades;
  }

  Map<String, String> _daemonUpgradeErrorsAfterPayload(
    Map<String, Object?> payload,
    String? daemonDid,
  ) {
    if (daemonDid == null) {
      return state.daemonUpgradeErrors;
    }
    final result = _readMap(payload['result']);
    if (_string(result['command']) == 'daemon.upgrade.cancel') {
      final commandId = _string(payload['command_id']);
      final cancelling = state.cancellingDaemonUpgrades[daemonDid];
      if (cancelling != null &&
          !_commandIdMatches(commandId, cancelling.commandId)) {
        return state.daemonUpgradeErrors;
      }
      final payloadState = _string(payload['state'])?.toLowerCase();
      final resultStatus = _string(result['status'])?.toLowerCase();
      if (payloadState == 'failed' ||
          resultStatus == 'not_cancellable' ||
          result['error_code'] != null) {
        return <String, String>{
          ...state.daemonUpgradeErrors,
          daemonDid: _daemonUpgradeCancelFailureMessage(result),
        };
      }
      return state.daemonUpgradeErrors;
    }
    if (_string(result['command']) != 'daemon.upgrade') {
      if (_daemonStatusShowsUpgradeResolved(payload)) {
        return _withoutStringKey(state.daemonUpgradeErrors, daemonDid);
      }
      return state.daemonUpgradeErrors;
    }
    final commandId = _string(payload['command_id']);
    final pending = state.pendingDaemonUpgrades[daemonDid];
    if (pending != null && !_commandIdMatches(commandId, pending.commandId)) {
      return state.daemonUpgradeErrors;
    }
    if (_isFinalDaemonUpgradeSuccess(payload, result)) {
      return _withoutStringKey(state.daemonUpgradeErrors, daemonDid);
    }
    final payloadState = _string(payload['state'])?.toLowerCase();
    final resultStatus = _string(result['status'])?.toLowerCase();
    if (payloadState == 'cancelled' ||
        resultStatus == 'cancelled' ||
        _string(result['error_code']) == 'upgrade_cancelled') {
      return _withoutStringKey(state.daemonUpgradeErrors, daemonDid);
    }
    final failed =
        payloadState == 'failed' ||
        resultStatus == 'failed' ||
        result['error_code'] != null;
    if (!failed) {
      return state.daemonUpgradeErrors;
    }
    return <String, String>{
      ...state.daemonUpgradeErrors,
      daemonDid: _daemonUpgradeFailureMessage(result),
    };
  }

  Map<String, DaemonUpgradeProgress> _daemonUpgradeProgressAfterPayload(
    Map<String, Object?> payload,
    String? daemonDid,
    Map<String, PendingDaemonUpgrade> nextPendingDaemonUpgrades,
  ) {
    if (daemonDid == null) {
      return state.daemonUpgradeProgress;
    }
    final result = _readMap(payload['result']);
    if (_string(result['command']) != 'daemon.upgrade') {
      if (_daemonStatusShowsUpgradeResolved(payload)) {
        return _withoutDaemonUpgradeProgressKey(
          state.daemonUpgradeProgress,
          daemonDid,
        );
      }
      return state.daemonUpgradeProgress;
    }
    final commandId = _string(payload['command_id']);
    final pending = state.pendingDaemonUpgrades[daemonDid];
    if (pending != null && !_commandIdMatches(commandId, pending.commandId)) {
      return state.daemonUpgradeProgress;
    }
    if (!nextPendingDaemonUpgrades.containsKey(daemonDid)) {
      return _withoutDaemonUpgradeProgressKey(
        state.daemonUpgradeProgress,
        daemonDid,
      );
    }
    final progress = DaemonUpgradeProgress.fromPayload(result);
    if (progress == null) {
      return state.daemonUpgradeProgress;
    }
    return <String, DaemonUpgradeProgress>{
      ...state.daemonUpgradeProgress,
      daemonDid: progress,
    };
  }

  void _scheduleStatusQueryClear(
    String daemonDid,
    DateTime pendingAt,
    Duration delay,
  ) {
    _statusQueryClearTimers.remove(daemonDid)?.cancel();
    _statusQueryClearTimers[daemonDid] = Timer(delay, () {
      _statusQueryClearTimers.remove(daemonDid);
      if (!mounted ||
          state.pendingStatusQueryAtByDaemon[daemonDid] != pendingAt) {
        return;
      }
      state = state.copyWith(
        pendingStatusQueryAtByDaemon: _withoutKey(
          state.pendingStatusQueryAtByDaemon,
          daemonDid,
        ),
      );
    });
  }

  void _cancelDaemonUpgradeAckTimer(String daemonDid) {
    _daemonUpgradeAckTimeouts.remove(daemonDid)?.cancel();
  }

  void _cancelDaemonUpgradeCancelTimer(String daemonDid) {
    _daemonUpgradeCancelAckTimeouts.remove(daemonDid)?.cancel();
  }

  void _cancelDaemonUpgradeTimers(String daemonDid) {
    _cancelDaemonUpgradeAckTimer(daemonDid);
    _cancelDaemonUpgradeCancelTimer(daemonDid);
  }

  void _cancelStatusQueryTracking(String daemonDid) {
    _statusQueryTimeouts.remove(daemonDid)?.cancel();
    _statusQueryClearTimers.remove(daemonDid)?.cancel();
    _statusQueryPollTimers.remove(daemonDid)?.cancel();
    _statusQueryCommandIds.remove(daemonDid);
  }

  @override
  void dispose() {
    _cancelStatusTimers();
    super.dispose();
  }

  void _cancelStatusTimers() {
    for (final timer in _statusQueryTimeouts.values) {
      timer.cancel();
    }
    _statusQueryTimeouts.clear();
    for (final timer in _statusQueryClearTimers.values) {
      timer.cancel();
    }
    _statusQueryClearTimers.clear();
    for (final timer in _statusQueryPollTimers.values) {
      timer.cancel();
    }
    _statusQueryPollTimers.clear();
    _statusQueryCommandIds.clear();
    for (final timer in _runtimeCreationTimeouts.values) {
      timer.cancel();
    }
    _runtimeCreationTimeouts.clear();
    for (final timer in _daemonUpgradeAckTimeouts.values) {
      timer.cancel();
    }
    _daemonUpgradeAckTimeouts.clear();
    for (final timer in _daemonUpgradeCancelAckTimeouts.values) {
      timer.cancel();
    }
    _daemonUpgradeCancelAckTimeouts.clear();
    for (final timer in _deletionRefreshTimers.values) {
      timer.cancel();
    }
    _deletionRefreshTimers.clear();
  }

  Future<void> _loadCached(String ownerDid) async {
    final List<LocalAgentState> cached;
    try {
      cached = await ref
          .read(productLocalStoreProvider)
          .loadAgentStates(ownerDid: ownerDid)
          .timeout(agentLocalCacheReadTimeout);
    } catch (_) {
      return;
    }
    if (cached.isEmpty) {
      return;
    }
    final agents = <AgentSummary>[];
    for (final item in cached) {
      try {
        final decoded = jsonDecode(item.valueJson);
        if (decoded is Map) {
          agents.add(
            AgentSummary.fromJson(
              decoded.map<String, Object?>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          );
        }
      } catch (_) {
        continue;
      }
    }
    final ordered = _stableAgentOrder(agents);
    if (ordered.isNotEmpty) {
      if (!_isCurrentCacheOwner(ownerDid)) {
        return;
      }
      state = state.copyWith(
        agents: ordered,
        selectedAgentDid: _nextSelection(ordered),
      );
    }
  }

  bool _isCurrentCacheOwner(String ownerDid, {int? epoch}) {
    if (!mounted) {
      return false;
    }
    if (epoch != null && epoch != _stateEpoch) {
      return false;
    }
    final session = ref.read(sessionProvider).session;
    return session != null && _agentCacheOwner(session) == ownerDid;
  }

  Future<void> _saveCacheBestEffort(
    String ownerDid,
    List<AgentSummary> agents,
  ) async {
    try {
      await _saveCache(ownerDid, agents).timeout(agentLocalCacheWriteTimeout);
    } catch (_) {
      // Local cache is only a fast-start snapshot; remote inventory remains
      // the source of truth for the Agent page.
    }
  }

  Future<void> _saveCache(String ownerDid, List<AgentSummary> agents) async {
    final store = ref.read(productLocalStoreProvider);
    final now = DateTime.now().toUtc();
    final retainedAgentDids = agents.map((agent) => agent.agentDid).toSet();
    final cached = await store.loadAgentStates(ownerDid: ownerDid);
    for (final item in cached) {
      if (!retainedAgentDids.contains(item.agentDid)) {
        await store.deleteAgentState(
          ownerDid: ownerDid,
          agentDid: item.agentDid,
        );
      }
    }
    for (final agent in agents) {
      await store.saveAgentState(
        LocalAgentState(
          ownerDid: ownerDid,
          agentDid: agent.agentDid,
          valueJson: jsonEncode(agent.toJson()),
          updatedAt: now,
        ),
      );
    }
  }

  Future<List<AgentSummary>> _mergeLatestDaemonStatusPayloads(
    List<AgentSummary> agents,
  ) async {
    final totalWatch = Stopwatch()..start();
    var merged = _stableAgentOrder(agents);
    final store = ref.read(agentControlStatusStoreProvider);
    var daemonCount = 0;
    var payloadCount = 0;
    for (final daemon in agents.where((agent) => agent.isDaemon)) {
      final Map<String, Object?>? payload;
      daemonCount += 1;
      try {
        payload = await AwikiPerformanceLogger.async(
          'agents.load.daemon_status_payload',
          () => store
              .findLatestDaemonStatusPayload(daemonAgentDid: daemon.agentDid)
              .timeout(agentStatusPayloadLookupTimeout, onTimeout: () => null),
          fields: <String, Object?>{
            'daemon_hash': AwikiPerformanceLogger.safeHash(daemon.agentDid),
          },
        );
      } catch (_) {
        continue;
      }
      if (payload == null) {
        continue;
      }
      payloadCount += 1;
      merged = _mergeControlPayload(merged, payload);
    }
    final ordered = _stableAgentOrder(merged);
    totalWatch.stop();
    AwikiPerformanceLogger.log(
      'agents.load.merge_daemon_status',
      elapsed: totalWatch.elapsed,
      fields: <String, Object?>{
        'agents': agents.length,
        'daemons': daemonCount,
        'payloads': payloadCount,
      },
    );
    return ordered;
  }

  String? _nextSelection(List<AgentSummary> agents) {
    final current = state.selectedAgentDid;
    if (current != null && agents.any((agent) => agent.agentDid == current)) {
      return current;
    }
    return agents.isEmpty ? null : agents.first.agentDid;
  }

  bool _shouldAutoRefresh(AgentSummary daemon) {
    return daemon.latest.status == 'ready' || daemon.latest.status == 'offline';
  }

  AgentSummary? _agentByDid(String agentDid) {
    final normalized = agentDid.trim();
    for (final agent in state.agents) {
      if (agent.agentDid == normalized) {
        return agent;
      }
    }
    return null;
  }

  AgentSummary? _messageAgentTargetForDaemon(String daemonDid) {
    final daemon = _agentByDid(daemonDid);
    if (daemon == null ||
        !daemon.isDaemon ||
        !_daemonAcceptsControlCommands(daemon)) {
      return null;
    }
    return state.messageAgentRuntimeFor(daemonDid);
  }

  DaemonBootstrapPublicKey? _daemonBootstrapPublicKey(AgentSummary daemon) {
    try {
      return DaemonBootstrapPublicKey.fromDiagnostics(
        daemonDid: daemon.agentDid,
        diagnostics: daemon.latest.diagnosticsSummary,
      );
    } catch (_) {
      return null;
    }
  }

  List<AgentSummary> _mergeControlPayload(
    List<AgentSummary> current,
    Map<String, Object?> payload,
  ) {
    final eventAt = _dateTime(payload['sent_at']);
    final statusScope = _string(payload['status_scope']);
    final payloadDaemonDid =
        _string(payload['daemon_agent_did']) ??
        _string(_readMap(payload['daemon'])['agent_did']);
    final byDid = <String, AgentSummary>{
      for (final agent in current) agent.agentDid: agent,
    };
    final snapshotRuntimeDids = <String>{};
    final daemonPayload = _readMap(payload['daemon']);
    if (daemonPayload.isNotEmpty) {
      final daemonDid = _string(daemonPayload['agent_did']) ?? payloadDaemonDid;
      if (daemonDid != null) {
        byDid[daemonDid] = _mergeAgent(
          byDid[daemonDid],
          agentDid: daemonDid,
          kind: AgentKind.daemon,
          payload: daemonPayload,
          fallbackStatus: _string(payload['state']),
          fallbackEventAt: eventAt,
        );
      }
    }
    final runtimes = payload['runtimes'];
    if (runtimes is List) {
      for (final item in runtimes) {
        final runtimePayload = _readMap(item);
        final runtimeDid = _string(runtimePayload['agent_did']);
        if (runtimeDid == null) {
          continue;
        }
        if (_isArchivedAgentPayload(runtimePayload)) {
          byDid.remove(runtimeDid);
          continue;
        }
        byDid[runtimeDid] = _mergeAgent(
          byDid[runtimeDid],
          agentDid: runtimeDid,
          daemonDid:
              _string(runtimePayload['daemon_agent_did']) ??
              _string(payload['daemon_agent_did']),
          kind: AgentKind.runtime,
          payload: runtimePayload,
          fallbackStatus: _string(runtimePayload['status']),
          fallbackEventAt: eventAt,
        );
        if ((_string(runtimePayload['daemon_agent_did']) ?? payloadDaemonDid) ==
            payloadDaemonDid) {
          snapshotRuntimeDids.add(runtimeDid);
        }
      }
    }
    if (statusScope == 'snapshot' && payloadDaemonDid != null) {
      final pruned = <String, AgentSummary>{};
      for (final entry in byDid.entries) {
        final agent = entry.value;
        final shouldPrune =
            agent.isRuntime &&
            agent.daemonAgentDid == payloadDaemonDid &&
            !snapshotRuntimeDids.contains(agent.agentDid) &&
            !_isStaleAgentStatus(agent, eventAt);
        if (!shouldPrune) {
          pruned[entry.key] = agent;
        }
      }
      byDid
        ..clear()
        ..addAll(pruned);
    }
    final result = _readMap(payload['result']);
    final command = _string(result['command']);
    if (command == 'runtime.agent.create') {
      final runtimeDid =
          _string(result['runtime_agent_did']) ?? _string(result['agent_did']);
      if (runtimeDid != null) {
        byDid[runtimeDid] = _mergeAgent(
          byDid[runtimeDid],
          agentDid: runtimeDid,
          daemonDid: _string(result['daemon_agent_did']),
          kind: AgentKind.runtime,
          payload: <String, Object?>{
            ...result,
            'agent_did': runtimeDid,
            'status': _string(payload['state']) ?? 'ready',
          },
          fallbackStatus: _string(payload['state']),
          fallbackEventAt: eventAt,
          allowPayloadDisplayName: true,
        );
      }
    } else if (command == 'daemon.upgrade') {
      final daemonDid =
          _string(result['daemon_agent_did']) ??
          _string(payload['daemon_agent_did']);
      if (daemonDid != null) {
        final statusPayload = _daemonUpgradeStatusPayload(
          result,
          payloadState: _string(payload['state']),
        );
        byDid[daemonDid] = _mergeAgent(
          byDid[daemonDid],
          agentDid: daemonDid,
          kind: AgentKind.daemon,
          payload: <String, Object?>{...statusPayload, 'agent_did': daemonDid},
          fallbackStatus:
              _string(statusPayload['status']) ?? _string(payload['state']),
          fallbackEventAt: eventAt,
        );
      }
    } else if (command == 'runtime.agent.delete') {
      final runtimeDid =
          _string(result['runtime_agent_did']) ?? _string(result['agent_did']);
      if (runtimeDid != null &&
          (_string(payload['state']) == 'archived' ||
              _string(result['active_state']) == 'archived')) {
        byDid.remove(runtimeDid);
      }
    } else if (command == 'daemon.delete') {
      final daemonDid =
          _string(result['daemon_agent_did']) ??
          _string(payload['daemon_agent_did']);
      if (daemonDid != null &&
          (_string(payload['state']) == 'archived' ||
              _string(result['active_state']) == 'archived')) {
        byDid.removeWhere(
          (_, agent) =>
              agent.agentDid == daemonDid || agent.daemonAgentDid == daemonDid,
        );
      }
    }
    final runs = payload['runs'];
    if (runs is List) {
      for (final item in runs) {
        final runPayload = _readMap(item);
        final runtimeDid = _string(runPayload['runtime_agent_did']);
        final runId = _string(runPayload['run_id']);
        if (runtimeDid == null || runId == null) {
          continue;
        }
        final current = byDid[runtimeDid];
        if (current == null || !current.isRuntime) {
          continue;
        }
        final run = AgentRunStatus.fromJson(runPayload);
        byDid[runtimeDid] = _mergeRuntimeRunStatus(current, run);
      }
    }
    return _stableAgentOrder(byDid.values);
  }

  List<PendingRuntimeCreation> _pendingCreationsAfterAgents(
    List<AgentSummary> agents,
  ) {
    return _pendingCreationsAfterControlPayloadAndAgents(
      state.pendingRuntimeCreations,
      const <String, Object?>{},
      agents,
    );
  }

  List<PendingRuntimeCreation> _pendingCreationsAfterControlPayloadAndAgents(
    List<PendingRuntimeCreation> current,
    Map<String, Object?> payload,
    List<AgentSummary> agents,
  ) {
    final completedRequestIds = <String>{};
    final result = _readMap(payload['result']);
    if (_string(result['command']) == 'runtime.agent.create') {
      final clientRequestId =
          _string(result['client_request_id']) ??
          _string(result['request_id']) ??
          _string(_readMap(result['args'])['client_request_id']);
      if (clientRequestId != null) {
        completedRequestIds.add(clientRequestId);
      }
    }

    final retained = <PendingRuntimeCreation>[];
    for (final pending in current) {
      if (completedRequestIds.contains(pending.requestId) ||
          _hasMatchingRuntimeAgent(agents, pending)) {
        _runtimeCreationTimeouts.remove(pending.requestId)?.cancel();
        continue;
      }
      retained.add(pending);
    }
    return retained;
  }

  Set<String> _pendingDeletionAfterAgents(List<AgentSummary> agents) {
    if (state.pendingDeletionAgentDids.isEmpty) {
      return state.pendingDeletionAgentDids;
    }
    final agentDids = agents.map((agent) => agent.agentDid).toSet();
    final retained = state.pendingDeletionAgentDids
        .where(agentDids.contains)
        .toSet();
    if (retained.length == state.pendingDeletionAgentDids.length) {
      return state.pendingDeletionAgentDids;
    }
    return retained;
  }

  Map<String, PendingDaemonUpgrade> _pendingDaemonUpgradesAfterAgents(
    List<AgentSummary> agents,
  ) {
    if (state.pendingDaemonUpgrades.isEmpty) {
      return state.pendingDaemonUpgrades;
    }
    final byDid = <String, AgentSummary>{
      for (final agent in agents.where((agent) => agent.isDaemon))
        agent.agentDid: agent,
    };
    final retained = <String, PendingDaemonUpgrade>{};
    for (final entry in state.pendingDaemonUpgrades.entries) {
      final daemon = byDid[entry.key];
      if (daemon == null ||
          _daemonAgentShowsUpgradeResolved(daemon) ||
          _daemonAgentShowsUpgradeFailed(daemon)) {
        continue;
      }
      retained[entry.key] = entry.value;
    }
    return retained;
  }

  Map<String, PendingDaemonUpgradeCancel> _cancellingDaemonUpgradesAfterAgents(
    List<AgentSummary> agents,
    Map<String, PendingDaemonUpgrade> nextPendingDaemonUpgrades,
  ) {
    if (state.cancellingDaemonUpgrades.isEmpty) {
      return state.cancellingDaemonUpgrades;
    }
    final byDid = <String, AgentSummary>{
      for (final agent in agents.where((agent) => agent.isDaemon))
        agent.agentDid: agent,
    };
    final retained = <String, PendingDaemonUpgradeCancel>{};
    for (final entry in state.cancellingDaemonUpgrades.entries) {
      final daemon = byDid[entry.key];
      if (!nextPendingDaemonUpgrades.containsKey(entry.key) ||
          daemon == null ||
          _daemonAgentShowsUpgradeResolved(daemon) ||
          _daemonAgentShowsUpgradeFailed(daemon)) {
        continue;
      }
      retained[entry.key] = entry.value;
    }
    return retained;
  }

  Map<String, String> _daemonUpgradeErrorsAfterAgents(
    List<AgentSummary> agents,
  ) {
    if (state.daemonUpgradeErrors.isEmpty &&
        state.pendingDaemonUpgrades.isEmpty) {
      return state.daemonUpgradeErrors;
    }
    var next = state.daemonUpgradeErrors;
    for (final daemon in agents.where((agent) => agent.isDaemon)) {
      if (_daemonAgentShowsUpgradeResolved(daemon)) {
        next = _withoutStringKey(next, daemon.agentDid);
        continue;
      }
      if (state.pendingDaemonUpgrades.containsKey(daemon.agentDid) &&
          _daemonAgentShowsUpgradeFailed(daemon)) {
        next = <String, String>{
          ...next,
          daemon.agentDid: _daemonUpgradeFailureMessage(<String, Object?>{
            'last_error_summary': daemon.latest.lastErrorSummary,
          }),
        };
      }
    }
    return next;
  }

  Map<String, DaemonUpgradeProgress> _daemonUpgradeProgressAfterAgents(
    List<AgentSummary> agents,
    Map<String, PendingDaemonUpgrade> nextPendingDaemonUpgrades,
  ) {
    if (state.daemonUpgradeProgress.isEmpty) {
      return state.daemonUpgradeProgress;
    }
    final byDid = <String, AgentSummary>{
      for (final agent in agents.where((agent) => agent.isDaemon))
        agent.agentDid: agent,
    };
    final retained = <String, DaemonUpgradeProgress>{};
    for (final entry in state.daemonUpgradeProgress.entries) {
      final daemon = byDid[entry.key];
      if (!nextPendingDaemonUpgrades.containsKey(entry.key) ||
          daemon == null ||
          _daemonAgentShowsUpgradeResolved(daemon) ||
          _daemonAgentShowsUpgradeFailed(daemon)) {
        continue;
      }
      retained[entry.key] = entry.value;
    }
    return retained;
  }

  AgentSummary _mergeRuntimeRunStatus(
    AgentSummary runtime,
    AgentRunStatus run,
  ) {
    final byRunId = <String, AgentRunStatus>{
      for (final existing in runtime.recentRuns) existing.runId: existing,
    };
    final existing = byRunId[run.runId];
    if (existing == null || _isNewerRunStatus(run, existing)) {
      byRunId[run.runId] = run;
    }
    final recentRuns = byRunId.values.toList()
      ..sort((a, b) {
        final aTime =
            a.updatedAt ??
            a.startedAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            b.updatedAt ??
            b.startedAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
    return AgentSummary(
      agentDid: runtime.agentDid,
      kind: runtime.kind,
      daemonAgentDid: runtime.daemonAgentDid,
      runtime: runtime.runtime,
      handle: runtime.handle,
      displayName: runtime.displayName,
      activeState: runtime.activeState,
      latest: runtime.latest,
      recentRuns: recentRuns.take(50).toList(),
    );
  }

  bool _isNewerRunStatus(AgentRunStatus next, AgentRunStatus current) {
    final nextTime = next.updatedAt ?? next.startedAt;
    final currentTime = current.updatedAt ?? current.startedAt;
    if (nextTime == null || currentTime == null) {
      return nextTime != null || currentTime == null;
    }
    return !nextTime.isBefore(currentTime);
  }

  AgentSummary _mergeAgent(
    AgentSummary? current, {
    required String agentDid,
    String? daemonDid,
    required AgentKind kind,
    required Map<String, Object?> payload,
    String? fallbackStatus,
    DateTime? fallbackEventAt,
    bool allowPayloadDisplayName = false,
  }) {
    final incomingEventAt = _agentStatusTimestamp(payload, fallbackEventAt);
    if (current != null && _isStaleAgentStatus(current, incomingEventAt)) {
      return current;
    }
    final resolvedAgentDid =
        _string(payload['agent_did']) ?? current?.agentDid ?? agentDid;
    final latest = normalizeAgentLatestStatusForKind(
      kind,
      _latestFromPayload(
        current?.latest,
        payload,
        fallbackStatus: fallbackStatus,
        fallbackEventAt: incomingEventAt,
      ),
    );
    return AgentSummary(
      agentDid: resolvedAgentDid,
      kind: kind,
      daemonAgentDid: kind == AgentKind.runtime
          ? (_string(payload['daemon_agent_did']) ??
                daemonDid ??
                current?.daemonAgentDid)
          : null,
      runtime: _string(payload['runtime']) ?? current?.runtime,
      handle: _string(payload['handle']) ?? current?.handle,
      displayName:
          (allowPayloadDisplayName ? _string(payload['display_name']) : null) ??
          current?.displayName ??
          AgentDisplayName.fallbackForKind(kind),
      activeState: current?.activeState ?? 'active',
      latest: latest,
      recentRuns: current?.recentRuns ?? const <AgentRunStatus>[],
    );
  }

  AgentLatestStatus _latestFromPayload(
    AgentLatestStatus? current,
    Map<String, Object?> payload, {
    String? fallbackStatus,
    DateTime? fallbackEventAt,
  }) {
    final merged = <String, Object?>{
      if (current != null) ...current.toJson(),
      'status':
          _string(payload['status']) ??
          fallbackStatus ??
          current?.status ??
          'ready',
      if (payload.containsKey('last_seen_at'))
        'last_seen_at': payload['last_seen_at'],
      if (!payload.containsKey('last_seen_at') && fallbackEventAt != null)
        'last_seen_at': fallbackEventAt.toUtc().toIso8601String(),
      if (payload.containsKey('version')) 'version': payload['version'],
      if (payload.containsKey('latest_version'))
        'latest_version': payload['latest_version'],
      if (payload.containsKey('min_supported_version'))
        'min_supported_version': payload['min_supported_version'],
      if (payload.containsKey('platform')) 'platform': payload['platform'],
      if (payload.containsKey('service')) 'service': payload['service'],
      if (payload.containsKey('needs_upgrade'))
        'needs_upgrade': payload['needs_upgrade'],
      if (payload.containsKey('needs_config'))
        'needs_config': payload['needs_config'],
      if (payload.containsKey('last_error_code'))
        'last_error_code': payload['last_error_code'],
      if (payload.containsKey('last_error_summary'))
        'last_error_summary': payload['last_error_summary'],
      if (payload.containsKey('diagnostics_summary'))
        'diagnostics_summary': payload['diagnostics_summary'],
    };
    return AgentLatestStatus.fromJson(merged);
  }
}

Set<String> _rememberControlEventId(Set<String> current, String eventId) {
  final remembered = <String>{...current, eventId};
  if (remembered.length <= 200) {
    return remembered;
  }
  return remembered.skip(remembered.length - 200).toSet();
}

DateTime? _agentStatusTimestamp(
  Map<String, Object?> payload,
  DateTime? fallbackEventAt,
) {
  return _dateTime(payload['last_seen_at']) ??
      _dateTime(payload['updated_at']) ??
      fallbackEventAt;
}

bool _isStaleAgentStatus(AgentSummary current, DateTime? incomingEventAt) {
  final currentAt = current.latest.lastSeenAt;
  if (currentAt == null || incomingEventAt == null) {
    return false;
  }
  return incomingEventAt.isBefore(currentAt);
}

List<AgentSummary> _stableAgentOrder(Iterable<AgentSummary> agents) {
  final ordered = agents.toList();
  ordered.sort((a, b) {
    if (a.kind != b.kind) {
      return a.isDaemon ? -1 : 1;
    }
    if (a.isRuntime) {
      final daemonCompare = _compareNullableText(
        a.daemonAgentDid,
        b.daemonAgentDid,
      );
      if (daemonCompare != 0) {
        return daemonCompare;
      }
    }
    final titleCompare = _agentSortTitle(a).compareTo(_agentSortTitle(b));
    if (titleCompare != 0) {
      return titleCompare;
    }
    final runtimeCompare = _compareNullableText(a.runtime, b.runtime);
    if (runtimeCompare != 0) {
      return runtimeCompare;
    }
    return a.agentDid.compareTo(b.agentDid);
  });
  return ordered;
}

String _agentSortTitle(AgentSummary agent) {
  final title = AgentDisplayName.title(agent).trim().toLowerCase();
  return title.isEmpty ? AgentDisplayName.fallbackForKind(agent.kind) : title;
}

int _compareNullableText(String? left, String? right) {
  final a = left?.trim().toLowerCase() ?? '';
  final b = right?.trim().toLowerCase() ?? '';
  return a.compareTo(b);
}

bool _daemonAcceptsControlCommands(AgentSummary daemon) {
  if (!daemon.isDaemon || daemon.activeState != 'active') {
    return false;
  }
  return switch (daemon.latest.status) {
    'ready' ||
    'needs_config' ||
    'needs_upgrade' ||
    'upgrading' ||
    'archiving' => true,
    _ => false,
  };
}

bool _canUnbindUnfinishedDaemonInstall(AgentSummary agent) {
  if (!agent.isDaemon || agent.activeState != 'active') {
    return false;
  }
  final status = agent.latest.status.trim().toLowerCase();
  if (status != 'registering') {
    return false;
  }
  return agent.latest.lastSeenAt == null;
}

bool _isMessageAgentRuntime(AgentSummary agent) {
  if (!agent.isRuntime) {
    return false;
  }
  final provider = MessageAgentRuntimeProviders.byRuntime(agent.runtime);
  if (provider == null || !provider.enabled) {
    return false;
  }
  final display = agent.displayName.trim().toLowerCase();
  final handle = agent.handle?.trim() ?? '';
  return display.contains('message agent') ||
      display.contains('消息处理') ||
      provider.matchesHandle(handle);
}

bool _isArchivedAgentPayload(Map<String, Object?> payload) {
  final activeState = _string(payload['active_state']);
  final status = _string(payload['status']);
  return activeState == 'archived' || status == 'archived';
}

Map<String, Object?> _daemonUpgradeStatusPayload(
  Map<String, Object?> result, {
  required String? payloadState,
}) {
  final payloadStatus = payloadState?.trim().toLowerCase();
  final resultStatus = _string(result['status'])?.toLowerCase();
  final isFinalSuccess = _isFinalDaemonUpgradeSuccess(<String, Object?>{
    'state': payloadState,
  }, result);
  final status = switch ((payloadStatus, resultStatus)) {
    (_, _) when _string(result['error_code']) == 'upgrade_cancelled' =>
      'needs_upgrade',
    (_, _) when result['error_code'] != null => 'failed',
    (_, _) when isFinalSuccess => 'ready',
    ('cancelled', _) || (_, 'cancelled') => 'needs_upgrade',
    ('failed', _) || (_, 'failed') => 'failed',
    ('upgrading', _) ||
    (_, 'in_progress') ||
    (_, 'restart_scheduled') => 'upgrading',
    ('ready', _) ||
    ('succeeded', _) ||
    (_, 'ready') ||
    (_, 'succeeded') => 'upgrading',
    (final state?, _) => state,
    (_, final state?) => state,
    _ => 'upgrading',
  };
  return <String, Object?>{
    ...result,
    'status': status,
    if (isFinalSuccess) 'needs_upgrade': false,
  };
}

bool _isFinalDaemonUpgradeSuccess(
  Map<String, Object?> payload,
  Map<String, Object?> result,
) {
  if (result['error_code'] != null) {
    return false;
  }
  final payloadState = _string(payload['state'])?.toLowerCase();
  final resultStatus = _string(result['status'])?.toLowerCase();
  if (payloadState == 'restart_scheduled' ||
      resultStatus == 'restart_scheduled' ||
      resultStatus == 'in_progress') {
    return false;
  }
  final hasVersionEvidence =
      _string(result['version']) != null ||
      _string(result['current_version']) != null;
  if (!hasVersionEvidence) {
    return false;
  }
  return payloadState == 'ready' ||
      payloadState == 'succeeded' ||
      resultStatus == 'ready' ||
      resultStatus == 'succeeded';
}

String _daemonUpgradeFailureMessage(Map<String, Object?> result) {
  final summary = _string(result['last_error_summary']);
  if (summary == null) {
    return '升级没有完成，请检查网络后重试。';
  }
  final normalized = summary.toLowerCase();
  final looksLikeDownload =
      normalized.contains('download daemon package') ||
      normalized.contains('timed out') ||
      normalized.contains('timeout') ||
      normalized.contains('network') ||
      normalized.contains('connection');
  if (!looksLikeDownload) {
    return summary;
  }
  return '安装包下载失败，请检查网络后重试。$summary';
}

bool _daemonStatusShowsUpgradeResolved(Map<String, Object?> payload) {
  final daemon = _readMap(payload['daemon']);
  if (daemon.isEmpty) {
    return false;
  }
  final status = _string(daemon['status'])?.toLowerCase();
  final needsUpgrade = daemon['needs_upgrade'];
  return needsUpgrade == false && (status == null || status == 'ready');
}

bool _daemonAgentShowsUpgradeResolved(AgentSummary daemon) {
  if (!daemon.isDaemon) {
    return false;
  }
  final status = daemon.latest.status.trim().toLowerCase();
  return !daemon.latest.needsUpgrade &&
      status != 'upgrading' &&
      status != 'restart_scheduled';
}

bool _daemonAgentShowsUpgradeFailed(AgentSummary daemon) {
  if (!daemon.isDaemon) {
    return false;
  }
  final status = daemon.latest.status.trim().toLowerCase();
  return status == 'failed' ||
      status == 'error' ||
      status == 'gateway_error' ||
      daemon.latest.lastErrorSummary != null;
}

bool _commandIdMatches(String? payloadCommandId, String expectedCommandId) {
  return payloadCommandId == null || payloadCommandId == expectedCommandId;
}

Map<String, PendingDaemonUpgrade> _acknowledgePendingDaemonUpgrade(
  Map<String, PendingDaemonUpgrade> input,
  String daemonDid,
  String? commandId,
) {
  final pending = input[daemonDid];
  if (pending == null) {
    return input;
  }
  if (commandId != null && commandId != pending.commandId) {
    return input;
  }
  final acknowledged = pending.acknowledge();
  if (identical(acknowledged, pending)) {
    return input;
  }
  return <String, PendingDaemonUpgrade>{...input, daemonDid: acknowledged};
}

String _daemonUpgradeCancelFailureMessage(Map<String, Object?> result) {
  final errorCode = _string(result['error_code']);
  if (errorCode == 'upgrade_not_cancellable' ||
      errorCode == 'upgrade_cancel_unavailable' ||
      _string(result['status']) == 'not_cancellable') {
    return '当前升级已经进入重启阶段，无法取消。请稍后刷新状态确认结果。';
  }
  final summary = _string(result['last_error_summary']);
  if (summary != null && summary.trim().isNotEmpty) {
    return summary;
  }
  return '取消升级失败，请刷新状态后重试。';
}

Map<String, DateTime> _withoutKey(Map<String, DateTime> input, String key) {
  if (!input.containsKey(key)) {
    return input;
  }
  return <String, DateTime>{
    for (final entry in input.entries)
      if (entry.key != key) entry.key: entry.value,
  };
}

Map<K, V> _withoutMapKey<K, V>(Map<K, V> input, K key) {
  if (!input.containsKey(key)) {
    return input;
  }
  return <K, V>{
    for (final entry in input.entries)
      if (entry.key != key) entry.key: entry.value,
  };
}

Map<String, String> _withoutStringKey(Map<String, String> input, String key) {
  if (!input.containsKey(key)) {
    return input;
  }
  return <String, String>{
    for (final entry in input.entries)
      if (entry.key != key) entry.key: entry.value,
  };
}

Map<String, DaemonUpgradeProgress> _withoutDaemonUpgradeProgressKey(
  Map<String, DaemonUpgradeProgress> input,
  String key,
) {
  if (!input.containsKey(key)) {
    return input;
  }
  return <String, DaemonUpgradeProgress>{
    for (final entry in input.entries)
      if (entry.key != key) entry.key: entry.value,
  };
}

Set<String> _withoutSetValue(Set<String> input, String value) {
  if (!input.contains(value)) {
    return input;
  }
  return <String>{
    for (final item in input)
      if (item != value) item,
  };
}

Set<String> _withSetValue(Set<String> input, String value) {
  if (input.contains(value)) {
    return input;
  }
  return <String>{...input, value};
}

Set<String> _withoutStringKeys(Set<String> input, Set<String> keys) {
  if (keys.isEmpty || !keys.any(input.contains)) {
    return input;
  }
  return <String>{
    for (final item in input)
      if (!keys.contains(item)) item,
  };
}

List<PendingRuntimeCreation> _upsertPendingRuntimeCreation(
  List<PendingRuntimeCreation> input,
  PendingRuntimeCreation pending,
) {
  return <PendingRuntimeCreation>[
    for (final item in input)
      if (item.requestId != pending.requestId &&
          !_samePendingRuntimeTarget(item, pending))
        item,
    pending,
  ];
}

List<PendingRuntimeCreation> _markPendingRuntimeCreationWaiting(
  List<PendingRuntimeCreation> input,
  String requestId,
) {
  var changed = false;
  final next = <PendingRuntimeCreation>[
    for (final item in input)
      if (item.requestId == requestId)
        () {
          changed = true;
          return item.copyWith(
            state: PendingRuntimeCreationState.waitingForStatus,
          );
        }()
      else
        item,
  ];
  return changed ? next : input;
}

List<PendingRuntimeCreation> _removePendingRuntimeCreation(
  List<PendingRuntimeCreation> input,
  String requestId,
) {
  if (!input.any((item) => item.requestId == requestId)) {
    return input;
  }
  return <PendingRuntimeCreation>[
    for (final item in input)
      if (item.requestId != requestId) item,
  ];
}

bool _samePendingRuntimeTarget(
  PendingRuntimeCreation left,
  PendingRuntimeCreation right,
) {
  return left.daemonAgentDid == right.daemonAgentDid &&
      _normalizedAgentHandle(left.handle) ==
          _normalizedAgentHandle(right.handle);
}

bool _hasMatchingRuntimeAgent(
  List<AgentSummary> agents,
  PendingRuntimeCreation pending,
) {
  return agents.any((agent) {
    if (!agent.isRuntime || agent.daemonAgentDid != pending.daemonAgentDid) {
      return false;
    }
    final agentHandle = _normalizedAgentHandle(agent.handle);
    final pendingHandle = _normalizedAgentHandle(pending.handle);
    if (agentHandle != null && pendingHandle != null) {
      return agentHandle == pendingHandle;
    }
    final agentName = agent.displayName.trim();
    return agentName.isNotEmpty && agentName == pending.displayName.trim();
  });
}

String? _normalizedAgentHandle(String? value) {
  final text = value?.trim().toLowerCase();
  return text == null || text.isEmpty ? null : text;
}

Map<String, Object?> _readMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return value.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
}

String? _string(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString().trim() ?? '');
}

double? _double(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString().trim() ?? '');
}

String _defaultAppInstanceId(String credentialName) {
  final normalized = credentialName.trim().replaceAll(
    RegExp(r'[^a-zA-Z0-9_.-]+'),
    '_',
  );
  return normalized.isEmpty ? 'app_1' : 'app_$normalized';
}

String _agentCacheOwner(SessionIdentity session) {
  final handle = session.handle?.trim().toLowerCase();
  if (handle != null && handle.isNotEmpty) {
    return 'controller-handle:$handle';
  }
  return 'controller-did:${session.did.trim()}';
}

DateTime? _dateTime(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '')?.toUtc();
}

String _agentErrorMessage(Object error) {
  final reason = _agentErrorReason(error);
  if (reason == 'daemon_controller_scope_mismatch' ||
      reason == 'agent_controller_scope_mismatch') {
    return '这台电脑已经绑定到另一个 handle 的 Daemon。请使用对应 handle 管理，或先卸载本机 Daemon 后重新安装。';
  }
  if (reason == 'controller_handle_mismatch') {
    return '当前客户端身份和登录 handle 不一致，请切换到正确账号后重新复制安装命令。';
  }
  if (reason == 'controller_handle_required') {
    return '当前账号没有可用 handle，暂时不能生成 Daemon 安装命令。';
  }
  if (reason == 'controller_scope_missing') {
    return '安装命令缺少账号归属信息，请重新复制最新的 Daemon 安装命令。';
  }
  if (reason == 'used') {
    return '这条安装命令已经使用过，请重新复制最新的 Daemon 安装命令。';
  }
  switch (classifyAppError(error)) {
    case AppErrorKind.authentication:
      return '登录状态已失效，请重新登录后再查看智能体。';
    case AppErrorKind.timeout:
      return '请求超时，请稍后重试。';
    case AppErrorKind.networkUnavailable:
      return '网络连接暂时不可用，已保留当前数据。';
    case AppErrorKind.didNotFoundOrRevoked:
    case AppErrorKind.other:
      break;
  }
  return '智能体信息暂时无法加载，请稍后重试。';
}

String? _agentErrorReason(Object error) {
  if (error is AwikiOnboardingUtilityError) {
    final data = error.data;
    if (data is Map) {
      final reason = data['reason']?.toString().trim();
      if (reason != null && reason.isNotEmpty) {
        return reason;
      }
    }
    final message = error.message.trim();
    if (message.isNotEmpty) {
      return _knownAgentErrorReason(message);
    }
  }
  return _knownAgentErrorReason(error.toString());
}

String? _knownAgentErrorReason(String raw) {
  final normalized = raw.toLowerCase();
  const reasons = <String>{
    'daemon_controller_scope_mismatch',
    'agent_controller_scope_mismatch',
    'controller_handle_required',
    'controller_handle_mismatch',
    'controller_scope_missing',
    'controller_scope_mismatch',
    'scope_mismatch',
    'used',
  };
  for (final reason in reasons) {
    final pattern = RegExp(
      '(^|[^a-z0-9_])${RegExp.escape(reason)}([^a-z0-9_]|\$)',
    );
    if (pattern.hasMatch(normalized)) {
      return reason;
    }
  }
  return null;
}

String _agentStatusRefreshErrorMessage(Object error) {
  switch (classifyAppError(error)) {
    case AppErrorKind.authentication:
      return '登录状态已失效，请重新登录后再刷新代理状态。';
    case AppErrorKind.timeout:
      return '刷新状态超时，当前数据已保留。';
    case AppErrorKind.networkUnavailable:
      return '网络连接暂时不可用，当前数据已保留。';
    case AppErrorKind.didNotFoundOrRevoked:
    case AppErrorKind.other:
      break;
  }
  return '状态刷新请求发送失败，请稍后再试。';
}

final agentsProvider = StateNotifierProvider<AgentsController, AgentsState>(
  (ref) => AgentsController(ref),
);
