import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const registryEpoch = ProductDeviceRegistryEpoch(
    currentDid: 'did:wba:awiki.info:users:alice-old',
    bindingGeneration: '7',
  );
  test(
    'in-memory product store keeps overlays drafts and preferences by owner',
    () async {
      final store = InMemoryAwikiProductLocalStore();
      final now = DateTime.utc(2026, 5, 23);

      await store.upsertConversationOverlay(
        ProductConversationOverlay(
          ownerDid: 'did:alice',
          threadId: 'thread-1',
          conversationId: 'thread-1',
          pinned: true,
          customTitle: 'Custom',
          updatedAt: now,
        ),
      );
      await store.setThreadHidden(
        ownerDid: 'did:alice',
        threadId: 'thread-1',
        hidden: true,
        updatedAt: now.add(const Duration(minutes: 1)),
      );
      await store.saveDraft(
        MessageDraft(
          ownerDid: 'did:alice',
          threadId: 'thread-1',
          draftText: 'draft',
          updatedAt: now,
        ),
      );
      await store.saveUiPreference(
        LocalUiPreference(
          ownerDid: 'did:alice',
          key: 'sort',
          valueJson: '{"by":"recent"}',
          updatedAt: now,
        ),
      );

      final overlay = await store.loadConversationOverlay(
        ownerDid: 'did:alice',
        threadId: 'thread-1',
      );
      final overlays = await store.loadConversationOverlays(
        ownerDid: 'did:alice',
      );
      final draft = await store.loadDraft(
        ownerDid: 'did:alice',
        threadId: 'thread-1',
      );
      final preference = await store.loadUiPreference(
        ownerDid: 'did:alice',
        key: 'sort',
      );

      expect(overlay?.pinned, isTrue);
      expect(overlay?.hidden, isTrue);
      expect(overlay?.customTitle, 'Custom');
      expect(overlays.keys, contains('thread-1'));
      expect(draft?.draftText, 'draft');
      expect(preference?.valueJson, contains('recent'));

      expect(
        await store.loadConversationOverlay(
          ownerDid: 'did:bob',
          threadId: 'thread-1',
        ),
        isNull,
      );
    },
  );

  test(
    'in-memory overlays use conversation id as canonical owner key',
    () async {
      final store = InMemoryAwikiProductLocalStore();
      final now = DateTime.utc(2026, 7, 5, 10);

      await store.upsertConversationOverlay(
        ProductConversationOverlay(
          ownerDid: 'did:alice',
          threadId: 'direct-did:did:bob',
          conversationId: 'dm:peer-scope:v1:bob',
          hidden: true,
          updatedAt: now,
        ),
      );
      await store.upsertConversationOverlayByConversationId(
        ProductConversationOverlay(
          ownerDid: 'did:alice',
          threadId: 'legacy-thread',
          conversationId: 'dm:peer-scope:v1:bob',
          pinned: true,
          customTitle: 'Bob canonical',
          avatarSeed: 'seed-canonical',
          updatedAt: now.add(const Duration(minutes: 1)),
        ),
      );
      await store.upsertConversationOverlayByConversationId(
        ProductConversationOverlay(
          ownerDid: 'did:bob',
          threadId: 'legacy-thread',
          conversationId: 'dm:peer-scope:v1:bob',
          customTitle: 'Bob owner',
          updatedAt: now,
        ),
      );

      final alice = await store.loadConversationOverlayByConversationId(
        ownerDid: 'did:alice',
        conversationId: 'dm:peer-scope:v1:bob',
      );
      final bob = await store.loadConversationOverlayByConversationId(
        ownerDid: 'did:bob',
        conversationId: 'dm:peer-scope:v1:bob',
      );
      final batch = await store.loadConversationOverlaysByConversationId(
        ownerDid: 'did:alice',
        conversationIds: const <String>['dm:peer-scope:v1:bob'],
      );

      expect(alice?.threadId, 'dm:peer-scope:v1:bob');
      expect(alice?.conversationId, 'dm:peer-scope:v1:bob');
      expect(alice?.pinned, isTrue);
      expect(alice?.hidden, isFalse);
      expect(alice?.customTitle, 'Bob canonical');
      expect(alice?.avatarSeed, 'seed-canonical');
      expect(bob?.customTitle, 'Bob owner');
      expect(batch.keys, ['dm:peer-scope:v1:bob']);

      await store.setConversationHiddenByConversationId(
        ownerDid: 'did:alice',
        conversationId: 'dm:peer-scope:v1:bob',
        hidden: true,
        updatedAt: now.add(const Duration(minutes: 2)),
      );
      final hidden = await store.loadConversationOverlayByConversationId(
        ownerDid: 'did:alice',
        conversationId: 'dm:peer-scope:v1:bob',
      );
      expect(hidden?.hidden, isTrue);
      expect(hidden?.pinned, isTrue);
      expect(hidden?.customTitle, 'Bob canonical');

      await store.deleteConversationOverlayByConversationId(
        ownerDid: 'did:alice',
        conversationId: 'dm:peer-scope:v1:bob',
      );
      expect(
        await store.loadConversationOverlayByConversationId(
          ownerDid: 'did:alice',
          conversationId: 'dm:peer-scope:v1:bob',
        ),
        isNull,
      );
      expect(
        await store.loadConversationOverlayByConversationId(
          ownerDid: 'did:bob',
          conversationId: 'dm:peer-scope:v1:bob',
        ),
        isNotNull,
      );
    },
  );

  test(
    'deleteOwnerData removes current and pre-recovery owner data only',
    () async {
      final store = InMemoryAwikiProductLocalStore();
      final now = DateTime.utc(2026, 8, 11);
      const aliceBinding = ProductAccountBinding(
        ownerIdentityId: 'owner-alice',
        accountId: 'account-alice',
      );
      const bobBinding = ProductAccountBinding(
        ownerIdentityId: 'owner-bob',
        accountId: 'account-bob',
      );
      const recovery = ProductDeviceRegistryEpochResetAuthorization(
        reference: ProductDeviceRegistryEpochResetReference(
          accountUserId: 'account-alice',
          ownerIdentityId: 'owner-alice',
          previousDid: 'did:wba:awiki.info:users:alice-old',
          currentDid: 'did:wba:awiki.info:users:alice-new',
          bindingGeneration: '2',
        ),
        handle: 'alice.awiki.info',
        sourceKind: ProductIdentityTransitionSourceKind.initiator,
        sourceId: 'recovery-alice',
      );

      await store.upsertConversationOverlay(
        ProductConversationOverlay(
          ownerDid: recovery.reference.previousDid,
          threadId: 'alice-old-thread',
          conversationId: 'alice-old-thread',
          updatedAt: now,
        ),
      );
      await store.upsertConversationOverlay(
        ProductConversationOverlay(
          ownerDid: 'did:wba:awiki.info:users:bob',
          threadId: 'bob-thread',
          conversationId: 'bob-thread',
          updatedAt: now,
        ),
      );
      await store.replaceAgentInventorySnapshot(
        ProductAgentInventorySnapshot(
          binding: aliceBinding,
          domainVersion: '1',
          refreshedAt: now,
          agents: const <ProductAgentInventoryItem>[
            ProductAgentInventoryItem(
              agentDid: 'did:agent:alice',
              activeState: 'active',
              payloadJson: '{"name":"Alice agent"}',
            ),
          ],
        ),
      );
      await store.replaceAgentInventorySnapshot(
        ProductAgentInventorySnapshot(
          binding: bobBinding,
          domainVersion: '1',
          refreshedAt: now,
          agents: const <ProductAgentInventoryItem>[
            ProductAgentInventoryItem(
              agentDid: 'did:agent:bob',
              activeState: 'active',
              payloadJson: '{"name":"Bob agent"}',
            ),
          ],
        ),
      );
      await store.applyDeviceRegistryEpochReset(recovery);

      await store.deleteOwnerData(
        ownerIdentityId: aliceBinding.ownerIdentityId,
        currentDid: recovery.reference.currentDid,
      );

      expect(
        await store.loadConversationOverlay(
          ownerDid: recovery.reference.previousDid,
          threadId: 'alice-old-thread',
        ),
        isNull,
      );
      expect(
        await store.loadAgentInventorySnapshot(binding: aliceBinding),
        isNull,
      );
      expect(
        await store.loadConversationOverlay(
          ownerDid: 'did:wba:awiki.info:users:bob',
          threadId: 'bob-thread',
        ),
        isNotNull,
      );
      expect(
        (await store.loadAgentInventorySnapshot(
          binding: bobBinding,
        ))?.agents.single.agentDid,
        'did:agent:bob',
      );
    },
  );

  test(
    'in-memory domain snapshots preserve atomic empty and isolation semantics',
    () async {
      final store = InMemoryAwikiProductLocalStore();
      const binding = ProductAccountBinding(
        ownerIdentityId: 'owner-identity-1',
        accountId: 'account-1',
      );
      final refreshedAt = DateTime.utc(2026, 7, 28, 8);

      await store.replaceAgentInventorySnapshot(
        ProductAgentInventorySnapshot(
          binding: binding,
          domainVersion: '90071992547409931234567890',
          refreshedAt: refreshedAt,
          agents: const <ProductAgentInventoryItem>[
            ProductAgentInventoryItem(
              agentDid: 'did:agent:inactive',
              activeState: 'inactive',
              payloadJson: '{"name":"Inactive"}',
            ),
          ],
        ),
      );
      await store.replaceAgentStatusSnapshot(
        ProductAgentStatusSnapshot(
          binding: binding,
          domainVersion: '5',
          refreshedAt: refreshedAt,
          statuses: const <ProductAgentStatusItem>[
            ProductAgentStatusItem(
              agentDid: 'did:agent:inactive',
              payloadJson: '{"runtime":"online"}',
            ),
          ],
        ),
      );

      final inputAgents = <ProductAgentInventoryItem>[
        const ProductAgentInventoryItem(
          agentDid: 'did:agent:replacement',
          activeState: 'active',
          payloadJson: '{"name":"Replacement"}',
        ),
      ];
      await store.replaceAgentInventorySnapshot(
        ProductAgentInventorySnapshot(
          binding: binding,
          domainVersion: '90071992547409931234567891',
          refreshedAt: refreshedAt.add(const Duration(minutes: 1)),
          agents: inputAgents,
        ),
      );
      inputAgents.clear();

      final inventory = await store.loadAgentInventorySnapshot(
        binding: binding,
      );
      final status = await store.loadAgentStatusSnapshot(binding: binding);
      expect(inventory?.agents.single.agentDid, 'did:agent:replacement');
      expect(status?.statuses.single.agentDid, 'did:agent:inactive');

      await store.replaceAgentInventorySnapshot(
        ProductAgentInventorySnapshot(
          binding: binding,
          domainVersion: '90071992547409931234567892',
          refreshedAt: refreshedAt.add(const Duration(minutes: 2)),
          agents: const <ProductAgentInventoryItem>[],
        ),
      );
      expect(
        (await store.loadAgentInventorySnapshot(binding: binding))?.agents,
        isEmpty,
      );
      expect(
        (await store.loadAgentStatusSnapshot(binding: binding))?.statuses,
        hasLength(1),
      );

      await store.replaceProfileSnapshot(
        ProductProfileSnapshot(
          binding: binding,
          domainVersion: '2',
          refreshedAt: refreshedAt,
          payloadJson: '{"display_name":"Alice"}',
        ),
      );
      await store.replaceProfileSnapshot(
        ProductProfileSnapshot(
          binding: binding,
          domainVersion: '3',
          refreshedAt: refreshedAt.add(const Duration(minutes: 3)),
        ),
      );
      expect(
        (await store.loadProfileSnapshot(binding: binding))?.payloadJson,
        isNull,
      );

      await store.replaceDeviceRegistrySnapshot(
        ProductDeviceRegistrySnapshot(
          binding: binding,
          epoch: registryEpoch,
          domainVersion: '3',
          refreshedAt: refreshedAt,
          devices: const <ProductDeviceRegistryItem>[
            ProductDeviceRegistryItem(
              protocolDeviceId: 'protocol-device-1',
              authGeneration: '184467440737095516160',
              payloadJson: '{"state":"active"}',
            ),
          ],
        ),
      );
      await store.replaceDeviceRegistrySnapshot(
        ProductDeviceRegistrySnapshot(
          binding: binding,
          epoch: registryEpoch,
          domainVersion: '4',
          refreshedAt: refreshedAt.add(const Duration(minutes: 4)),
          devices: const <ProductDeviceRegistryItem>[],
        ),
      );
      expect(
        (await store.loadDeviceRegistrySnapshot(binding: binding))?.devices,
        isEmpty,
      );
    },
  );

  test(
    'in-memory copy-on-read keeps legacy data and fences account mismatch',
    () async {
      final store = InMemoryAwikiProductLocalStore();
      const legacyOwnerDid = 'did:wba:awiki.ai:alice:e1_old';
      const binding = ProductAccountBinding(
        ownerIdentityId: 'owner-identity-copy',
        accountId: 'account-copy',
      );
      await store.saveAgentState(
        LocalAgentState(
          ownerDid: legacyOwnerDid,
          agentDid: 'did:agent:legacy',
          valueJson: '{"active_state":"inactive"}',
          updatedAt: DateTime.utc(2026, 7, 28, 7),
        ),
      );

      expect(await store.loadAgentInventorySnapshot(binding: binding), isNull);
      final copied = await store.loadAgentInventorySnapshot(
        binding: binding,
        legacyOwnerDid: legacyOwnerDid,
      );
      expect(copied?.domainVersion, '0');
      expect(copied?.payloadHash, productLegacyAgentSeedPayloadHash);
      expect(copied?.agents.single.activeState, 'inactive');
      expect(
        await store.loadAgentStates(ownerDid: legacyOwnerDid),
        hasLength(1),
      );

      const mismatch = ProductAccountBinding(
        ownerIdentityId: 'owner-identity-copy',
        accountId: 'account-other',
      );
      await expectLater(
        store.loadAgentStatusSnapshot(binding: mismatch),
        throwsA(isA<ProductAccountBindingMismatchException>()),
      );
    },
  );

  test(
    'in-memory validation and version failures leave prior snapshot unchanged',
    () async {
      final store = InMemoryAwikiProductLocalStore();
      const binding = ProductAccountBinding(
        ownerIdentityId: 'owner-identity-atomic',
        accountId: 'account-atomic',
      );
      await store.replaceAgentInventorySnapshot(
        ProductAgentInventorySnapshot(
          binding: binding,
          domainVersion: '2',
          refreshedAt: DateTime.utc(2026, 7, 28, 8),
          agents: const <ProductAgentInventoryItem>[
            ProductAgentInventoryItem(
              agentDid: 'did:agent:original',
              activeState: 'active',
              payloadJson: '{"name":"Original"}',
            ),
          ],
        ),
      );

      await expectLater(
        store.replaceAgentInventorySnapshot(
          ProductAgentInventorySnapshot(
            binding: binding,
            domainVersion: '3',
            refreshedAt: DateTime.utc(2026, 7, 28, 9),
            agents: const <ProductAgentInventoryItem>[
              ProductAgentInventoryItem(
                agentDid: 'did:agent:duplicate',
                activeState: 'active',
                payloadJson: '{"name":"One"}',
              ),
              ProductAgentInventoryItem(
                agentDid: 'did:agent:duplicate',
                activeState: 'inactive',
                payloadJson: '{"name":"Two"}',
              ),
            ],
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        store.replaceAgentInventorySnapshot(
          ProductAgentInventorySnapshot(
            binding: binding,
            domainVersion: '1',
            refreshedAt: DateTime.utc(2026, 7, 28, 10),
            agents: const <ProductAgentInventoryItem>[],
          ),
        ),
        throwsA(isA<ProductDomainVersionRegressionException>()),
      );
      await expectLater(
        store.replaceDeviceRegistrySnapshot(
          ProductDeviceRegistrySnapshot(
            binding: binding,
            epoch: registryEpoch,
            domainVersion: '1',
            refreshedAt: DateTime.utc(2026, 7, 28, 10),
            devices: const <ProductDeviceRegistryItem>[
              ProductDeviceRegistryItem(
                protocolDeviceId: 'protocol-device-invalid',
                authGeneration: '01',
                payloadJson: '{"state":"active"}',
              ),
            ],
          ),
        ),
        throwsArgumentError,
      );

      final retained = await store.loadAgentInventorySnapshot(binding: binding);
      expect(retained?.domainVersion, '2');
      expect(retained?.agents.single.agentDid, 'did:agent:original');
    },
  );

  test(
    'in-memory Registry epoch reset requires exact reference and is idempotent',
    () async {
      final store = InMemoryAwikiProductLocalStore();
      const binding = ProductAccountBinding(
        ownerIdentityId: 'owner-identity-recovery',
        accountId: 'account-recovery',
      );
      const previousEpoch = ProductDeviceRegistryEpoch(
        currentDid: 'did:wba:awiki.info:users:alice-old',
        bindingGeneration: '7',
      );
      const currentEpoch = ProductDeviceRegistryEpoch(
        currentDid: 'did:wba:awiki.info:users:alice-new',
        bindingGeneration: '8',
      );
      const reset = ProductDeviceRegistryEpochResetReference(
        accountUserId: 'account-recovery',
        ownerIdentityId: 'owner-identity-recovery',
        previousDid: 'did:wba:awiki.info:users:alice-old',
        currentDid: 'did:wba:awiki.info:users:alice-new',
        bindingGeneration: '8',
      );
      const authorization = ProductDeviceRegistryEpochResetAuthorization(
        reference: reset,
        handle: 'alice.awiki.info',
        sourceKind: ProductIdentityTransitionSourceKind.initiator,
        sourceId: 'recover-001',
      );
      final now = DateTime.utc(2026, 8, 3);

      await store.replaceProfileSnapshot(
        ProductProfileSnapshot(
          binding: binding,
          domainVersion: '12',
          refreshedAt: now,
          payloadJson: '{"display_name":"Alice"}',
        ),
      );
      await store.replaceAgentInventorySnapshot(
        ProductAgentInventorySnapshot(
          binding: binding,
          domainVersion: '15',
          refreshedAt: now,
          agents: const <ProductAgentInventoryItem>[],
        ),
      );
      await store.replaceDeviceRegistrySnapshot(
        ProductDeviceRegistrySnapshot(
          binding: binding,
          epoch: previousEpoch,
          domainVersion: '9',
          refreshedAt: now,
          devices: const <ProductDeviceRegistryItem>[
            ProductDeviceRegistryItem(
              protocolDeviceId: 'old-device',
              authGeneration: '4',
              payloadJson: '{"status":"active"}',
            ),
          ],
        ),
      );

      await expectLater(
        store.replaceDeviceRegistrySnapshot(
          ProductDeviceRegistrySnapshot(
            binding: binding,
            epoch: currentEpoch,
            domainVersion: '1',
            refreshedAt: now,
            devices: const <ProductDeviceRegistryItem>[],
          ),
        ),
        throwsA(isA<ProductDeviceRegistryEpochMismatchException>()),
      );
      expect(
        (await store.loadDeviceRegistrySnapshot(
          binding: binding,
        ))?.devices.single.protocolDeviceId,
        'old-device',
      );

      final receipt = await store.applyDeviceRegistryEpochReset(authorization);
      expect(receipt.reference.currentDid, currentEpoch.currentDid);
      expect(await store.loadDeviceRegistrySnapshot(binding: binding), isNull);
      expect(
        (await store.loadProfileSnapshot(binding: binding))?.domainVersion,
        '12',
      );
      expect(
        (await store.loadAgentInventorySnapshot(
          binding: binding,
        ))?.domainVersion,
        '15',
      );

      await store.replaceDeviceRegistrySnapshot(
        ProductDeviceRegistrySnapshot(
          binding: binding,
          epoch: currentEpoch,
          domainVersion: '1',
          refreshedAt: now,
          devices: const <ProductDeviceRegistryItem>[
            ProductDeviceRegistryItem(
              protocolDeviceId: 'new-device',
              authGeneration: '1',
              payloadJson: '{"status":"active"}',
            ),
          ],
        ),
      );
      final repeated = await store.applyDeviceRegistryEpochReset(authorization);
      expect(repeated.reference.currentDid, currentEpoch.currentDid);
      expect(
        (await store.loadDeviceRegistrySnapshot(
          binding: binding,
        ))?.devices.single.protocolDeviceId,
        'new-device',
      );

      await expectLater(
        store.applyDeviceRegistryEpochReset(
          const ProductDeviceRegistryEpochResetAuthorization(
            reference: reset,
            handle: 'alice.awiki.info',
            sourceKind: ProductIdentityTransitionSourceKind.joinedDevice,
            sourceId: 'join-session-1',
          ),
        ),
        throwsA(isA<ProductDeviceRegistryEpochMismatchException>()),
      );

      await expectLater(
        store.applyDeviceRegistryEpochReset(
          const ProductDeviceRegistryEpochResetAuthorization(
            reference: ProductDeviceRegistryEpochResetReference(
              accountUserId: 'account-recovery',
              ownerIdentityId: 'owner-identity-recovery',
              previousDid: 'did:wba:awiki.info:users:unknown',
              currentDid: 'did:wba:awiki.info:users:alice-next',
              bindingGeneration: '9',
            ),
            handle: 'alice.awiki.info',
            sourceKind: ProductIdentityTransitionSourceKind.joinedDevice,
            sourceId: 'join-session-next',
          ),
        ),
        throwsA(isA<ProductDeviceRegistryEpochMismatchException>()),
      );
    },
  );

  test(
    'exact joined-device authorization establishes an empty Registry epoch',
    () async {
      final store = InMemoryAwikiProductLocalStore();
      const binding = ProductAccountBinding(
        ownerIdentityId: 'owner-identity-fresh-join',
        accountId: 'account-fresh-join',
      );
      const authorization = ProductDeviceRegistryEpochResetAuthorization(
        reference: ProductDeviceRegistryEpochResetReference(
          accountUserId: 'account-fresh-join',
          ownerIdentityId: 'owner-identity-fresh-join',
          previousDid: 'did:wba:awiki.info:users:alice-old',
          currentDid: 'did:wba:awiki.info:users:alice-new',
          bindingGeneration: '8',
        ),
        handle: 'alice.awiki.info',
        sourceKind: ProductIdentityTransitionSourceKind.joinedDevice,
        sourceId: 'join-session-fresh',
      );
      await store.replaceProfileSnapshot(
        ProductProfileSnapshot(
          binding: binding,
          domainVersion: '3',
          refreshedAt: DateTime.utc(2026, 8, 3),
          payloadJson: '{"display_name":"Alice"}',
        ),
      );

      final receipt = await store.applyDeviceRegistryEpochReset(authorization);

      expect(receipt.authorization.sourceId, 'join-session-fresh');
      expect(
        (await store.loadDeviceRegistryEpoch(binding: binding))?.currentDid,
        authorization.reference.currentDid,
      );
      expect(await store.loadDeviceRegistrySnapshot(binding: binding), isNull);
      expect(
        (await store.loadProfileSnapshot(binding: binding))?.domainVersion,
        '3',
      );
    },
  );
}
