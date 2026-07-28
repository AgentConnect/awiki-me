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

  /// Legacy v3 DID-keyed Agent cache. New account-domain reads must use
  /// [loadAgentInventorySnapshot] with an explicit stable binding.
  Future<List<LocalAgentState>> loadAgentStates({required String ownerDid});

  Future<void> saveAgentState(LocalAgentState state);

  Future<void> deleteAgentState({
    required String ownerDid,
    required String agentDid,
  });

  /// Loads the stable-owner Inventory snapshot. [legacyOwnerDid] opts into the
  /// one-way v3 copy-on-read bridge; omitting it never consults DID-keyed rows.
  Future<ProductAgentInventorySnapshot?> loadAgentInventorySnapshot({
    required ProductAccountBinding binding,
    String? legacyOwnerDid,
  });

  Future<void> replaceAgentInventorySnapshot(
    ProductAgentInventorySnapshot snapshot,
  );

  Future<ProductAgentStatusSnapshot?> loadAgentStatusSnapshot({
    required ProductAccountBinding binding,
  });

  Future<void> replaceAgentStatusSnapshot(ProductAgentStatusSnapshot snapshot);

  Future<ProductProfileSnapshot?> loadProfileSnapshot({
    required ProductAccountBinding binding,
  });

  Future<void> replaceProfileSnapshot(ProductProfileSnapshot snapshot);

  Future<ProductDeviceRegistrySnapshot?> loadDeviceRegistrySnapshot({
    required ProductAccountBinding binding,
  });

  Future<void> replaceDeviceRegistrySnapshot(
    ProductDeviceRegistrySnapshot snapshot,
  );
}
