import '../../application/models/product_local_models.dart';
import '../../application/product_local_store.dart';

class InMemoryAwikiProductLocalStore implements ProductLocalStore {
  final Map<String, ProductConversationOverlay> _overlays =
      <String, ProductConversationOverlay>{};
  final Map<String, MessageDraft> _drafts = <String, MessageDraft>{};
  final Map<String, LocalUiPreference> _preferences =
      <String, LocalUiPreference>{};
  final Map<String, LocalAgentState> _agentStates = <String, LocalAgentState>{};

  @override
  Future<ProductConversationOverlay?> loadConversationOverlay({
    required String ownerDid,
    required String threadId,
  }) async {
    return _overlays[_compoundKey(ownerDid, threadId)];
  }

  @override
  Future<Map<String, ProductConversationOverlay>> loadConversationOverlays({
    required String ownerDid,
    Iterable<String>? threadIds,
  }) async {
    final allowed = threadIds?.toSet();
    return Map<String, ProductConversationOverlay>.fromEntries(
      _overlays.values
          .where((overlay) => overlay.ownerDid == ownerDid)
          .where(
            (overlay) => allowed == null || allowed.contains(overlay.threadId),
          )
          .map((overlay) => MapEntry(overlay.threadId, overlay)),
    );
  }

  @override
  Future<void> upsertConversationOverlay(
    ProductConversationOverlay overlay,
  ) async {
    _overlays[_compoundKey(overlay.ownerDid, overlay.threadId)] = overlay;
  }

  @override
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    required DateTime updatedAt,
  }) async {
    await setConversationHidden(
      ownerDid: ownerDid,
      conversationKey: threadId,
      hidden: hidden,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> setConversationHidden({
    required String ownerDid,
    required String conversationKey,
    required bool hidden,
    required DateTime updatedAt,
  }) async {
    final key = _compoundKey(ownerDid, conversationKey);
    final existing = _overlays[key];
    _overlays[key] =
        (existing ??
                ProductConversationOverlay(
                  ownerDid: ownerDid,
                  threadId: conversationKey,
                  updatedAt: updatedAt,
                ))
            .copyWith(hidden: hidden, updatedAt: updatedAt);
  }

  @override
  Future<void> deleteConversationOverlay({
    required String ownerDid,
    required String threadId,
  }) async {
    _overlays.remove(_compoundKey(ownerDid, threadId));
  }

  @override
  Future<MessageDraft?> loadDraft({
    required String ownerDid,
    required String threadId,
  }) async {
    return _drafts[_compoundKey(ownerDid, threadId)];
  }

  @override
  Future<void> saveDraft(MessageDraft draft) async {
    _drafts[_compoundKey(draft.ownerDid, draft.threadId)] = draft;
  }

  @override
  Future<void> deleteDraft({
    required String ownerDid,
    required String threadId,
  }) async {
    _drafts.remove(_compoundKey(ownerDid, threadId));
  }

  @override
  Future<LocalUiPreference?> loadUiPreference({
    required String ownerDid,
    required String key,
  }) async {
    return _preferences[_compoundKey(ownerDid, key)];
  }

  @override
  Future<void> saveUiPreference(LocalUiPreference preference) async {
    _preferences[_compoundKey(preference.ownerDid, preference.key)] =
        preference;
  }

  @override
  Future<void> deleteUiPreference({
    required String ownerDid,
    required String key,
  }) async {
    _preferences.remove(_compoundKey(ownerDid, key));
  }

  @override
  Future<List<LocalAgentState>> loadAgentStates({
    required String ownerDid,
  }) async {
    return _agentStates.values
        .where((state) => state.ownerDid == ownerDid)
        .toList();
  }

  @override
  Future<void> saveAgentState(LocalAgentState state) async {
    _agentStates[_compoundKey(state.ownerDid, state.agentDid)] = state;
  }

  @override
  Future<void> deleteAgentState({
    required String ownerDid,
    required String agentDid,
  }) async {
    _agentStates.remove(_compoundKey(ownerDid, agentDid));
  }
}

String _compoundKey(String ownerDid, String id) => '$ownerDid\u0000$id';
