import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'in-memory product store keeps overlays drafts and preferences by owner',
    () async {
      final store = InMemoryAwikiProductLocalStore();
      final now = DateTime.utc(2026, 5, 23);

      await store.upsertConversationOverlay(
        ProductConversationOverlay(
          ownerDid: 'did:alice',
          threadId: 'thread-1',
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
      expect(alice?.effectiveConversationId, 'dm:peer-scope:v1:bob');
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
}
