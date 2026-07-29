import 'package:awiki_me/src/application/account_state_sync_service.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/ports/account_state_sync_port.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const binding = ProductAccountBinding(
    ownerIdentityId: 'owner-1',
    accountId: 'account-1',
  );
  const did = 'did:wba:example.test:alice';

  test('reconcile commits four independent versioned domains', () async {
    final remote = _Remote();
    final store = InMemoryAwikiProductLocalStore();
    final result = await AccountStateSyncService(remote: remote, local: store)
        .reconcile(
          binding: binding,
          expectedCurrentDid: did,
          expectedIdentityGeneration: '1',
          sessionGeneration: 7,
          isSessionCurrent: (_, generation) => generation == 7,
        );

    expect(result.failures, isEmpty);
    expect(result.committedDomains, ProductAccountDomain.values.toSet());
    expect(remote.manifestCalls, 2);
    expect(
      (await store.loadAgentInventorySnapshot(binding: binding))?.domainVersion,
      '1',
    );
    expect(
      (await store.loadAgentStatusSnapshot(binding: binding))?.domainVersion,
      '1',
    );
    expect(
      (await store.loadProfileSnapshot(binding: binding))?.domainVersion,
      '1',
    );
    expect(
      (await store.loadDeviceRegistrySnapshot(binding: binding))?.domainVersion,
      '1',
    );
  });

  test('one failed domain does not block the other three', () async {
    final remote = _Remote(failStatus: true);
    final store = InMemoryAwikiProductLocalStore();
    final result = await AccountStateSyncService(remote: remote, local: store)
        .reconcile(
          binding: binding,
          expectedCurrentDid: did,
          expectedIdentityGeneration: '1',
          sessionGeneration: 1,
          isSessionCurrent: (_, __) => true,
        );

    expect(result.failures.keys, contains(ProductAccountDomain.agentStatus));
    expect(
      result.committedDomains,
      containsAll(<ProductAccountDomain>[
        ProductAccountDomain.agentInventory,
        ProductAccountDomain.profile,
        ProductAccountDomain.deviceRegistry,
      ]),
    );
    expect(await store.loadAgentStatusSnapshot(binding: binding), isNull);
  });

  test('one failed local domain read does not block the other three', () async {
    final remote = _Remote();
    final store = _OneDomainBrokenStore(
      brokenDomain: ProductAccountDomain.agentStatus,
    );
    final result = await AccountStateSyncService(remote: remote, local: store)
        .reconcile(
          binding: binding,
          expectedCurrentDid: did,
          expectedIdentityGeneration: '1',
          sessionGeneration: 1,
          isSessionCurrent: (_, __) => true,
        );

    expect(result.failures.keys, contains(ProductAccountDomain.agentStatus));
    expect(
      result.committedDomains,
      containsAll(<ProductAccountDomain>[
        ProductAccountDomain.agentInventory,
        ProductAccountDomain.profile,
        ProductAccountDomain.deviceRegistry,
      ]),
    );
    expect(
      (await store.loadAgentInventorySnapshot(binding: binding))?.domainVersion,
      '1',
    );
    expect(
      (await store.loadProfileSnapshot(binding: binding))?.domainVersion,
      '1',
    );
    expect(
      (await store.loadDeviceRegistrySnapshot(binding: binding))?.domainVersion,
      '1',
    );
  });

  test('M2 refetches only a domain that advanced after M1', () async {
    final remote = _Remote(advanceProfileAtM2: true);
    final store = InMemoryAwikiProductLocalStore();

    await AccountStateSyncService(remote: remote, local: store).reconcile(
      binding: binding,
      expectedCurrentDid: did,
      expectedIdentityGeneration: '1',
      sessionGeneration: 1,
      isSessionCurrent: (_, __) => true,
    );

    expect(remote.profileCalls, 2);
    expect(remote.inventoryCalls, 1);
    expect(
      (await store.loadProfileSnapshot(binding: binding))?.domainVersion,
      '2',
    );
  });

  test(
    'non-authoritative legacy version zero always fetches authoritative zero',
    () async {
      final remote = _Remote(version: '0', emptyInventory: true);
      final store = InMemoryAwikiProductLocalStore();
      await store.saveAgentState(
        LocalAgentState(
          ownerDid: did,
          agentDid: 'did:agent:removed',
          valueJson:
              '{"agent_did":"did:agent:removed","agent_kind":"runtime",'
              '"controller_full_handle":"alice.example.test",'
              '"profile_summary":{},"active_state":"active",'
              '"invocation_policy":{},"inventory_version":"0"}',
          updatedAt: DateTime.utc(2026, 7, 28),
        ),
      );
      final seeded = await store.loadAgentInventorySnapshot(
        binding: binding,
        legacyOwnerDid: did,
      );
      expect(seeded?.payloadHash, productLegacyAgentSeedPayloadHash);

      await AccountStateSyncService(remote: remote, local: store).reconcile(
        binding: binding,
        expectedCurrentDid: did,
        expectedIdentityGeneration: '1',
        sessionGeneration: 1,
        isSessionCurrent: (_, __) => true,
      );

      expect(remote.inventoryCalls, 1);
      final authoritative = await store.loadAgentInventorySnapshot(
        binding: binding,
      );
      expect(authoritative?.agents, isEmpty);
      expect(authoritative?.payloadHash, isNull);
    },
  );

  test('manifest DID mismatch fails before domain fetches', () async {
    final remote = _Remote(currentDid: 'did:wba:example.test:mallory');

    await expectLater(
      AccountStateSyncService(
        remote: remote,
        local: InMemoryAwikiProductLocalStore(),
      ).reconcile(
        binding: binding,
        expectedCurrentDid: did,
        expectedIdentityGeneration: '1',
        sessionGeneration: 1,
        isSessionCurrent: (_, __) => true,
      ),
      throwsA(
        isA<AccountStateSyncProtocolException>().having(
          (error) => error.code,
          'code',
          'account_state_manifest_did_mismatch',
        ),
      ),
    );
    expect(remote.inventoryCalls, 0);
  });

  test('invalidated session does not commit fetched snapshot', () async {
    var current = true;
    final remote = _Remote(onInventoryLoaded: () => current = false);
    final store = InMemoryAwikiProductLocalStore();
    final result = await AccountStateSyncService(remote: remote, local: store)
        .reconcile(
          binding: binding,
          expectedCurrentDid: did,
          expectedIdentityGeneration: '1',
          sessionGeneration: 1,
          isSessionCurrent: (_, __) => current,
        );

    expect(result.sessionInvalidated, isTrue);
    expect(await store.loadAgentInventorySnapshot(binding: binding), isNull);
  });
}

class _Remote implements AccountStateSyncPort {
  _Remote({
    this.version = '1',
    this.currentDid = 'did:wba:example.test:alice',
    this.failStatus = false,
    this.emptyInventory = false,
    this.advanceProfileAtM2 = false,
    this.onInventoryLoaded,
  });

  final String version;
  final String currentDid;
  final bool failStatus;
  final bool emptyInventory;
  final bool advanceProfileAtM2;
  final void Function()? onInventoryLoaded;
  int manifestCalls = 0;
  int inventoryCalls = 0;
  int profileCalls = 0;

  @override
  Future<AccountStateManifest> loadManifest() async {
    manifestCalls += 1;
    return AccountStateManifest(
      accountId: 'account-1',
      currentDid: currentDid,
      identityGeneration: '1',
      versions: <ProductAccountDomain, String>{
        for (final domain in ProductAccountDomain.values)
          domain:
              advanceProfileAtM2 &&
                  domain == ProductAccountDomain.profile &&
                  manifestCalls > 1
              ? '2'
              : version,
      },
      serverTime: DateTime.utc(2026, 7, 29),
    );
  }

  @override
  Future<AccountStateAgentInventorySnapshot> loadAgentInventory() async {
    inventoryCalls += 1;
    onInventoryLoaded?.call();
    return AccountStateAgentInventorySnapshot(
      accountId: 'account-1',
      inventoryVersion: version,
      agents: emptyInventory
          ? const <AccountStateAgentInventoryEntry>[]
          : <AccountStateAgentInventoryEntry>[
              AccountStateAgentInventoryEntry(
                agentDid: 'did:agent:one',
                agentKind: 'runtime',
                controllerFullHandle: 'alice.example.test',
                profileSummary: const <String, Object?>{},
                activeState: 'active',
                invocationPolicy: const <String, Object?>{},
                inventoryVersion: version,
              ),
            ],
    );
  }

  @override
  Future<AccountStateAgentStatusSnapshot> loadAgentStatus() async {
    if (failStatus) {
      throw StateError('status_unavailable');
    }
    return AccountStateAgentStatusSnapshot(
      accountId: 'account-1',
      agentStatusVersion: version,
      statuses: const <AccountStateAgentStatusEntry>[],
    );
  }

  @override
  Future<AccountStateProfileSnapshot> loadProfile() async {
    profileCalls += 1;
    return AccountStateProfileSnapshot(
      accountId: 'account-1',
      profileVersion: advanceProfileAtM2 && profileCalls > 1 ? '2' : version,
      profile: AccountStateProfile(tags: const <String>[]),
    );
  }

  @override
  Future<AccountStateDeviceRegistrySnapshot> loadDeviceRegistry() async {
    return AccountStateDeviceRegistrySnapshot(
      did: currentDid,
      registryVersion: version,
      devices: const <AccountStateDeviceRegistryEntry>[
        AccountStateDeviceRegistryEntry(
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

class _OneDomainBrokenStore extends InMemoryAwikiProductLocalStore {
  _OneDomainBrokenStore({required this.brokenDomain});

  final ProductAccountDomain brokenDomain;

  @override
  Future<ProductAccountDomainSyncState?> loadDomainSyncState({
    required ProductAccountBinding binding,
    required ProductAccountDomain domain,
  }) {
    if (domain == brokenDomain) {
      throw StateError('local_domain_unavailable');
    }
    return super.loadDomainSyncState(binding: binding, domain: domain);
  }
}
