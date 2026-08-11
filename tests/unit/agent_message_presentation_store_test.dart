import 'dart:convert';

import 'package:awiki_me/src/application/agent_message_presentation_store.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ownerA = AgentMessagePresentationOwnerScope(
    ownerIdentityId: 'identity-a',
    accountId: 'account-a',
  );
  final ownerB = AgentMessagePresentationOwnerScope(
    ownerIdentityId: 'identity-a',
    accountId: 'account-b',
  );
  final now = DateTime.utc(2026, 8, 11, 12);

  test('owner/account scope hashes private account material', () {
    expect(ownerA.storageOwnerKey, isNot(contains('account-a')));
    expect(ownerA.storageOwnerKey, isNot(contains('identity-a')));
    expect(ownerA.storageOwnerKey, hasLength(64));
    expect(ownerA.storageOwnerKey, isNot(ownerB.storageOwnerKey));
  });

  test(
    'receipt claim persists owner/event/full digests and is exact-once',
    () async {
      final local = InMemoryAwikiProductLocalStore();
      final store = AgentMessagePresentationStore(local);
      final first = await store.claim(
        owner: ownerA,
        eventId: 'evt_task_20260811_001',
        senderDid: 'did:test:sender-a',
        now: now,
      );
      final replay = await store.claim(
        owner: ownerA,
        eventId: 'evt_task_20260811_001',
        senderDid: 'did:test:sender-a',
        now: now.add(const Duration(minutes: 1)),
      );
      expect(first.isNew, isTrue);
      expect(first.receipt!.ownerHash, hasLength(64));
      expect(first.receipt!.eventHash, hasLength(64));
      expect(first.receipt!.fullDigest, hasLength(64));
      expect(replay.isNew, isFalse);
      expect(replay.receipt!.nativeId, first.receipt!.nativeId);

      final raw = await local.loadUiPreference(
        ownerDid: ownerA.storageOwnerKey,
        key: 'agent_message_presentation_receipts.v1',
      );
      expect(raw!.valueJson, isNot(contains('evt_task_20260811_001')));
      expect(raw.valueJson, isNot(contains('account-a')));
      expect(raw.valueJson, isNot(contains('did:test:sender-a')));
    },
  );

  test('concurrent claims serialize read-modify-write without loss', () async {
    final store = AgentMessagePresentationStore(
      InMemoryAwikiProductLocalStore(),
    );
    final claims = await Future.wait(<Future<AgentMessagePresentationClaim>>[
      store.claim(
        owner: ownerA,
        eventId: 'event-0001',
        senderDid: 'did:test:sender-a',
        now: now,
      ),
      store.claim(
        owner: ownerA,
        eventId: 'event-0002',
        senderDid: 'did:test:sender-a',
        now: now,
      ),
      store.claim(
        owner: ownerA,
        eventId: 'event-0003',
        senderDid: 'did:test:sender-a',
        now: now,
      ),
    ]);
    expect(claims.every((claim) => claim.isNew), isTrue);
    for (var index = 1; index <= 3; index += 1) {
      final replay = await store.claim(
        owner: ownerA,
        eventId: 'event-000$index',
        senderDid: 'did:test:sender-a',
        now: now,
      );
      expect(replay.isNew, isFalse);
    }
  });

  test(
    'native ID collision fails closed without replacing first claim',
    () async {
      final store = AgentMessagePresentationStore(
        InMemoryAwikiProductLocalStore(),
        nativeIdDeriver: (_) => 73,
      );
      final first = await store.claim(
        owner: ownerA,
        eventId: 'event-0001',
        senderDid: 'did:test:sender-a',
        now: now,
      );
      final collision = await store.claim(
        owner: ownerA,
        eventId: 'event-0002',
        senderDid: 'did:test:sender-a',
        now: now,
      );
      expect(first.isNew, isTrue);
      expect(collision.isCollision, isTrue);
      final replay = await store.claim(
        owner: ownerA,
        eventId: 'event-0001',
        senderDid: 'did:test:sender-a',
        now: now,
      );
      expect(replay.receipt!.nativeId, 73);
    },
  );

  test(
    'terminal disposition is monotonic and repeated outcome is idempotent',
    () async {
      final store = AgentMessagePresentationStore(
        InMemoryAwikiProductLocalStore(),
      );
      await store.claim(
        owner: ownerA,
        eventId: 'event-0001',
        senderDid: 'did:test:sender-a',
        now: now,
      );
      await store.markDisposition(
        owner: ownerA,
        eventId: 'event-0001',
        disposition: AgentMessageReceiptDisposition.presentedApp,
        now: now,
      );
      await store.markDisposition(
        owner: ownerA,
        eventId: 'event-0001',
        disposition: AgentMessageReceiptDisposition.presentedApp,
        now: now.add(const Duration(minutes: 1)),
      );
      await expectLater(
        store.markDisposition(
          owner: ownerA,
          eventId: 'event-0001',
          disposition: AgentMessageReceiptDisposition.downgradedNormal,
          now: now.add(const Duration(minutes: 2)),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'provider deferral is terminal and cannot be rewritten by a late sync',
    () async {
      final store = AgentMessagePresentationStore(
        InMemoryAwikiProductLocalStore(),
      );
      await store.claim(
        owner: ownerA,
        eventId: 'event-provider-deferred-0001',
        senderDid: 'did:test:sender-a',
        now: now,
      );
      await store.markDisposition(
        owner: ownerA,
        eventId: 'event-provider-deferred-0001',
        disposition: AgentMessageReceiptDisposition.deferredProvider,
        now: now,
      );

      final replay = await store.claim(
        owner: ownerA,
        eventId: 'event-provider-deferred-0001',
        senderDid: 'did:test:sender-a',
        now: now.add(const Duration(minutes: 1)),
      );

      expect(replay.isNew, isFalse);
      expect(replay.receipt!.isTerminal, isTrue);
      expect(
        replay.receipt!.disposition,
        AgentMessageReceiptDisposition.deferredProvider,
      );
      await expectLater(
        store.markDisposition(
          owner: ownerA,
          eventId: 'event-provider-deferred-0001',
          disposition: AgentMessageReceiptDisposition.providerPresented,
          now: now.add(const Duration(minutes: 2)),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'cleanup expires terminal only and terminal capacity never removes claims',
    () async {
      final local = InMemoryAwikiProductLocalStore();
      final store = AgentMessagePresentationStore(local, maxReceipts: 2);
      for (var index = 1; index <= 4; index += 1) {
        final eventId = 'event-000$index';
        await store.claim(
          owner: ownerA,
          eventId: eventId,
          senderDid: 'did:test:sender-a',
          now: now,
        );
        if (index <= 3) {
          await store.markDisposition(
            owner: ownerA,
            eventId: eventId,
            disposition: AgentMessageReceiptDisposition.presentedApp,
            now: now.add(Duration(minutes: index)),
          );
        }
      }

      final nonterminalReplay = await store.claim(
        owner: ownerA,
        eventId: 'event-0004',
        senderDid: 'did:test:sender-a',
        now: now.add(const Duration(days: 30)),
      );
      expect(nonterminalReplay.isNew, isFalse);
      final evictedTerminal = await store.claim(
        owner: ownerA,
        eventId: 'event-0001',
        senderDid: 'did:test:sender-a',
        now: now.add(const Duration(days: 30)),
      );
      expect(evictedTerminal.isNew, isTrue);
    },
  );

  test(
    'full nonterminal capacity fails closed without deleting claims',
    () async {
      final store = AgentMessagePresentationStore(
        InMemoryAwikiProductLocalStore(),
        maxReceipts: 2,
      );
      await store.claim(
        owner: ownerA,
        eventId: 'event-0001',
        senderDid: 'did:test:sender-a',
        now: now,
      );
      await store.claim(
        owner: ownerA,
        eventId: 'event-0002',
        senderDid: 'did:test:sender-a',
        now: now,
      );
      await expectLater(
        store.claim(
          owner: ownerA,
          eventId: 'event-0003',
          senderDid: 'did:test:sender-a',
          now: now,
        ),
        throwsStateError,
      );
      expect(
        (await store.claim(
          owner: ownerA,
          eventId: 'event-0001',
          senderDid: 'did:test:sender-a',
          now: now,
        )).isNew,
        isFalse,
      );
      expect(
        (await store.claim(
          owner: ownerA,
          eventId: 'event-0002',
          senderDid: 'did:test:sender-a',
          now: now,
        )).isNew,
        isFalse,
      );
    },
  );

  test('corrupt or mismatched ledger fails closed', () async {
    final local = InMemoryAwikiProductLocalStore();
    await local.saveUiPreference(
      LocalUiPreference(
        ownerDid: ownerA.storageOwnerKey,
        key: 'agent_message_presentation_receipts.v1',
        valueJson: jsonEncode(<String, Object?>{
          'version': 1,
          'owner_hash': ownerB.ownerHash,
          'receipts': <Object?>[],
        }),
        updatedAt: now,
      ),
    );
    final store = AgentMessagePresentationStore(local);
    await expectLater(
      store.claim(
        owner: ownerA,
        eventId: 'event-0001',
        senderDid: 'did:test:sender-a',
        now: now,
      ),
      throwsStateError,
    );
  });

  test(
    'recent urgent counts use only presented terminal sender hashes',
    () async {
      final store = AgentMessagePresentationStore(
        InMemoryAwikiProductLocalStore(),
      );
      for (final entry in <({String event, String sender, bool presented})>[
        (
          event: 'event-rate-0001',
          sender: 'did:test:sender-a',
          presented: true,
        ),
        (
          event: 'event-rate-0002',
          sender: 'did:test:sender-a',
          presented: false,
        ),
        (
          event: 'event-rate-0003',
          sender: 'did:test:sender-b',
          presented: true,
        ),
      ]) {
        await store.claim(
          owner: ownerA,
          eventId: entry.event,
          senderDid: entry.sender,
          now: now.subtract(const Duration(minutes: 5)),
        );
        await store.markDisposition(
          owner: ownerA,
          eventId: entry.event,
          disposition: entry.presented
              ? AgentMessageReceiptDisposition.presentedApp
              : AgentMessageReceiptDisposition.downgradedNormal,
          now: now.subtract(const Duration(minutes: 4)),
        );
      }
      final counts = await store.recentUrgentPresentationCounts(
        owner: ownerA,
        senderDid: 'did:test:sender-a',
        since: now.subtract(const Duration(minutes: 15)),
        now: now,
      );
      expect(counts.senderCount, 1);
      expect(counts.accountCount, 2);
    },
  );
}
