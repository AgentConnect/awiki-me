import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../app_shell/providers/session_provider.dart';
import '../conversation_list/conversation_provider.dart';

class ChatThreadState {
  const ChatThreadState({
    required this.threadId,
    this.messages = const <ChatMessage>[],
    this.isLoading = false,
  });

  final String threadId;
  final List<ChatMessage> messages;
  final bool isLoading;

  ChatThreadState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
  }) {
    return ChatThreadState(
      threadId: threadId,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ChatThreadsController
    extends StateNotifier<Map<String, ChatThreadState>> {
  ChatThreadsController(this.ref) : super(const <String, ChatThreadState>{});

  final Ref ref;

  ChatThreadState thread(String threadId) {
    return state[threadId] ?? ChatThreadState(threadId: threadId);
  }

  Future<void> openConversation(ConversationSummary conversation) async {
    _setThreadLoading(conversation.threadId, true);
    final history = conversation.isGroup
        ? await ref.read(awikiGatewayProvider).fetchGroupHistory(
              conversation.groupId ?? '',
            )
        : await ref.read(awikiGatewayProvider).fetchDmHistory(
              conversation.targetDid ?? '',
            );
    state = <String, ChatThreadState>{
      ...state,
      conversation.threadId: ChatThreadState(
        threadId: conversation.threadId,
        messages: _sortMessages(history),
        isLoading: false,
      ),
    };
    await ref.read(awikiGatewayProvider).markRead(conversation.threadId);
    await ref.read(conversationListProvider.notifier).refresh();
  }

  Future<void> sendMessage({
    required ConversationSummary conversation,
    required String content,
  }) async {
    final session = ref.read(sessionProvider).session;
    if (session == null || content.trim().isEmpty) {
      return;
    }
    final pending = ChatMessage(
      localId: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      threadId: conversation.threadId,
      senderDid: session.did,
      senderName: session.handle ?? session.displayName,
      receiverDid: conversation.targetDid,
      groupId: conversation.groupId,
      content: content.trim(),
      createdAt: DateTime.now(),
      isMine: true,
      sendState: MessageSendState.sending,
    );
    final current =
        List<ChatMessage>.from(thread(conversation.threadId).messages)
          ..add(pending);
    _setMessages(conversation.threadId, current);
    try {
      final sent = await ref.read(awikiGatewayProvider).sendTextMessage(
            threadId: conversation.threadId,
            peerDid: conversation.targetDid,
            groupId: conversation.groupId,
            content: content.trim(),
          );
      final replaced = current
          .map((item) => item.localId == pending.localId ? sent : item)
          .toList();
      _setMessages(conversation.threadId, replaced);
    } catch (_) {
      final failed = pending.copyWith(sendState: MessageSendState.failed);
      final replaced = current
          .map((item) => item.localId == pending.localId ? failed : item)
          .toList();
      _setMessages(conversation.threadId, replaced);
    }
    await ref.read(conversationListProvider.notifier).refresh();
  }

  Future<void> retryMessage({
    required ConversationSummary conversation,
    required ChatMessage message,
  }) async {
    final retried = await ref.read(awikiGatewayProvider).retryMessage(message);
    final updated = thread(conversation.threadId)
        .messages
        .map((item) => item.localId == message.localId ? retried : item)
        .toList();
    _setMessages(conversation.threadId, updated);
    await ref.read(conversationListProvider.notifier).refresh();
  }

  Future<void> deleteThread(String threadId) async {
    await ref.read(awikiGatewayProvider).deleteLocalThread(threadId);
    final next = Map<String, ChatThreadState>.from(state)..remove(threadId);
    state = next;
    await ref.read(conversationListProvider.notifier).refresh();
  }

  void applyRealtimeUpdate(ChatMessage message) {
    final current = List<ChatMessage>.from(thread(message.threadId).messages);
    final index = current.indexWhere(
      (item) =>
          (message.remoteId != null && item.remoteId == message.remoteId) ||
          item.localId == message.localId,
    );
    if (index >= 0) {
      current[index] = message;
    } else {
      current.add(message);
    }
    _setMessages(message.threadId, current);
  }

  void clear() {
    state = const <String, ChatThreadState>{};
  }

  void _setThreadLoading(String threadId, bool isLoading) {
    final current = thread(threadId);
    state = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(isLoading: isLoading),
    };
  }

  void _setMessages(String threadId, List<ChatMessage> messages) {
    state = <String, ChatThreadState>{
      ...state,
      threadId: ChatThreadState(
        threadId: threadId,
        messages: _sortMessages(messages),
      ),
    };
  }

  List<ChatMessage> _sortMessages(List<ChatMessage> messages) {
    final sorted = List<ChatMessage>.from(messages);
    sorted.sort((a, b) {
      final aSeq = a.serverSequence;
      final bSeq = b.serverSequence;
      if (aSeq != null && bSeq != null && aSeq != bSeq) {
        return aSeq.compareTo(bSeq);
      }
      if (aSeq != null && bSeq == null) {
        return -1;
      }
      if (aSeq == null && bSeq != null) {
        return 1;
      }
      return a.createdAt.compareTo(b.createdAt);
    });
    return sorted;
  }
}

final chatThreadsProvider =
    StateNotifierProvider<ChatThreadsController, Map<String, ChatThreadState>>(
  (ref) => ChatThreadsController(ref),
);

final chatThreadProvider =
    Provider.family<ChatThreadState, String>((ref, threadId) {
  final threads = ref.watch(chatThreadsProvider);
  return threads[threadId] ?? ChatThreadState(threadId: threadId);
});
