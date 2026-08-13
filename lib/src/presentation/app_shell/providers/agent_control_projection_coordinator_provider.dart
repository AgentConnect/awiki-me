// [INPUT]: Realtime Agent control hints, committed control-message streams, Agent inventory, and SessionEpoch.
// [OUTPUT]: One deduplicated, session-fenced projection into Agent, chat, inbox, and terminal-notification state.
// [POS]: App-wide Agent control event owner; realtime accelerates delivery while committed Core state guarantees convergence.

import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_services.dart';
import '../../../application/agent/agent_control_status_store.dart';
import '../../../core/performance_logger.dart';
import '../../../domain/entities/agent/agent_control_payloads.dart';
import '../../../domain/entities/agent/agent_terminal_notification.dart';
import '../../agents/agent_inbox_provider.dart';
import '../../agents/agents_provider.dart';
import '../../agents/personal_agent_feature_visibility.dart';
import '../../chat/chat_provider.dart';
import 'agent_terminal_notification_provider.dart';
import 'session_provider.dart';

const agentControlProjectionRetryBaseDelay = Duration(milliseconds: 150);
const agentControlProjectionRetryMaxDelay = Duration(seconds: 3);

class AgentControlProjectionCoordinator
    extends StateNotifier<AgentTerminalNotification?> {
  AgentControlProjectionCoordinator(this.ref) : super(null) {
    _start();
  }

  static const int _maxProjectedEventKeys = 1024;

  final Ref ref;
  final LinkedHashSet<String> _projectedEventKeys = LinkedHashSet<String>();
  final Map<String, _AgentControlProjectionSubscription> _subscriptions =
      <String, _AgentControlProjectionSubscription>{};
  final Map<String, int> _subscriptionTokens = <String, int>{};
  final Map<String, int> _retryAttempts = <String, int>{};
  final Map<String, Timer> _retryTimers = <String, Timer>{};

  ProviderSubscription<SessionState>? _sessionSubscription;
  ProviderSubscription<AgentsState>? _agentsSubscription;
  int _nextSubscriptionToken = 0;
  bool _disposed = false;
  _AgentControlProjectionFence? _activeFence;

  void _start() {
    _sessionSubscription = ref.listen<SessionState>(
      sessionProvider,
      (_, __) => _reconcileSubscriptions(),
    );
    _agentsSubscription = ref.listen<AgentsState>(
      agentsProvider,
      (_, __) => _reconcileSubscriptions(),
    );
    _reconcileSubscriptions();
  }

  void applyRealtimePayload(Map<String, Object?> payload) {
    if (_disposed || ref.read(sessionProvider).activeEpoch == null) {
      return;
    }
    final daemonDid = _payloadDaemonDid(payload);
    _projectPresentation(
      payload,
      eventKey: _projectionEventKey(
        daemonDid: daemonDid,
        payload: payload,
        fallback: null,
      ),
    );
  }

  void _reconcileSubscriptions() {
    if (_disposed) {
      return;
    }
    final store = ref.read(agentControlStatusStoreProvider);
    final fence = _AgentControlProjectionFence.capture(
      ref.read(sessionProvider),
    );
    if (_activeFence != fence) {
      _activeFence = fence;
      _projectedEventKeys.clear();
      ref.read(agentTerminalNotificationDeduplicatorProvider).clear();
    }
    if (store is! AgentControlEventStore || fence == null) {
      _cancelAllSubscriptions();
      _projectedEventKeys.clear();
      return;
    }
    final eventStore = store as AgentControlEventStore;
    final daemonDids = ref
        .read(agentsProvider)
        .agents
        .where((agent) => agent.isDaemon)
        .map((agent) => agent.agentDid.trim())
        .where((did) => did.isNotEmpty)
        .toSet();

    for (final daemonDid in _subscriptions.keys.toList(growable: false)) {
      final current = _subscriptions[daemonDid];
      if (!daemonDids.contains(daemonDid) || current?.fence != fence) {
        _cancelSubscription(daemonDid);
      }
    }
    for (final daemonDid in _retryTimers.keys.toList(growable: false)) {
      if (!daemonDids.contains(daemonDid)) {
        _retryTimers.remove(daemonDid)?.cancel();
        _retryAttempts.remove(daemonDid);
      }
    }
    for (final daemonDid in daemonDids) {
      if (_subscriptions.containsKey(daemonDid) ||
          _subscriptionTokens.containsKey(daemonDid)) {
        continue;
      }
      _startSubscription(
        eventStore: eventStore,
        daemonDid: daemonDid,
        fence: fence,
      );
    }
  }

  void _startSubscription({
    required AgentControlEventStore eventStore,
    required String daemonDid,
    required _AgentControlProjectionFence fence,
  }) {
    _retryTimers.remove(daemonDid)?.cancel();
    final token = ++_nextSubscriptionToken;
    _subscriptionTokens[daemonDid] = token;
    final subscription = eventStore
        .watchDaemonControlEvents(daemonAgentDid: daemonDid)
        .listen(
          (event) {
            if (!_isCurrentSubscription(daemonDid, token, fence) ||
                event.daemonAgentDid.trim() != daemonDid) {
              return;
            }
            _retryAttempts.remove(daemonDid);
            _applyCommittedEvent(event);
          },
          onError: (Object error, StackTrace stackTrace) {
            _handleSubscriptionTerminated(
              daemonDid: daemonDid,
              token: token,
              fence: fence,
              error: error,
            );
          },
          onDone: () {
            _handleSubscriptionTerminated(
              daemonDid: daemonDid,
              token: token,
              fence: fence,
            );
          },
          cancelOnError: true,
        );
    if (_subscriptionTokens[daemonDid] != token) {
      unawaited(subscription.cancel());
      return;
    }
    _subscriptions[daemonDid] = _AgentControlProjectionSubscription(
      token: token,
      fence: fence,
      subscription: subscription,
    );
    unawaited(
      _replayLatestDaemonStatus(
        daemonDid: daemonDid,
        token: token,
        fence: fence,
      ),
    );
  }

  Future<void> _replayLatestDaemonStatus({
    required String daemonDid,
    required int token,
    required _AgentControlProjectionFence fence,
  }) async {
    try {
      final payload = await ref
          .read(agentControlStatusStoreProvider)
          .findLatestDaemonStatusPayload(daemonAgentDid: daemonDid)
          .timeout(agentStatusPayloadLookupTimeout);
      if (payload == null || !_isCurrentSubscription(daemonDid, token, fence)) {
        return;
      }
      _applyCommittedEvent(
        AgentControlEvent(
          messageId: 'latest-daemon-status:$daemonDid',
          daemonAgentDid: daemonDid,
          payload: payload,
          isReplay: true,
        ),
      );
    } on Object {
      // The committed patch stream remains primary; latest-status replay is a
      // best-effort bootstrap for stores that have not emitted their reset yet.
    }
  }

  void _applyCommittedEvent(AgentControlEvent event) {
    ref.read(agentsProvider.notifier).applyCommittedControlEvent(event);
    _projectPresentation(
      event.payload,
      eventKey: _projectionEventKey(
        daemonDid: event.daemonAgentDid,
        payload: event.payload,
        fallback: event.messageId,
      ),
    );
  }

  void _projectPresentation(
    Map<String, Object?> payload, {
    required String? eventKey,
  }) {
    final schema = payload['schema']?.toString().trim();
    if (!AgentControlPayloads.isSystemSchema(schema)) {
      return;
    }
    if (eventKey != null && !_rememberProjectedEvent(eventKey)) {
      return;
    }
    ref.read(agentInboxProvider.notifier).applyControlPayload(payload);
    final chat = ref.read(chatThreadsProvider.notifier);
    chat.applyAgentRunStatusPayload(payload);
    chat.applyPersonalAgentControlPayload(payload);

    final terminalNotification = ref
        .read(agentTerminalNotificationDeduplicatorProvider)
        .acceptStatus(payload);
    final hiddenPersonalAgentStatus =
        !ref.read(personalAgentFeatureVisibleProvider) &&
        isPersonalAgentControlPayload(payload, ref.read(agentsProvider).agents);
    if (terminalNotification != null && !hiddenPersonalAgentStatus) {
      state = terminalNotification;
    }
  }

  bool _rememberProjectedEvent(String key) {
    if (!_projectedEventKeys.add(key)) {
      return false;
    }
    while (_projectedEventKeys.length > _maxProjectedEventKeys) {
      _projectedEventKeys.remove(_projectedEventKeys.first);
    }
    return true;
  }

  bool _isCurrentSubscription(
    String daemonDid,
    int token,
    _AgentControlProjectionFence fence,
  ) {
    return !_disposed &&
        _subscriptionTokens[daemonDid] == token &&
        fence.matches(ref.read(sessionProvider));
  }

  void _handleSubscriptionTerminated({
    required String daemonDid,
    required int token,
    required _AgentControlProjectionFence fence,
    Object? error,
  }) {
    if (_subscriptionTokens[daemonDid] != token) {
      return;
    }
    _subscriptionTokens.remove(daemonDid);
    final current = _subscriptions.remove(daemonDid);
    if (current != null && current.token == token) {
      unawaited(current.subscription.cancel());
    }
    if (error != null) {
      AwikiPerformanceLogger.log(
        'agent_control_projection.stream_error',
        fields: <String, Object?>{
          'daemon_hash': AwikiPerformanceLogger.safeHash(daemonDid),
          'error': error.runtimeType.toString(),
        },
      );
    }
    _scheduleRetry(daemonDid, fence);
  }

  void _scheduleRetry(String daemonDid, _AgentControlProjectionFence fence) {
    if (_disposed ||
        !fence.matches(ref.read(sessionProvider)) ||
        !ref
            .read(agentsProvider)
            .agents
            .any((agent) => agent.isDaemon && agent.agentDid == daemonDid)) {
      return;
    }
    final attempt = (_retryAttempts[daemonDid] ?? 0) + 1;
    _retryAttempts[daemonDid] = attempt;
    final multiplier = 1 << (attempt - 1).clamp(0, 5);
    final delayMs =
        (agentControlProjectionRetryBaseDelay.inMilliseconds * multiplier)
            .clamp(
              agentControlProjectionRetryBaseDelay.inMilliseconds,
              agentControlProjectionRetryMaxDelay.inMilliseconds,
            )
            .toInt();
    _retryTimers.remove(daemonDid)?.cancel();
    late final Timer timer;
    timer = Timer(Duration(milliseconds: delayMs), () {
      if (!identical(_retryTimers[daemonDid], timer)) {
        return;
      }
      _retryTimers.remove(daemonDid);
      if (!_disposed && fence.matches(ref.read(sessionProvider))) {
        _reconcileSubscriptions();
      }
    });
    _retryTimers[daemonDid] = timer;
  }

  void _cancelSubscription(String daemonDid) {
    _retryTimers.remove(daemonDid)?.cancel();
    _retryAttempts.remove(daemonDid);
    _subscriptionTokens.remove(daemonDid);
    unawaited(_subscriptions.remove(daemonDid)?.subscription.cancel());
  }

  void _cancelAllSubscriptions() {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _retryAttempts.clear();
    _subscriptionTokens.clear();
    for (final entry in _subscriptions.values) {
      unawaited(entry.subscription.cancel());
    }
    _subscriptions.clear();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _sessionSubscription?.close();
    _agentsSubscription?.close();
    _cancelAllSubscriptions();
    _activeFence = null;
    _projectedEventKeys.clear();
    super.dispose();
  }
}

String? _projectionEventKey({
  required String? daemonDid,
  required Map<String, Object?> payload,
  required String? fallback,
}) {
  final schema = payload['schema']?.toString().trim() ?? '';
  final payloadIdentity =
      <Object?>[
            payload['event_id'],
            payload['action_id'],
            payload['notification_id'],
          ]
          .map((value) => value?.toString().trim())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .firstOrNull;
  final identity = payloadIdentity ?? fallback?.trim();
  if (identity == null || identity.isEmpty) {
    return null;
  }
  return '${daemonDid?.trim() ?? ''}|$schema|$identity';
}

String? _payloadDaemonDid(Map<String, Object?> payload) {
  final direct = payload['daemon_agent_did']?.toString().trim();
  if (direct?.isNotEmpty == true) {
    return direct;
  }
  final daemon = payload['daemon'];
  if (daemon is Map) {
    final nested = daemon['agent_did']?.toString().trim();
    if (nested?.isNotEmpty == true) {
      return nested;
    }
  }
  return null;
}

final class _AgentControlProjectionFence {
  const _AgentControlProjectionFence({
    required this.sessionGeneration,
    required this.ownerDid,
    this.bindingCurrentDid,
    this.ownerIdentityId,
    this.accountId,
    this.protocolDeviceId,
    this.identityGeneration,
    this.deviceAuthGeneration,
  });

  static _AgentControlProjectionFence? capture(SessionState state) {
    final session = state.session;
    if (session == null) {
      return null;
    }
    final binding = session.accountBinding;
    return _AgentControlProjectionFence(
      sessionGeneration: state.generation,
      ownerDid: session.did,
      bindingCurrentDid: binding?.currentDid,
      ownerIdentityId: binding?.ownerIdentityId,
      accountId: binding?.accountId,
      protocolDeviceId: binding?.protocolDeviceId,
      identityGeneration: binding?.identityGeneration,
      deviceAuthGeneration: binding?.deviceAuthGeneration,
    );
  }

  final int sessionGeneration;
  final String ownerDid;
  final String? bindingCurrentDid;
  final String? ownerIdentityId;
  final String? accountId;
  final String? protocolDeviceId;
  final String? identityGeneration;
  final String? deviceAuthGeneration;

  bool matches(SessionState state) => this == capture(state);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _AgentControlProjectionFence &&
            other.sessionGeneration == sessionGeneration &&
            other.ownerDid == ownerDid &&
            other.bindingCurrentDid == bindingCurrentDid &&
            other.ownerIdentityId == ownerIdentityId &&
            other.accountId == accountId &&
            other.protocolDeviceId == protocolDeviceId &&
            other.identityGeneration == identityGeneration &&
            other.deviceAuthGeneration == deviceAuthGeneration;
  }

  @override
  int get hashCode => Object.hash(
    sessionGeneration,
    ownerDid,
    bindingCurrentDid,
    ownerIdentityId,
    accountId,
    protocolDeviceId,
    identityGeneration,
    deviceAuthGeneration,
  );
}

final class _AgentControlProjectionSubscription {
  const _AgentControlProjectionSubscription({
    required this.token,
    required this.fence,
    required this.subscription,
  });

  final int token;
  final _AgentControlProjectionFence fence;
  final StreamSubscription<AgentControlEvent> subscription;
}

final agentControlProjectionCoordinatorProvider =
    StateNotifierProvider.autoDispose<
      AgentControlProjectionCoordinator,
      AgentTerminalNotification?
    >((ref) => AgentControlProjectionCoordinator(ref));
