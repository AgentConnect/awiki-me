// StateNotifier's protected state is inspected only by these focused tests.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:awiki_me/src/application/ports/agent_availability_port.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_availability.dart';
import 'package:awiki_me/src/presentation/agents/agent_availability_provider.dart';
import 'package:flutter_test/flutter_test.dart';

AgentAvailability fact(String did, {String version = '1', String? reason}) =>
    AgentAvailability(
      agentDid: did,
      state: reason == null
          ? AgentAvailabilityState.available
          : AgentAvailabilityState.unavailable,
      reason: reason,
      version: version,
    );

class AvailabilityPort implements AgentAvailabilityPort {
  final List<List<String>> calls = [];
  Future<List<AgentAvailability>> Function(List<String>)? respond;

  @override
  Future<List<AgentAvailability>> getAgentAvailability(
    List<String> agentDids,
  ) async {
    calls.add(List.of(agentDids));
    return respond == null
        ? agentDids.map((did) => fact(did)).toList()
        : respond!(agentDids);
  }
}

void main() {
  test(
    'versions retain precision; unknown and later active cannot resurrect terminal Agent',
    () {
      final deleted = fact(
        'did:agent',
        version: '9007199254740993',
        reason: 'agent_deleted',
      );
      expect(
        fact('did:agent', version: '9007199254740992').supersedes(deleted),
        isFalse,
      );
      expect(
        fact('did:agent', version: '9007199254740994').supersedes(deleted),
        isFalse,
      );
      expect(
        fact(
          'did:agent',
          version: '9007199254740994',
          reason: 'agent_revoked',
        ).supersedes(deleted),
        isTrue,
      );
      expect(
        const AgentAvailability(
          agentDid: 'did:agent',
          state: AgentAvailabilityState.unknown,
          version: '9999999999999999',
        ).supersedes(deleted),
        isFalse,
      );
      expect(
        AgentAvailability.parse({...deleted.toJson(), 'version': 1}),
        isNull,
      );
    },
  );

  test(
    'overlapping requests share bounded batches and successful cache',
    () async {
      final port = AvailabilityPort();
      final controller = AgentAvailabilityController(
        port: port,
        store: InMemoryAwikiProductLocalStore(),
        ownerDid: 'did:owner',
      );
      addTearDown(controller.dispose);
      final dids = List.generate(130, (i) => 'did:agent:$i');
      await Future.wait([controller.ensure(dids), controller.ensure(dids)]);
      expect(port.calls.map((batch) => batch.length), [64, 64, 2]);
      expect(controller.state.length, 130);
      await controller.ensure(dids);
      expect(port.calls.length, 3);
    },
  );

  test(
    'failure retains known facts, unknown remains unknown, and retries are bounded by TTL',
    () async {
      var now = DateTime.utc(2026, 9, 21);
      final port = AvailabilityPort()
        ..respond = (dids) async => [
          fact(dids.single, reason: 'agent_retired'),
        ];
      final controller = AgentAvailabilityController(
        port: port,
        store: InMemoryAwikiProductLocalStore(),
        ownerDid: 'did:owner',
        clock: () => now,
      );
      addTearDown(controller.dispose);
      await controller.ensure(['did:old']);
      port.respond = (_) async => throw StateError('offline');
      await controller.ensure(['did:old', 'did:unknown'], force: true);
      expect(controller.state['did:old']!.terminal, isTrue);
      expect(controller.state['did:unknown'], isNull);
      final count = port.calls.length;
      await controller.ensure(['did:unknown']);
      expect(port.calls.length, count);
      now = now.add(const Duration(minutes: 2));
      await controller.ensure(['did:unknown']);
      expect(port.calls.length, count + 1);
    },
  );

  test(
    'new provider restores only its owner and revalidates persisted facts',
    () async {
      final store = InMemoryAwikiProductLocalStore();
      final port = AvailabilityPort()
        ..respond = (dids) async => [
          fact(dids.single, reason: 'agent_deleted'),
        ];
      final first = AgentAvailabilityController(
        port: port,
        store: store,
        ownerDid: 'did:alice',
      );
      await first.ensure(['did:old']);
      first.dispose();
      final alice = AgentAvailabilityController(
        port: port,
        store: store,
        ownerDid: 'did:alice',
      );
      final bob = AgentAvailabilityController(
        port: port,
        store: store,
        ownerDid: 'did:bob',
      );
      addTearDown(alice.dispose);
      addTearDown(bob.dispose);
      await Future.wait([alice.restore(), bob.restore()]);
      expect(alice.state['did:old']!.unavailable, isTrue);
      expect(bob.state, isEmpty);
      await alice.ensure(['did:old']);
      expect(port.calls.length, 2);
    },
  );

  test(
    'disposal releases waiters and fences late network state and persistence',
    () async {
      final response = Completer<List<AgentAvailability>>();
      final called = Completer<void>();
      final port = AvailabilityPort()
        ..respond = (_) {
          called.complete();
          return response.future;
        };
      final store = InMemoryAwikiProductLocalStore();
      final controller = AgentAvailabilityController(
        port: port,
        store: store,
        ownerDid: 'did:owner',
      );
      final request = controller.ensure(['did:old']);
      await called.future;
      controller.dispose();
      await request;
      response.complete([fact('did:old', reason: 'agent_deleted')]);
      await Future<void>.delayed(Duration.zero);
      expect(
        await store.loadUiPreference(
          ownerDid: 'did:owner',
          key: AgentAvailabilityController.cacheKey,
        ),
        isNull,
      );
    },
  );

  test(
    'account sync retirement wins over an older in-flight availability response',
    () async {
      final response = Completer<List<AgentAvailability>>();
      final called = Completer<void>();
      final port = AvailabilityPort()
        ..respond = (_) {
          called.complete();
          return response.future;
        };
      final store = InMemoryAwikiProductLocalStore();
      final controller = AgentAvailabilityController(
        port: port,
        store: store,
        ownerDid: 'did:owner',
      );
      addTearDown(controller.dispose);
      final request = controller.ensure(['did:old']);
      await called.future;
      await controller.applyFacts([
        fact('did:old', version: '3', reason: 'agent_retired'),
      ]);
      response.complete([fact('did:old', version: '2')]);
      await request;
      expect(controller.state['did:old']!.reason, 'agent_retired');
      expect(controller.state['did:old']!.version, '3');

      final restored = AgentAvailabilityController(
        port: port,
        store: store,
        ownerDid: 'did:owner',
      );
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.state['did:old']!.reason, 'agent_retired');
      expect(restored.state['did:old']!.version, '3');
    },
  );

  test(
    'unavailable optional endpoint retains legacy presentation without network work',
    () async {
      final controller = AgentAvailabilityController(
        port: null,
        store: InMemoryAwikiProductLocalStore(),
        ownerDid: 'did:owner',
      );
      addTearDown(controller.dispose);
      await controller.ensure(['did:agent']);
      expect(controller.state, isEmpty);
    },
  );
}
