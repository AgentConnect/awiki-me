import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/ports/account_state_sync_port.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/account_state_sync_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
import 'package:awiki_me/src/presentation/profile/profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reconcile publishes committed Profile and display-only Registry',
    () async {
      final remote = _CoordinatorRemote();
      final container = ProviderContainer(
        overrides: <Override>[
          productLocalStoreProvider.overrideWithValue(
            InMemoryAwikiProductLocalStore(),
          ),
          accountStateSyncPortProvider.overrideWithValue(remote),
        ],
      );
      addTearDown(container.dispose);
      container.read(accountStateSyncCoordinatorProvider);
      container
          .read(sessionProvider.notifier)
          .setSession(_session(accountId: 'account-1'));

      await container
          .read(accountStateSyncCoordinatorProvider.notifier)
          .request('test');

      expect(
        container.read(accountStateSyncCoordinatorProvider).status,
        AccountStateSyncCoordinatorStatus.ready,
      );
      expect(container.read(profileProvider).profile?.displayName, 'Alice v1');
      final devices = container.read(devicesProvider);
      expect(
        devices.registry,
        isNull,
        reason: 'security truth stays in IM Core',
      );
      expect(devices.cachedRegistry?.registryVersion, '1');
      expect(
        devices.displayRegistry?.currentDevice?.protocolDeviceId,
        'device-1',
      );
    },
  );

  test('session switch during manifest load fences every projection', () async {
    final remote = _CoordinatorRemote(blockManifest: true);
    final container = ProviderContainer(
      overrides: <Override>[
        productLocalStoreProvider.overrideWithValue(
          InMemoryAwikiProductLocalStore(),
        ),
        accountStateSyncPortProvider.overrideWithValue(remote),
      ],
    );
    addTearDown(container.dispose);
    container.read(accountStateSyncCoordinatorProvider);
    container
        .read(sessionProvider.notifier)
        .setSession(_session(accountId: 'account-1'));
    final operation = container
        .read(accountStateSyncCoordinatorProvider.notifier)
        .request('blocked');
    await remote.manifestStarted.future;

    container
        .read(sessionProvider.notifier)
        .setSession(_session(accountId: 'account-2'));
    remote.releaseManifest.complete();
    await operation;

    expect(container.read(profileProvider).profile, isNull);
    expect(container.read(devicesProvider).cachedRegistry, isNull);
    expect(
      container.read(accountStateSyncCoordinatorProvider).status,
      AccountStateSyncCoordinatorStatus.idle,
    );
  });

  test('concurrent requests coalesce behind one active reconcile', () async {
    final remote = _CoordinatorRemote(blockManifest: true);
    final container = ProviderContainer(
      overrides: <Override>[
        productLocalStoreProvider.overrideWithValue(
          InMemoryAwikiProductLocalStore(),
        ),
        accountStateSyncPortProvider.overrideWithValue(remote),
      ],
    );
    addTearDown(container.dispose);
    container.read(accountStateSyncCoordinatorProvider);
    container
        .read(sessionProvider.notifier)
        .setSession(_session(accountId: 'account-1'));
    final first = container
        .read(accountStateSyncCoordinatorProvider.notifier)
        .request('first');
    await remote.manifestStarted.future;
    final second = container
        .read(accountStateSyncCoordinatorProvider.notifier)
        .request('second');
    remote.releaseManifest.complete();
    await Future.wait<void>(<Future<void>>[first, second]);

    expect(remote.maxConcurrentManifestLoads, 1);
    expect(remote.manifestCalls, 4, reason: 'M1/M2 plus one coalesced M1/M2');
    expect(
      container.read(accountStateSyncCoordinatorProvider).lastReason,
      'second',
    );
  });

  test(
    'Inventory cache retains inactive rows while Agent UI hides them',
    () async {
      final store = InMemoryAwikiProductLocalStore();
      final container = ProviderContainer(
        overrides: <Override>[
          productLocalStoreProvider.overrideWithValue(store),
          accountStateSyncPortProvider.overrideWithValue(
            _CoordinatorRemote(withAgents: true),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(accountStateSyncCoordinatorProvider);
      container
          .read(sessionProvider.notifier)
          .setSession(_session(accountId: 'account-1'));

      await container
          .read(accountStateSyncCoordinatorProvider.notifier)
          .request('agents');

      expect(
        (await store.loadAgentInventorySnapshot(
          binding: const ProductAccountBinding(
            ownerIdentityId: 'owner-account-1',
            accountId: 'account-1',
          ),
        ))?.agents,
        hasLength(2),
      );
      expect(container.read(agentsProvider).agents, hasLength(1));
      expect(
        container.read(agentsProvider).agents.single.agentDid,
        'did:agent:active',
      );
    },
  );

  test(
    'legacy seed renders once but server zero still clears removed Agent',
    () async {
      final store = InMemoryAwikiProductLocalStore();
      await store.saveAgentState(
        LocalAgentState(
          ownerDid: 'did:wba:example.test:alice',
          agentDid: 'did:agent:removed',
          valueJson:
              '{"agent_did":"did:agent:removed","agent_kind":"runtime",'
              '"display_name":"Removed","active_state":"active"}',
          updatedAt: DateTime.utc(2026, 7, 28),
        ),
      );
      final remote = _CoordinatorRemote(blockManifest: true, version: '0');
      final container = ProviderContainer(
        overrides: <Override>[
          productLocalStoreProvider.overrideWithValue(store),
          accountStateSyncPortProvider.overrideWithValue(remote),
        ],
      );
      addTearDown(container.dispose);
      container.read(accountStateSyncCoordinatorProvider);
      container
          .read(sessionProvider.notifier)
          .setSession(_session(accountId: 'account-1'));

      final operation = container
          .read(accountStateSyncCoordinatorProvider.notifier)
          .request('legacy_seed');
      await remote.manifestStarted.future;
      expect(
        container.read(agentsProvider).agents.single.agentDid,
        'did:agent:removed',
      );
      remote.releaseManifest.complete();
      await operation;

      expect(remote.inventoryCalls, 1);
      expect(container.read(agentsProvider).agents, isEmpty);
      expect(
        (await store.loadAgentInventorySnapshot(
          binding: const ProductAccountBinding(
            ownerIdentityId: 'owner-account-1',
            accountId: 'account-1',
          ),
        ))?.payloadHash,
        isNull,
      );
    },
  );
}

SessionIdentity _session({required String accountId}) {
  return SessionIdentity(
    did: 'did:wba:example.test:alice',
    credentialName: accountId,
    displayName: 'Alice',
    accountBinding: SessionAccountBinding(
      ownerIdentityId: 'owner-$accountId',
      accountId: accountId,
      currentDid: 'did:wba:example.test:alice',
      protocolDeviceId: 'device-1',
      identityGeneration: '1',
      deviceAuthGeneration: '1',
    ),
  );
}

class _CoordinatorRemote implements AccountStateSyncPort {
  _CoordinatorRemote({
    this.blockManifest = false,
    this.withAgents = false,
    this.version = '1',
  });

  final bool blockManifest;
  final bool withAgents;
  final String version;
  final Completer<void> manifestStarted = Completer<void>();
  final Completer<void> releaseManifest = Completer<void>();
  int manifestCalls = 0;
  int concurrentManifestLoads = 0;
  int maxConcurrentManifestLoads = 0;
  int inventoryCalls = 0;

  @override
  Future<AccountStateManifest> loadManifest() async {
    manifestCalls += 1;
    concurrentManifestLoads += 1;
    if (concurrentManifestLoads > maxConcurrentManifestLoads) {
      maxConcurrentManifestLoads = concurrentManifestLoads;
    }
    if (!manifestStarted.isCompleted) {
      manifestStarted.complete();
    }
    if (blockManifest && !releaseManifest.isCompleted) {
      await releaseManifest.future;
    }
    concurrentManifestLoads -= 1;
    return AccountStateManifest(
      accountId: 'account-1',
      currentDid: 'did:wba:example.test:alice',
      identityGeneration: '1',
      versions: <ProductAccountDomain, String>{
        for (final domain in ProductAccountDomain.values) domain: version,
      },
      serverTime: DateTime.utc(2026, 7, 29),
    );
  }

  @override
  Future<AccountStateAgentInventorySnapshot> loadAgentInventory() async {
    inventoryCalls += 1;
    return AccountStateAgentInventorySnapshot(
      accountId: 'account-1',
      inventoryVersion: version,
      agents: withAgents
          ? <AccountStateAgentInventoryEntry>[
              for (final state in <String>['active', 'archived'])
                AccountStateAgentInventoryEntry(
                  agentDid: 'did:agent:$state',
                  agentKind: 'runtime',
                  controllerFullHandle: 'alice.example.test',
                  displayName: state,
                  profileSummary: const <String, Object?>{},
                  activeState: state,
                  invocationPolicy: const <String, Object?>{},
                  inventoryVersion: version,
                ),
            ]
          : const <AccountStateAgentInventoryEntry>[],
    );
  }

  @override
  Future<AccountStateAgentStatusSnapshot> loadAgentStatus() async {
    return AccountStateAgentStatusSnapshot(
      accountId: 'account-1',
      agentStatusVersion: version,
      statuses: const <AccountStateAgentStatusEntry>[],
    );
  }

  @override
  Future<AccountStateProfileSnapshot> loadProfile() async {
    return AccountStateProfileSnapshot(
      accountId: 'account-1',
      profileVersion: version,
      profile: AccountStateProfile(
        nickName: 'Alice v1',
        tags: const <String>[],
      ),
    );
  }

  @override
  Future<AccountStateDeviceRegistrySnapshot> loadDeviceRegistry() async {
    return AccountStateDeviceRegistrySnapshot(
      did: 'did:wba:example.test:alice',
      registryVersion: version,
      devices: <AccountStateDeviceRegistryEntry>[
        const AccountStateDeviceRegistryEntry(
          protocolDeviceId: 'device-1',
          signingKeyId: 'did:key:signing',
          e2eeKeyId: 'did:key:e2ee',
          status: 'active',
          role: 'admin',
          managementReady: true,
          authGeneration: '1',
        ),
      ],
    );
  }
}
