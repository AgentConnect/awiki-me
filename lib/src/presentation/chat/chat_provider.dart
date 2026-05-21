import 'dart:async';

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

  ChatThreadState copyWith({List<ChatMessage>? messages, bool? isLoading}) {
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
  static const Duration _pendingMatchWindow = Duration(minutes: 2);
  static const Duration _staleSendingAge = Duration(seconds: 30);
  static const Duration _sendTimeout = Duration(seconds: 20);

  ChatThreadState thread(String threadId) {
    return state[threadId] ?? ChatThreadState(threadId: threadId);
  }

  Future<void> openConversation(ConversationSummary conversation) async {
    final current = thread(conversation.threadId);
    if (_shouldLoadHistory(current, conversation)) {
      unawaited(_loadHistory(conversation));
    }
    if (conversation.unreadCount > 0) {
      ref
          .read(conversationListProvider.notifier)
          .markThreadReadLocal(conversation.threadId);
      unawaited(
        ref
            .read(awikiGatewayProvider)
            .markRead(conversation.threadId)
            .catchError((_) {}),
      );
    }
  }

  Future<void> _loadHistory(ConversationSummary conversation) async {
    if (!mounted) {
      return;
    }
    _setThreadLoading(conversation.threadId, true);
    try {
      final history = conversation.isGroup
          ? await ref
                .read(awikiGatewayProvider)
                .fetchGroupHistory(conversation.groupId ?? '')
          : await ref
                .read(awikiGatewayProvider)
                .fetchDmHistory(conversation.targetDid ?? '');
      if (!mounted) {
        return;
      }
      _mergeMessages(
        conversation.threadId,
        history,
        isLoading: false,
        resolveStaleSending: true,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _setThreadLoading(conversation.threadId, false);
    }
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
    final current = List<ChatMessage>.from(
      thread(conversation.threadId).messages,
    )..add(pending);
    _setMessages(conversation.threadId, current);
    try {
      final sent = await ref
          .read(awikiGatewayProvider)
          .sendTextMessage(
            threadId: conversation.threadId,
            peerDid: conversation.targetDid,
            groupId: conversation.groupId,
            content: content.trim(),
          )
          .timeout(_sendTimeout);
      _replaceMessage(conversation.threadId, pending.localId, sent);
    } catch (_) {
      final failed = pending.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(conversation.threadId, pending.localId, failed);
    }
    await ref.read(conversationListProvider.notifier).refresh();
    final refreshedConversation = _refreshedConversationFor(conversation);
    unawaited(_loadHistory(refreshedConversation));
  }

  Future<void> retryMessage({
    required ConversationSummary conversation,
    required ChatMessage message,
  }) async {
    final retrying = message.copyWith(sendState: MessageSendState.sending);
    _setMessages(
      conversation.threadId,
      thread(conversation.threadId).messages
          .map((item) => item.localId == message.localId ? retrying : item)
          .toList(),
    );
    try {
      final retried = await ref
          .read(awikiGatewayProvider)
          .retryMessage(retrying)
          .timeout(_sendTimeout);
      _replaceMessage(conversation.threadId, message.localId, retried);
    } catch (_) {
      final failed = retrying.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(conversation.threadId, message.localId, failed);
    }
    await ref.read(conversationListProvider.notifier).refresh();
    unawaited(_loadHistory(_refreshedConversationFor(conversation)));
  }

  Future<void> deleteThread(String threadId) async {
    await ref.read(awikiGatewayProvider).deleteLocalThread(threadId);
    final next = Map<String, ChatThreadState>.from(state)..remove(threadId);
    state = next;
    await ref.read(conversationListProvider.notifier).refresh();
  }

  void applyRealtimeUpdate(ChatMessage message) {
    _mergeMessages(message.threadId, <ChatMessage>[message]);
  }

  Future<void> refreshConversation(ConversationSummary conversation) async {
    await ref.read(conversationListProvider.notifier).refresh();
    await _loadHistory(_refreshedConversationFor(conversation));
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

  void _replaceMessage(
    String threadId,
    String localId,
    ChatMessage replacement,
  ) {
    final current = List<ChatMessage>.from(thread(threadId).messages);
    final index = current.indexWhere((item) => item.localId == localId);
    if (index >= 0) {
      current.removeAt(index);
    } else if (replacement.sendState != MessageSendState.sent) {
      return;
    }
    final replacementIndex = _matchingMessageIndex(current, replacement);
    if (replacementIndex >= 0) {
      current[replacementIndex] = replacement;
    } else {
      current.add(replacement);
    }
    _setMessages(threadId, current);
  }

  void _mergeMessages(
    String threadId,
    List<ChatMessage> incoming, {
    bool? isLoading,
    bool resolveStaleSending = false,
  }) {
    final current = List<ChatMessage>.from(thread(threadId).messages);
    for (final message in incoming) {
      final index = _matchingMessageIndex(current, message);
      if (index >= 0) {
        current[index] = message;
      } else {
        current.add(message);
      }
    }
    final messages = resolveStaleSending
        ? _markStaleSendingFailed(current)
        : current;
    state = <String, ChatThreadState>{
      ...state,
      threadId: ChatThreadState(
        threadId: threadId,
        messages: _sortMessages(messages),
        isLoading: isLoading ?? thread(threadId).isLoading,
      ),
    };
  }

  List<ChatMessage> _markStaleSendingFailed(List<ChatMessage> messages) {
    final now = DateTime.now();
    return messages.map((message) {
      if (!message.isMine ||
          message.sendState != MessageSendState.sending ||
          now.difference(message.createdAt) < _staleSendingAge) {
        return message;
      }
      return message.copyWith(sendState: MessageSendState.failed);
    }).toList();
  }

  int _matchingMessageIndex(List<ChatMessage> current, ChatMessage incoming) {
    final remoteId = incoming.remoteId;
    if (remoteId != null && remoteId.isNotEmpty) {
      final remoteIndex = current.indexWhere(
        (item) => item.remoteId == remoteId,
      );
      if (remoteIndex >= 0) {
        return remoteIndex;
      }
    }
    final localIndex = current.indexWhere(
      (item) => item.localId == incoming.localId,
    );
    if (localIndex >= 0) {
      return localIndex;
    }
    if (!incoming.isMine || incoming.sendState != MessageSendState.sent) {
      return -1;
    }
    return current.indexWhere((item) => _isMatchingPending(item, incoming));
  }

  bool _isMatchingPending(ChatMessage pending, ChatMessage sent) {
    if (!pending.isMine ||
        pending.threadId != sent.threadId ||
        pending.content != sent.content ||
        pending.senderDid != sent.senderDid ||
        pending.sendState == MessageSendState.sent) {
      return false;
    }
    final delta = pending.createdAt.difference(sent.createdAt).abs();
    return delta <= _pendingMatchWindow;
  }

  bool _shouldLoadHistory(
    ChatThreadState current,
    ConversationSummary conversation,
  ) {
    if (current.isLoading) {
      return false;
    }
    if (current.messages.isEmpty) {
      return true;
    }
    if (conversation.unreadCount > 0) {
      return true;
    }
    final latestLocalAt = current.messages
        .map((message) => message.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return conversation.lastMessageAt.isAfter(latestLocalAt);
  }

  ConversationSummary _refreshedConversationFor(ConversationSummary fallback) {
    final refreshed = ref
        .read(conversationListProvider)
        .conversations
        .where((item) => item.threadId == fallback.threadId);
    return refreshed.isEmpty ? fallback : refreshed.first;
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

final chatThreadProvider = Provider.family<ChatThreadState, String>((
  ref,
  threadId,
) {
  final threads = ref.watch(chatThreadsProvider);
  return threads[threadId] ?? ChatThreadState(threadId: threadId);
});
