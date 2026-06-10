import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/models/product_local_models.dart';
import '../../data/agent/user_service_agent_inventory_adapter.dart';
import '../../domain/entities/agent/agent_bootstrap.dart';
import '../../domain/entities/agent/agent_control_payloads.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/agent/agent_status.dart';
import '../../domain/entities/agent/install_command.dart';
import '../app_shell/providers/session_provider.dart';

class AgentsState {
  const AgentsState({
    this.agents = const <AgentSummary>[],
    this.selectedAgentDid,
    this.isLoading = false,
    this.isActing = false,
    this.installCommand,
    this.error,
    this.lastRefreshAtByDaemon = const <String, DateTime>{},
    this.pendingStatusQueryAtByDaemon = const <String, DateTime>{},
    this.seenControlEventIds = const <String>{},
  });

  final List<AgentSummary> agents;
  final String? selectedAgentDid;
  final bool isLoading;
  final bool isActing;
  final InstallCommand? installCommand;
  final String? error;
  final Map<String, DateTime> lastRefreshAtByDaemon;
  final Map<String, DateTime> pendingStatusQueryAtByDaemon;
  final Set<String> seenControlEventIds;

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

  List<AgentSummary> get daemonAgents =>
      agents.where((agent) => agent.isDaemon).toList();

  List<AgentSummary> runtimesFor(String daemonDid) => agents
      .where((agent) => agent.isRuntime && agent.daemonAgentDid == daemonDid)
      .toList();

  bool isStatusQueryPending(String daemonDid) {
    return pendingStatusQueryAtByDaemon.containsKey(daemonDid);
  }

  AgentsState copyWith({
    List<AgentSummary>? agents,
    String? selectedAgentDid,
    bool clearSelection = false,
    bool? isLoading,
    bool? isActing,
    InstallCommand? installCommand,
    bool clearInstallCommand = false,
    String? error,
    bool clearError = false,
    Map<String, DateTime>? lastRefreshAtByDaemon,
    Map<String, DateTime>? pendingStatusQueryAtByDaemon,
    Set<String>? seenControlEventIds,
  }) {
    return AgentsState(
      agents: agents ?? this.agents,
      selectedAgentDid: clearSelection
          ? null
          : (selectedAgentDid ?? this.selectedAgentDid),
      isLoading: isLoading ?? this.isLoading,
      isActing: isActing ?? this.isActing,
      installCommand: clearInstallCommand
          ? null
          : (installCommand ?? this.installCommand),
      error: clearError ? null : (error ?? this.error),
      lastRefreshAtByDaemon:
          lastRefreshAtByDaemon ?? this.lastRefreshAtByDaemon,
      pendingStatusQueryAtByDaemon:
          pendingStatusQueryAtByDaemon ?? this.pendingStatusQueryAtByDaemon,
      seenControlEventIds: seenControlEventIds ?? this.seenControlEventIds,
    );
  }
}

class AgentsController extends StateNotifier<AgentsState> {
  AgentsController(this.ref) : super(const AgentsState());

  final Ref ref;
  final Map<String, Timer> _statusQueryTimeouts = <String, Timer>{};

  Future<void> load() async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      state = const AgentsState();
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    await _loadCached(session.did);
    try {
      final agents = await ref.read(agentControlServiceProvider).listAgents();
      await _saveCache(session.did, agents);
      state = state.copyWith(
        agents: agents,
        selectedAgentDid: _nextSelection(agents),
        isLoading: false,
        clearError: true,
      );
      for (final daemon in agents.where((agent) => agent.isDaemon)) {
        if (_shouldAutoRefresh(daemon)) {
          await refreshDaemonStatus(daemon.agentDid, fromAutoLoad: true);
        }
      }
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: _agentErrorMessage(error),
      );
    }
  }

  void select(String agentDid) {
    state = state.copyWith(selectedAgentDid: agentDid);
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
    await _act(() async {
      final command = await ref
          .read(agentControlServiceProvider)
          .createDaemonInstallCommand(
            controllerDid: session.did,
            clientPlatform: awikiClientPlatform(),
          );
      state = state.copyWith(installCommand: command, clearError: true);
    });
  }

  Future<void> refreshDaemonStatus(
    String daemonDid, {
    bool fromAutoLoad = false,
  }) async {
    final last = state.lastRefreshAtByDaemon[daemonDid];
    final now = DateTime.now().toUtc();
    if (last != null && now.difference(last) < const Duration(seconds: 10)) {
      if (!fromAutoLoad) {
        state = state.copyWith(error: '10 秒内只能刷新一次。');
      }
      return;
    }
    if (!fromAutoLoad) {
      state = state.copyWith(
        pendingStatusQueryAtByDaemon: <String, DateTime>{
          ...state.pendingStatusQueryAtByDaemon,
          daemonDid: now,
        },
        clearError: true,
      );
      _scheduleStatusQueryTimeout(daemonDid);
    }
    state = state.copyWith(isActing: true, clearError: true);
    try {
      await ref
          .read(agentControlServiceProvider)
          .refreshDaemonStatus(daemonDid);
      state = state.copyWith(
        isActing: false,
        lastRefreshAtByDaemon: <String, DateTime>{
          ...state.lastRefreshAtByDaemon,
          daemonDid: now,
        },
        clearError: true,
      );
    } catch (error) {
      _statusQueryTimeouts.remove(daemonDid)?.cancel();
      final nextPending = fromAutoLoad
          ? state.pendingStatusQueryAtByDaemon
          : _withoutKey(state.pendingStatusQueryAtByDaemon, daemonDid);
      state = state.copyWith(
        isActing: false,
        pendingStatusQueryAtByDaemon: nextPending,
        error: fromAutoLoad ? state.error : _agentErrorMessage(error),
      );
    }
  }

  Future<void> createHermesRuntime(String daemonDid) async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      state = state.copyWith(error: '请先登录。');
      return;
    }
    await _act(() async {
      await ref
          .read(agentControlServiceProvider)
          .createHermesRuntime(
            daemonAgentDid: daemonDid,
            controllerDid: session.did,
          );
      await load();
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
    final resolvedAppInstanceId =
        appInstanceId ?? _defaultAppInstanceId(session.credentialName);
    await _act(() async {
      final subkeyPackage =
          userSubkeyPackage ??
          await ref
              .read(identityCorePortProvider)
              .ensureDaemonSubkeyPackage(session.credentialName);
      await ref
          .read(agentControlServiceProvider)
          .ensureMessageAgentBootstrap(
            daemonAgentDid: daemonDid,
            controllerDid: session.did,
            appInstanceId: resolvedAppInstanceId,
            userSubkeyPackage: subkeyPackage,
            userHandle: session.handle,
          );
    });
  }

  Future<void> resetRuntimeSession(AgentSummary runtime) async {
    final daemonDid = runtime.daemonAgentDid;
    if (daemonDid == null) {
      return;
    }
    await _act(() {
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
    await _act(() {
      return ref
          .read(agentControlServiceProvider)
          .retryRun(
            daemonAgentDid: daemonDid,
            runtimeAgentDid: runtime.agentDid,
            runId: normalizedRunId,
          );
    });
  }

  Future<void> upgradeDaemon(String daemonDid) async {
    await _act(() {
      return ref.read(agentControlServiceProvider).upgradeDaemon(daemonDid);
    });
  }

  Future<void> unbindSelected() async {
    final selected = state.selectedAgent;
    if (selected == null) {
      return;
    }
    await _act(() async {
      await ref
          .read(agentControlServiceProvider)
          .unbindAgent(selected.agentDid);
      await load();
    });
  }

  Future<void> renameSelected(String displayName) async {
    final selected = state.selectedAgent;
    if (selected == null) {
      return;
    }
    await _act(() async {
      await ref
          .read(agentControlServiceProvider)
          .updateDisplayName(
            agentDid: selected.agentDid,
            displayName: displayName,
          );
      await load();
    });
  }

  void clearInstallCommand() {
    state = state.copyWith(clearInstallCommand: true);
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
    final daemonDid =
        _string(payload['daemon_agent_did']) ??
        _string(_readMap(payload['daemon'])['agent_did']);
    final nextPending = daemonDid == null
        ? state.pendingStatusQueryAtByDaemon
        : _withoutKey(state.pendingStatusQueryAtByDaemon, daemonDid);
    if (daemonDid != null) {
      _statusQueryTimeouts.remove(daemonDid)?.cancel();
    }
    state = state.copyWith(
      agents: merged,
      selectedAgentDid: _nextSelection(merged),
      pendingStatusQueryAtByDaemon: nextPending,
      seenControlEventIds: eventId == null
          ? state.seenControlEventIds
          : _rememberControlEventId(state.seenControlEventIds, eventId),
      clearError: true,
    );
    final session = ref.read(sessionProvider).session;
    if (session != null) {
      unawaited(_saveCache(session.did, merged));
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    state = state.copyWith(isActing: true, clearError: true);
    try {
      await action();
      state = state.copyWith(isActing: false, clearError: true);
    } catch (error) {
      state = state.copyWith(isActing: false, error: _agentErrorMessage(error));
    }
  }

  void _scheduleStatusQueryTimeout(String daemonDid) {
    _statusQueryTimeouts.remove(daemonDid)?.cancel();
    _statusQueryTimeouts[daemonDid] = Timer(const Duration(seconds: 10), () {
      _statusQueryTimeouts.remove(daemonDid);
      if (!mounted ||
          !state.pendingStatusQueryAtByDaemon.containsKey(daemonDid)) {
        return;
      }
      state = state.copyWith(
        pendingStatusQueryAtByDaemon: _withoutKey(
          state.pendingStatusQueryAtByDaemon,
          daemonDid,
        ),
        error: '未收到代理响应',
      );
    });
  }

  @override
  void dispose() {
    for (final timer in _statusQueryTimeouts.values) {
      timer.cancel();
    }
    _statusQueryTimeouts.clear();
    super.dispose();
  }

  Future<void> _loadCached(String ownerDid) async {
    final cached = await ref
        .read(productLocalStoreProvider)
        .loadAgentStates(ownerDid: ownerDid);
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
    if (agents.isNotEmpty) {
      state = state.copyWith(
        agents: agents,
        selectedAgentDid: _nextSelection(agents),
      );
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
        );
      }
    } else if (command == 'daemon.upgrade') {
      final daemonDid =
          _string(result['daemon_agent_did']) ??
          _string(payload['daemon_agent_did']);
      if (daemonDid != null) {
        byDid[daemonDid] = _mergeAgent(
          byDid[daemonDid],
          agentDid: daemonDid,
          kind: AgentKind.daemon,
          payload: <String, Object?>{
            ...result,
            'agent_did': daemonDid,
            'status': _string(payload['state']) ?? _string(result['status']),
          },
          fallbackStatus: _string(payload['state']),
          fallbackEventAt: eventAt,
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
    final ordered = byDid.values.toList()
      ..sort((a, b) {
        if (a.kind != b.kind) {
          return a.isDaemon ? -1 : 1;
        }
        return a.displayName.compareTo(b.displayName);
      });
    return ordered;
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
  }) {
    final incomingEventAt = _agentStatusTimestamp(payload, fallbackEventAt);
    if (current != null && _isStaleAgentStatus(current, incomingEventAt)) {
      return current;
    }
    final resolvedAgentDid =
        _string(payload['agent_did']) ?? current?.agentDid ?? agentDid;
    final latest = _latestFromPayload(
      current?.latest,
      payload,
      fallbackStatus: fallbackStatus,
      fallbackEventAt: incomingEventAt,
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
          _string(payload['display_name']) ??
          current?.displayName ??
          (kind == AgentKind.daemon ? '代理 1' : 'Hermes'),
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

Map<String, DateTime> _withoutKey(Map<String, DateTime> input, String key) {
  if (!input.containsKey(key)) {
    return input;
  }
  return <String, DateTime>{
    for (final entry in input.entries)
      if (entry.key != key) entry.key: entry.value,
  };
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

String _defaultAppInstanceId(String credentialName) {
  final normalized = credentialName.trim().replaceAll(
    RegExp(r'[^a-zA-Z0-9_.-]+'),
    '_',
  );
  return normalized.isEmpty ? 'app_1' : 'app_$normalized';
}

DateTime? _dateTime(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '')?.toUtc();
}

String _agentErrorMessage(Object error) {
  final raw = error.toString();
  final normalized = raw.toLowerCase();
  final compact = normalized.replaceAll(RegExp(r'\s+'), '');
  if (normalized.contains('missing or invalid authorization header') ||
      compact.contains('http401') ||
      normalized.contains('invalid token') ||
      normalized.contains('empty token')) {
    return '登录状态已失效，请重新登录后再查看智能体。';
  }
  if (normalized.contains('timeoutexception') ||
      normalized.contains('timed out')) {
    return '请求超时，请检查网络后重试。';
  }
  if (normalized.contains('connection refused') ||
      normalized.contains('failed host lookup') ||
      normalized.contains('network is unreachable')) {
    return '暂时无法连接后端服务，请检查网络或服务地址后重试。';
  }
  return '智能体信息暂时无法加载，请稍后重试。';
}

final agentsProvider = StateNotifierProvider<AgentsController, AgentsState>(
  (ref) => AgentsController(ref),
);
