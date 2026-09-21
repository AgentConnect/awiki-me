import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/models/product_local_models.dart';
import '../../application/ports/agent_availability_port.dart';
import '../../application/product_local_store.dart';
import '../../domain/entities/agent/agent_availability.dart';
import '../app_shell/providers/session_provider.dart';
import 'agents_provider.dart';

/// One bounded, owner-scoped lifecycle cache shared by group presentation.
/// It never owns message, roster or execution facts.
class AgentAvailabilityController
    extends StateNotifier<Map<String, AgentAvailability>> {
  AgentAvailabilityController({
    required this.port,
    required this.store,
    required this.ownerDid,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const {});

  static const cacheKey = 'agent-availability:v1';
  static const maxEntries = 1024;
  static const ttl = Duration(minutes: 1);
  final AgentAvailabilityPort? port;
  final ProductLocalStore store;
  final String? ownerDid;
  final DateTime Function() _clock;
  final Map<String, DateTime> _checked = {};
  final Map<String, Completer<void>> _pending = {};
  Future<void>? _restoration;
  Future<void> _writeTail = Future<void>.value();
  bool _draining = false;

  Future<void> restore() => _restoration ??= _restore();

  /// Same authoritative inventory facts arriving via account sync, including
  /// rows omitted from the manageable Agent list. Missing rows are not inferred.
  Future<void> applyFacts(Iterable<AgentAvailability> facts) async {
    await restore();
    if (!mounted) return;
    final next = <String, AgentAvailability>{...state};
    for (final fact in facts) {
      final previous = next[fact.agentDid];
      if (previous == null || fact.supersedes(previous)) {
        next.remove(fact.agentDid);
        next[fact.agentDid] = fact;
      }
    }
    while (next.length > maxEntries) {
      next.remove(next.keys.first);
    }
    state = Map.unmodifiable(next);
    await _persist();
  }

  Future<void> _restore() async {
    final owner = ownerDid;
    if (owner == null) return;
    try {
      final saved = await store.loadUiPreference(
        ownerDid: owner,
        key: cacheKey,
      );
      if (!mounted || saved == null) return;
      final rows = jsonDecode(saved.valueJson);
      if (rows is! List || rows.length > maxEntries) return;
      final values = <String, AgentAvailability>{...state};
      for (final row in rows) {
        if (row is! Map) continue;
        final value = AgentAvailability.parse(Map<String, Object?>.from(row));
        if (value == null) continue;
        final previous = values[value.agentDid];
        if (previous == null || value.supersedes(previous)) {
          values[value.agentDid] = value;
        }
      }
      state = Map.unmodifiable(values);
      // Disk facts paint immediately but always receive a fresh network check.
    } catch (_) {
      // A disposable presentation cache must not prevent opening a group.
    }
  }

  Future<void> ensure(Iterable<String> agentDids, {bool force = false}) async {
    await restore();
    if (!mounted || ownerDid == null || port == null) return;
    final now = _clock();
    final waiting = <Future<void>>[];
    for (final did in agentDids.toSet()) {
      if (!did.startsWith('did:') || did.length > 256) continue;
      final existing = _pending[did];
      if (existing != null) {
        waiting.add(existing.future);
        continue;
      }
      final checked = _checked[did];
      if (!force &&
          checked != null &&
          !now.isBefore(checked) &&
          now.difference(checked) < ttl) {
        continue;
      }
      final completer = Completer<void>();
      _pending[did] = completer;
      waiting.add(completer.future);
    }
    if (!_draining && _pending.isNotEmpty) {
      _draining = true;
      // Merge independent widgets' requests before starting one bounded batch.
      scheduleMicrotask(_drain);
    }
    await Future.wait(waiting);
  }

  Future<void> _drain() async {
    try {
      while (mounted && _pending.isNotEmpty) {
        final batch = _pending.keys.take(64).toList(growable: false);
        try {
          final results = await port!
              .getAgentAvailability(batch)
              .timeout(const Duration(seconds: 10));
          if (!mounted) return;
          final next = <String, AgentAvailability>{...state};
          for (final value in results) {
            if (!batch.contains(value.agentDid)) continue;
            final previous = next[value.agentDid];
            if (previous == null || value.supersedes(previous)) {
              next.remove(value.agentDid);
              next[value.agentDid] = value;
            }
          }
          while (next.length > maxEntries) {
            next.remove(next.keys.first);
          }
          state = Map.unmodifiable(next);
          await _persist();
        } catch (_) {
          // Unsupported old servers and temporary failures preserve known facts.
        } finally {
          if (mounted) {
            for (final did in batch) {
              _checked.remove(did);
              _checked[did] = _clock();
              _pending.remove(did)?.complete();
            }
            while (_checked.length > maxEntries) {
              _checked.remove(_checked.keys.first);
            }
          }
        }
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _persist() async {
    if (!mounted || ownerDid == null) return;
    final preference = LocalUiPreference(
      ownerDid: ownerDid!,
      key: cacheKey,
      valueJson: jsonEncode(
        state.values.map((value) => value.toJson()).toList(),
      ),
      updatedAt: _clock(),
    );
    _writeTail = _writeTail
        .then((_) async {
          if (!mounted) return;
          await store.saveUiPreference(preference);
        })
        .catchError((Object _) {});
    await _writeTail;
  }

  @override
  void dispose() {
    for (final pending in _pending.values) {
      pending.complete();
    }
    _pending.clear();
    super.dispose();
  }
}

final agentAvailabilityProvider =
    StateNotifierProvider<
      AgentAvailabilityController,
      Map<String, AgentAvailability>
    >((ref) {
      final epoch = ref.watch(
        sessionProvider.select((value) => value.activeEpoch),
      );
      return AgentAvailabilityController(
        port: ref.watch(agentAvailabilityPortProvider),
        store: ref.watch(productLocalStoreProvider),
        ownerDid: epoch?.ownerDid,
      );
    });

/// Confirmed local inventory retirement can paint before the batch RPC finishes.
/// Absence from personal inventory never implies deletion of someone else's Agent.
final effectiveAgentAvailabilityProvider =
    Provider<Map<String, AgentAvailability>>((ref) {
      final values = <String, AgentAvailability>{
        ...ref.watch(agentAvailabilityProvider),
      };
      for (final agent in ref.watch(
        agentsProvider.select((value) => value.agents),
      )) {
        final reason = switch (agent.activeState) {
          'archived' => 'agent_deleted',
          'revoked' => 'agent_revoked',
          'retired' => 'agent_retired',
          'inactive' => 'agent_inactive',
          _ => agent.isRetiredRuntime ? 'agent_retired' : null,
        };
        if (reason == null || values[agent.agentDid]?.terminal == true) {
          continue;
        }
        values[agent.agentDid] = AgentAvailability(
          agentDid: agent.agentDid,
          state: AgentAvailabilityState.unavailable,
          reason: reason,
        );
      }
      return Map.unmodifiable(values);
    });
