import 'models/product_local_models.dart';

abstract interface class ProductLocalStore {
  Future<ProductConversationOverlay?> loadConversationOverlay({
    required String ownerDid,
    required String threadId,
  });

  Future<Map<String, ProductConversationOverlay>> loadConversationOverlays({
    required String ownerDid,
    Iterable<String>? threadIds,
  });

  Future<void> upsertConversationOverlay(ProductConversationOverlay overlay);

  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    required DateTime updatedAt,
  });

  Future<void> deleteConversationOverlay({
    required String ownerDid,
    required String threadId,
  });

  Future<MessageDraft?> loadDraft({
    required String ownerDid,
    required String threadId,
  });

  Future<void> saveDraft(MessageDraft draft);

  Future<void> deleteDraft({
    required String ownerDid,
    required String threadId,
  });

  Future<LocalUiPreference?> loadUiPreference({
    required String ownerDid,
    required String key,
  });

  Future<void> saveUiPreference(LocalUiPreference preference);

  Future<void> deleteUiPreference({
    required String ownerDid,
    required String key,
  });
}
