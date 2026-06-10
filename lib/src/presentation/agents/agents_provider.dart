import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/models/product_local_models.dart';
import '../../data/agent/user_service_agent_inventory_adapter.dart';
import '../../domain/entities/agent/agent_control_payloads.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/agent/agent_status.dart';
import '../../domain/entities/agent/install_command.dart';
import '../../domain/entities/session_identity.dart';
import '../app_shell/providers/session_provider.dart';
import 'agent_display_name.dart';

const agentStatusQueryTimeout = Duration(seconds: 10);
const agentStatusRefreshMinimumIndicatorDuration = Duration(milliseconds: 1500);

class AgentsState {
  const AgentsState({
    this.agents = const <AgentSummary>[],
    this.selectedAgentDid,
    this.isLoading = false,
    this.isActing = false,
    this.installCommand,
    this.error,
    this.pendingStatusQueryAtByDaemon = const <String, DateTime>{},
    this.seenControlEventIds = const <String>{},
  });

  final List<AgentSummary> agents;
  final String? selectedAgentDid;
  final bool isLoading;
  final bool isActing;
  final InstallCommand? installCommand;
  final String? error;
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
    final daemon = agent.isDaemon ? agent : daemonForRuntime(agent);
    return daemon != null && _daemonAcceptsControlCommands(daemon);
  }

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
  final Map<String, Timer> _statusQueryClearTimers = <String, Timer>{};

  Future<void> load() async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      state = const AgentsState();
      return;
    }
    final cacheOwner = _agentCacheOwner(session);
    state = state.copyWith(isLoading: true, clearError: true);
    await _loadCached(cacheOwner);
    try {
      final agents = _stableAgentOrder(
        await ref.read(agentControlServiceProvider).listAgents(),
      );
      await _saveCache(cacheOwner, agents);
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
    final now = DateTime.now().toUtc();
    if (state.isStatusQueryPending(daemonDid)) {
      return;
    }
    if (!fromAutoLoad) {
      _statusQueryClearTimers.remove(daemonDid)?.cancel();
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
      state = state.copyWith(isActing: false, clearError: true);
    } catch (error) {
      _statusQueryTimeouts.remove(daemonDid)?.cancel();
      _statusQueryClearTimers.remove(daemonDid)?.cancel();
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

  Future<void> deleteSelected() async {
    final selected = state.selectedAgent;
    if (selected == null) {
      return;
    }
    final daemon = selected.isDaemon
        ? selected
        : state.daemonForRuntime(selected);
    if (daemon == null || !_daemonAcceptsControlCommands(daemon)) {
      state = state.copyWith(error: '代理当前不可达，暂时不能删除。');
      return;
    }
    await _act(() async {
      if (selected.isDaemon) {
        await ref
            .read(agentControlServiceProvider)
            .deleteDaemon(selected.agentDid);
      } else {
        await ref
            .read(agentControlServiceProvider)
            .deleteRuntimeAgent(
              daemonAgentDid: daemon.agentDid,
              runtimeAgentDid: selected.agentDid,
            );
      }
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
    final nextPending = _pendingAfterStatusPayload(daemonDid);
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
      unawaited(_saveCache(_agentCacheOwner(session), merged));
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
    _statusQueryTimeouts[daemonDid] = Timer(agentStatusQueryTimeout, () {
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

  @override
  void dispose() {
    for (final timer in _statusQueryTimeouts.values) {
      timer.cancel();
    }
    _statusQueryTimeouts.clear();
    for (final timer in _statusQueryClearTimers.values) {
      timer.cancel();
    }
    _statusQueryClearTimers.clear();
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
    final ordered = _stableAgentOrder(agents);
    if (ordered.isNotEmpty) {
      state = state.copyWith(
        agents: ordered,
        selectedAgentDid: _nextSelection(ordered),
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

bool _isArchivedAgentPayload(Map<String, Object?> payload) {
  final activeState = _string(payload['active_state']);
  final status = _string(payload['status']);
  return activeState == 'archived' || status == 'archived';
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
