import 'models/product_local_models.dart';

abstract interface class ProductLocalStore {
  Future<void> warmUp();

  Future<ProductConversationOverlay?> loadConversationOverlay({
    required String ownerDid,
    required String threadId,
  });

  Future<ProductConversationOverlay?> loadConversationOverlayByConversationId({
    required String ownerDid,
    required String conversationId,
  });

  Future<Map<String, ProductConversationOverlay>> loadConversationOverlays({
    required String ownerDid,
    Iterable<String>? threadIds,
  });

  Future<Map<String, ProductConversationOverlay>>
  loadConversationOverlaysByConversationId({
    required String ownerDid,
    Iterable<String>? conversationIds,
  });

  Future<void> upsertConversationOverlay(ProductConversationOverlay overlay);

  Future<void> upsertConversationOverlayByConversationId(
    ProductConversationOverlay overlay,
  );

  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    required DateTime updatedAt,
  });

  Future<void> setConversationHidden({
    required String ownerDid,
    required String conversationKey,
    required bool hidden,
    required DateTime updatedAt,
  });

  Future<void> setConversationHiddenByConversationId({
    required String ownerDid,
    required String conversationId,
    required bool hidden,
    required DateTime updatedAt,
  });

  Future<void> deleteConversationOverlay({
    required String ownerDid,
    required String threadId,
  });

  Future<void> deleteConversationOverlayByConversationId({
    required String ownerDid,
    required String conversationId,
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

  Future<List<LocalAgentState>> loadAgentStates({required String ownerDid});

  Future<void> saveAgentState(LocalAgentState state);

  Future<void> deleteAgentState({
    required String ownerDid,
    required String agentDid,
  });
}
