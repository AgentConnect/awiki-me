import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/models/product_local_models.dart';
import '../../application/product_local_store.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../app_shell/providers/session_provider.dart';

/// Device-local presentation tombstones. Never calls the messaging service or
/// changes Core history, outbox, read watermarks, or another device's state.
class LocalMessageDeletions extends StateNotifier<AsyncValue<Set<String>>> {
  LocalMessageDeletions(this.store, this.owner, this.conversationId)
    : super(const AsyncLoading()) {
    ready = _load();
  }

  final ProductLocalStore store;
  final String owner;
  final String conversationId;
  late final Future<void> ready;
  Future<void> _pendingWrite = Future<void>.value();
  String get storageKey => 'deleted-messages:v1:$conversationId';

  Future<void> _load() async {
    try {
      final saved = await store.loadUiPreference(
        ownerDid: owner,
        key: storageKey,
      );
      final values = saved == null
          ? <dynamic>[]
          : jsonDecode(saved.valueJson) as List;
      if (mounted) state = AsyncData(values.cast<String>().toSet());
    } catch (error, stack) {
      if (mounted) state = AsyncError(error, stack);
    }
  }

  Future<void> delete(Iterable<ChatMessage> messages) {
    final ids = messages.expand(messageDeletionKeys).toSet();
    final operation = _pendingWrite.then((_) async {
      await ready;
      if (!mounted) return;
      final previous = state.requireValue;
      final next = {...previous, ...ids};
      await store.saveUiPreference(
        LocalUiPreference(
          ownerDid: owner,
          key: storageKey,
          valueJson: jsonEncode(next.toList()..sort()),
          updatedAt: DateTime.now(),
        ),
      );
      if (mounted) state = AsyncData(next);
    });
    _pendingWrite = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }
}

Set<String> messageDeletionKeys(ChatMessage message) => {
  message.localId,
  if (message.remoteId?.isNotEmpty == true) message.remoteId!,
  ...message.identityAliases,
};

bool isMessageLocallyDeleted(ChatMessage message, Set<String> deleted) =>
    messageDeletionKeys(message).any(deleted.contains);

ConversationSummary withoutLocallyDeletedPreview(
  ConversationSummary conversation,
  AsyncValue<Set<String>> deletions,
) {
  final last = conversation.lastMessageSnapshot;
  final ids = deletions.asData?.value;
  if (ids != null && (last == null || !isMessageLocallyDeleted(last, ids))) {
    return conversation;
  }
  return conversation.copyWith(
    lastMessagePreview: '',
    lastMessageSnapshot: null,
    lastMessagePayloadJson: null,
  );
}

final localMessageDeletionsProvider =
    StateNotifierProvider.family<
      LocalMessageDeletions,
      AsyncValue<Set<String>>,
      String
    >((ref, conversationId) {
      // Recreate on owner/generation and on storage scope replacement. Old async
      // completions cannot publish into the new owner's notifier.
      final epoch = ref.watch(
        sessionProvider.select((value) => value.activeEpoch),
      );
      return LocalMessageDeletions(
        ref.watch(productLocalStoreProvider),
        epoch?.ownerDid ?? '',
        conversationId,
      );
    });
