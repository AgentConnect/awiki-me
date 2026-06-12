import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/models/attachment_models.dart';
import '../../application/models/app_thread_ref.dart';
import '../../domain/entities/chat_attachment.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../app_shell/providers/session_provider.dart';
import '../conversation_list/conversation_provider.dart';

class ChatThreadState {
  const ChatThreadState({
    required this.threadId,
    this.messages = const <ChatMessage>[],
    this.isLoading = false,
    this.agentPendingTurns = const <AgentPendingTurn>[],
  });

  final String threadId;
  final List<ChatMessage> messages;
  final bool isLoading;
  final List<AgentPendingTurn> agentPendingTurns;

  bool get isAgentProcessing => agentPendingTurns.any((turn) => turn.isActive);

  bool get isAgentProcessingOverdue =>
      agentPendingTurns.any((turn) => turn.isActive && turn.isOverdue);

  int get pendingAgentReplyCount =>
      agentPendingTurns.where((turn) => turn.isActive).length;

  AgentPendingTurn? pendingAgentTurnForMessage(ChatMessage message) {
    for (final turn in agentPendingTurns) {
      if (turn.matchesMessage(message)) {
        return turn;
      }
    }
    return null;
  }

  ChatThreadState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    List<AgentPendingTurn>? agentPendingTurns,
  }) {
    return ChatThreadState(
      threadId: threadId,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      agentPendingTurns: agentPendingTurns ?? this.agentPendingTurns,
    );
  }
}

class AgentPendingTurn {
  const AgentPendingTurn({
    required this.agentDid,
    required this.localMessageId,
    required this.startedAt,
    this.remoteMessageId,
    this.isOverdue = false,
  });

  final String agentDid;
  final String localMessageId;
  final String? remoteMessageId;
  final DateTime startedAt;
  final bool isOverdue;

  bool get isActive =>
      agentDid.trim().isNotEmpty && localMessageId.trim().isNotEmpty;

  bool matchesMessage(ChatMessage message) {
    if (message.localId == localMessageId) {
      return true;
    }
    final remote = remoteMessageId?.trim();
    return remote != null &&
        remote.isNotEmpty &&
        message.remoteId?.trim() == remote;
  }

  AgentPendingTurn withRemoteMessageId(String? remoteMessageId) {
    final normalized = remoteMessageId?.trim();
    if (normalized == null ||
        normalized.isEmpty ||
        normalized == this.remoteMessageId) {
      return this;
    }
    return AgentPendingTurn(
      agentDid: agentDid,
      localMessageId: localMessageId,
      remoteMessageId: normalized,
      startedAt: startedAt,
      isOverdue: isOverdue,
    );
  }

  AgentPendingTurn markOverdue() {
    if (isOverdue) {
      return this;
    }
    return AgentPendingTurn(
      agentDid: agentDid,
      localMessageId: localMessageId,
      remoteMessageId: remoteMessageId,
      startedAt: startedAt,
      isOverdue: true,
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
  static const Duration _attachmentSendTimeout = Duration(minutes: 3);
  static const Duration _attachmentStaleSendingAge = Duration(
    minutes: 3,
    seconds: 30,
  );
  static const Duration agentProcessingOverdueAfter = Duration(seconds: 75);
  static const Duration _agentProcessingReplyClockSkew = Duration(seconds: 2);

  final Map<String, Timer> _agentProcessingTimers = <String, Timer>{};

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
      _markThreadReadBestEffort(conversation.threadId);
    }
  }

  void _markThreadReadBestEffort(String threadId) {
    try {
      final operation = ref
          .read(conversationServiceProvider)
          .markThreadRead(AppThreadRef.thread(threadId));
      unawaited(operation.catchError((_) {}));
    } catch (_) {
      // IM Core does not expose thread-level read-state yet, and the adapter can
      // throw UnsupportedError synchronously. Opening a conversation must still
      // clear unread locally and continue rendering messages.
    }
  }

  Future<void> _loadHistory(ConversationSummary conversation) async {
    if (!mounted) {
      return;
    }
    _setThreadLoading(conversation.threadId, true);
    try {
      final history =
          (await ref
                  .read(messagingServiceProvider)
                  .loadHistory(_historyThreadRefFor(conversation)))
              .map((message) => _withThreadId(message, conversation.threadId))
              .where((message) => message.hasRenderableContent)
              .toList();
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
    String? expectedAgentReplyDid,
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
    final pendingConversation = _withConversationPreview(conversation, pending);
    ref
        .read(conversationListProvider.notifier)
        .upsertConversation(pendingConversation);
    _startAgentProcessingIfNeeded(
      conversation: pendingConversation,
      expectedAgentReplyDid: expectedAgentReplyDid,
      localMessageId: pending.localId,
      remoteMessageId: pending.remoteId,
      startedAt: pending.createdAt,
    );
    var latestConversation = pendingConversation;
    try {
      final sent = await ref
          .read(messagingServiceProvider)
          .sendText(
            thread: _sendThreadRefFor(conversation),
            content: content.trim(),
          )
          .timeout(_sendTimeout);
      final sentInThread = _withThreadId(sent, conversation.threadId);
      _replaceMessage(conversation.threadId, pending.localId, sentInThread);
      _bindAgentPendingTurnMessageId(
        conversation.threadId,
        localMessageId: pending.localId,
        remoteMessageId: sentInThread.remoteId ?? sentInThread.localId,
      );
      latestConversation = _withConversationPreview(conversation, sentInThread);
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(latestConversation);
    } catch (_) {
      final failed = pending.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(conversation.threadId, pending.localId, failed);
      _removeAgentPendingTurn(
        conversation.threadId,
        localMessageId: pending.localId,
      );
      latestConversation = _withConversationPreview(conversation, failed);
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(latestConversation);
    }
    await _refreshConversationsBestEffort();
    final refreshedConversation = _newerConversation(
      _refreshedConversationFor(latestConversation),
      latestConversation,
    );
    ref
        .read(conversationListProvider.notifier)
        .upsertConversation(refreshedConversation);
    unawaited(_loadHistory(refreshedConversation));
  }

  Future<void> sendAttachment({
    required ConversationSummary conversation,
    required AttachmentDraft attachment,
    String? caption,
    String? expectedAgentReplyDid,
  }) async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      return;
    }
    final normalizedCaption = _normalizedOptionalText(caption);
    final pendingId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final pendingAttachment = ChatAttachment(
      attachmentId: pendingId,
      filename: attachment.displayName,
      mimeType: attachment.mimeType,
      sizeBytes: attachment.sizeBytes,
      caption: normalizedCaption,
      localPath: attachment.localPath,
      hasLocalSource: true,
    );
    final pending = ChatMessage(
      localId: pendingId,
      threadId: conversation.threadId,
      senderDid: session.did,
      senderName: session.handle ?? session.displayName,
      receiverDid: conversation.targetDid,
      groupId: conversation.groupId,
      content: pendingAttachment.caption ?? '',
      originalType: 'application/anp-attachment-manifest+json',
      createdAt: DateTime.now(),
      isMine: true,
      sendState: MessageSendState.sending,
      attachment: pendingAttachment,
    );
    final current = List<ChatMessage>.from(
      thread(conversation.threadId).messages,
    )..add(pending);
    _setMessages(conversation.threadId, current);
    final pendingConversation = _withConversationPreview(conversation, pending);
    ref
        .read(conversationListProvider.notifier)
        .upsertConversation(pendingConversation);
    _startAgentProcessingIfNeeded(
      conversation: pendingConversation,
      expectedAgentReplyDid: expectedAgentReplyDid,
      localMessageId: pending.localId,
      remoteMessageId: pending.remoteId,
      startedAt: pending.createdAt,
    );
    var latestConversation = pendingConversation;
    try {
      final sent = await ref
          .read(messagingServiceProvider)
          .sendAttachment(
            thread: _sendThreadRefFor(conversation),
            attachment: attachment,
            caption: normalizedCaption,
            idempotencyKey: pending.localId,
          )
          .timeout(_attachmentSendTimeout);
      final sentInThread = _withThreadId(sent, conversation.threadId);
      _replaceMessage(conversation.threadId, pending.localId, sentInThread);
      _bindAgentPendingTurnMessageId(
        conversation.threadId,
        localMessageId: pending.localId,
        remoteMessageId: sentInThread.remoteId ?? sentInThread.localId,
      );
      latestConversation = _withConversationPreview(conversation, sentInThread);
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(latestConversation);
    } catch (_) {
      final failed = pending.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(conversation.threadId, pending.localId, failed);
      _removeAgentPendingTurn(
        conversation.threadId,
        localMessageId: pending.localId,
      );
      latestConversation = _withConversationPreview(conversation, failed);
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(latestConversation);
    }
    await _refreshConversationsBestEffort();
    final refreshedConversation = _newerConversation(
      _refreshedConversationFor(latestConversation),
      latestConversation,
    );
    ref
        .read(conversationListProvider.notifier)
        .upsertConversation(refreshedConversation);
    unawaited(_loadHistory(refreshedConversation));
  }

  Future<AttachmentDownloadResult> downloadAttachment({
    required ConversationSummary conversation,
    required ChatMessage message,
  }) {
    final attachment = message.attachment;
    final messageId = message.remoteId ?? message.localId;
    if (attachment == null || messageId.trim().isEmpty) {
      throw StateError('Cannot download this attachment message.');
    }
    return ref
        .read(messagingServiceProvider)
        .downloadAttachment(
          thread: _historyThreadRefFor(conversation),
          messageId: messageId,
          attachmentId: attachment.attachmentId,
        );
  }

  Future<void> retryMessage({
    required ConversationSummary conversation,
    required ChatMessage message,
  }) async {
    if (message.isAttachmentMessage) {
      await retryAttachment(conversation: conversation, message: message);
      return;
    }
    final retrying = message.copyWith(sendState: MessageSendState.sending);
    _setMessages(
      conversation.threadId,
      thread(conversation.threadId).messages
          .map((item) => item.localId == message.localId ? retrying : item)
          .toList(),
    );
    try {
      final retried = await ref
          .read(messagingServiceProvider)
          .retryByResendOriginalContent(retrying)
          .timeout(_sendTimeout);
      _replaceMessage(
        conversation.threadId,
        message.localId,
        _withThreadId(retried, conversation.threadId),
      );
    } catch (_) {
      final failed = retrying.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(conversation.threadId, message.localId, failed);
    }
    await _refreshConversationsBestEffort();
    unawaited(_loadHistory(_refreshedConversationFor(conversation)));
  }

  Future<void> retryAttachment({
    required ConversationSummary conversation,
    required ChatMessage message,
  }) async {
    final attachment = message.attachment;
    final localPath = attachment?.localPath?.trim();
    if (attachment == null || localPath == null || localPath.isEmpty) {
      final failed = message.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(conversation.threadId, message.localId, failed);
      return;
    }
    final retrying = message.copyWith(sendState: MessageSendState.sending);
    _setMessages(
      conversation.threadId,
      thread(conversation.threadId).messages
          .map((item) => item.localId == message.localId ? retrying : item)
          .toList(),
    );
    try {
      final retried = await ref
          .read(messagingServiceProvider)
          .sendAttachment(
            thread: _sendThreadRefFor(conversation),
            attachment: AttachmentDraft(
              filename: attachment.filename,
              mimeType: attachment.mimeType,
              localPath: localPath,
              sizeBytes: attachment.sizeBytes,
            ),
            caption: attachment.caption,
            idempotencyKey: message.localId,
          )
          .timeout(_attachmentSendTimeout);
      _replaceMessage(
        conversation.threadId,
        message.localId,
        _withThreadId(retried, conversation.threadId),
      );
    } catch (_) {
      final failed = retrying.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(conversation.threadId, message.localId, failed);
    }
    await _refreshConversationsBestEffort();
    unawaited(_loadHistory(_refreshedConversationFor(conversation)));
  }

  Future<void> deleteThread(String threadId) async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      throw StateError('No active awiki session. Please sign in first.');
    }
    await ref
        .read(conversationServiceProvider)
        .setThreadHidden(
          ownerDid: session.did,
          threadId: threadId,
          hidden: true,
        );
    final next = Map<String, ChatThreadState>.from(state)..remove(threadId);
    state = next;
    await ref.read(conversationListProvider.notifier).refresh();
  }

  void applyRealtimeUpdate(ChatMessage message) {
    _mergeMessages(message.threadId, <ChatMessage>[
      message,
    ], trustIncomingAgentReply: true);
  }

  Future<void> refreshConversation(ConversationSummary conversation) async {
    await ref.read(conversationListProvider.notifier).refresh();
    await _loadHistory(_refreshedConversationFor(conversation));
  }

  Future<void> _refreshConversationsBestEffort() async {
    try {
      await ref.read(conversationListProvider.notifier).refresh();
    } catch (_) {
      // The local thread has already been updated with the send result. A
      // follow-up conversation-list refresh should not turn a completed send
      // into a visible low-level SDK error.
    }
  }

  void clear() {
    _cancelAgentProcessingTimers();
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
    final current = thread(threadId);
    state = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(messages: _sortMessages(messages)),
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
    bool trustIncomingAgentReply = false,
  }) {
    final current = List<ChatMessage>.from(thread(threadId).messages);
    final newlyMergedMessages = <ChatMessage>[];
    for (final message in incoming.where(
      (message) => message.hasRenderableContent,
    )) {
      final index = _matchingMessageIndex(current, message);
      if (index >= 0) {
        current[index] = message;
      } else {
        current.add(message);
        newlyMergedMessages.add(message);
      }
    }
    final messages = resolveStaleSending
        ? _markStaleSendingFailed(current)
        : current;
    final previous = thread(threadId);
    final nextAgentPendingTurns = _nextAgentPendingTurnsAfterMerge(
      previous.agentPendingTurns,
      newlyMergedMessages,
      trustIncomingAgentReply: trustIncomingAgentReply,
    );
    state = <String, ChatThreadState>{
      ...state,
      threadId: ChatThreadState(
        threadId: threadId,
        messages: _sortMessages(messages),
        isLoading: isLoading ?? previous.isLoading,
        agentPendingTurns: nextAgentPendingTurns,
      ),
    };
    if (nextAgentPendingTurns.isEmpty) {
      _cancelAgentProcessingTimer(threadId);
    } else {
      _scheduleAgentProcessingOverdue(threadId);
    }
  }

  void _startAgentProcessingIfNeeded({
    required ConversationSummary conversation,
    required String? expectedAgentReplyDid,
    required String localMessageId,
    required String? remoteMessageId,
    required DateTime startedAt,
  }) {
    final agentDid = expectedAgentReplyDid?.trim();
    if (conversation.isGroup ||
        agentDid == null ||
        agentDid.isEmpty ||
        localMessageId.trim().isEmpty) {
      return;
    }
    final threadId = conversation.threadId;
    final current = thread(threadId);
    final nextTurns = <AgentPendingTurn>[
      ...current.agentPendingTurns.where(
        (turn) =>
            turn.localMessageId != localMessageId &&
            (remoteMessageId == null ||
                turn.remoteMessageId != remoteMessageId),
      ),
      AgentPendingTurn(
        agentDid: agentDid,
        localMessageId: localMessageId,
        remoteMessageId: remoteMessageId,
        startedAt: startedAt,
      ),
    ];
    state = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(agentPendingTurns: nextTurns),
    };
    _scheduleAgentProcessingOverdue(threadId);
  }

  void _bindAgentPendingTurnMessageId(
    String threadId, {
    required String localMessageId,
    required String? remoteMessageId,
  }) {
    final normalizedRemoteId = remoteMessageId?.trim();
    if (normalizedRemoteId == null || normalizedRemoteId.isEmpty) {
      return;
    }
    final current = thread(threadId);
    var changed = false;
    final nextTurns = current.agentPendingTurns.map((turn) {
      if (turn.localMessageId != localMessageId) {
        return turn;
      }
      final next = turn.withRemoteMessageId(normalizedRemoteId);
      changed = changed || next != turn;
      return next;
    }).toList();
    if (!changed) {
      return;
    }
    state = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(agentPendingTurns: nextTurns),
    };
  }

  void _removeAgentPendingTurn(
    String threadId, {
    required String localMessageId,
  }) {
    final current = thread(threadId);
    final nextTurns = current.agentPendingTurns
        .where((turn) => turn.localMessageId != localMessageId)
        .toList();
    if (nextTurns.length == current.agentPendingTurns.length) {
      return;
    }
    state = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(agentPendingTurns: nextTurns),
    };
    if (nextTurns.isEmpty) {
      _cancelAgentProcessingTimer(threadId);
    } else {
      _scheduleAgentProcessingOverdue(threadId);
    }
  }

  List<AgentPendingTurn> _nextAgentPendingTurnsAfterMerge(
    List<AgentPendingTurn> current,
    List<ChatMessage> incoming, {
    required bool trustIncomingAgentReply,
  }) {
    if (current.isEmpty) {
      return current;
    }
    final next = List<AgentPendingTurn>.from(current);
    for (final message in incoming) {
      if (message.isMine || !message.hasRenderableContent) {
        continue;
      }
      final senderDid = message.senderDid.trim();
      if (senderDid.isEmpty) {
        continue;
      }
      final index = next.indexWhere((turn) {
        if (turn.agentDid.trim() != senderDid) {
          return false;
        }
        if (trustIncomingAgentReply) {
          return true;
        }
        return !message.createdAt.isBefore(
          turn.startedAt.subtract(_agentProcessingReplyClockSkew),
        );
      });
      if (index >= 0) {
        next.removeAt(index);
      }
    }
    return next;
  }

  void _scheduleAgentProcessingOverdue(String threadId) {
    _cancelAgentProcessingTimer(threadId);
    final current = state[threadId];
    if (current == null || current.agentPendingTurns.isEmpty) {
      return;
    }
    final now = DateTime.now();
    Duration? nextDelay;
    for (final turn in current.agentPendingTurns) {
      if (!turn.isActive || turn.isOverdue) {
        continue;
      }
      final delay = turn.startedAt
          .add(agentProcessingOverdueAfter)
          .difference(now);
      if (nextDelay == null || delay < nextDelay) {
        nextDelay = delay;
      }
    }
    if (nextDelay == null) {
      return;
    }
    if (nextDelay.isNegative) {
      nextDelay = Duration.zero;
    }
    _agentProcessingTimers[threadId] = Timer(nextDelay, () {
      _agentProcessingTimers.remove(threadId);
      if (!mounted) {
        return;
      }
      final current = state[threadId];
      if (current == null || current.agentPendingTurns.isEmpty) {
        return;
      }
      final now = DateTime.now();
      var changed = false;
      final nextTurns = current.agentPendingTurns.map((turn) {
        if (turn.isOverdue ||
            now.isBefore(turn.startedAt.add(agentProcessingOverdueAfter))) {
          return turn;
        }
        changed = true;
        return turn.markOverdue();
      }).toList();
      if (!changed) {
        _scheduleAgentProcessingOverdue(threadId);
        return;
      }
      state = <String, ChatThreadState>{
        ...state,
        threadId: current.copyWith(agentPendingTurns: nextTurns),
      };
      _scheduleAgentProcessingOverdue(threadId);
    });
  }

  void _cancelAgentProcessingTimer(String threadId) {
    _agentProcessingTimers.remove(threadId)?.cancel();
  }

  void _cancelAgentProcessingTimers() {
    for (final timer in _agentProcessingTimers.values) {
      timer.cancel();
    }
    _agentProcessingTimers.clear();
  }

  @override
  void dispose() {
    _cancelAgentProcessingTimers();
    super.dispose();
  }

  List<ChatMessage> _markStaleSendingFailed(List<ChatMessage> messages) {
    final now = DateTime.now();
    return messages.map((message) {
      if (!message.isMine ||
          message.sendState != MessageSendState.sending ||
          now.difference(message.createdAt) < _staleSendingAgeFor(message)) {
        return message;
      }
      return message.copyWith(sendState: MessageSendState.failed);
    }).toList();
  }

  Duration _staleSendingAgeFor(ChatMessage message) {
    return message.isAttachmentMessage
        ? _attachmentStaleSendingAge
        : _staleSendingAge;
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
        pending.previewText != sent.previewText ||
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
        .where((item) => _sameConversationTarget(item, fallback));
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

ConversationSummary _withConversationPreview(
  ConversationSummary conversation,
  ChatMessage message,
) {
  return conversation.copyWith(
    lastMessagePreview: message.previewText,
    lastMessageAt: message.createdAt,
    unreadCount: message.isMine ? 0 : conversation.unreadCount,
    lastMessagePayloadJson: conversation.lastMessagePayloadJson,
  );
}

ConversationSummary _newerConversation(
  ConversationSummary first,
  ConversationSummary second,
) {
  return first.lastMessageAt.isBefore(second.lastMessageAt) ? second : first;
}

bool _sameConversationTarget(
  ConversationSummary first,
  ConversationSummary second,
) {
  if (first.threadId == second.threadId) {
    return true;
  }
  if (first.isGroup || second.isGroup) {
    return false;
  }
  final firstDid = first.targetDid?.trim();
  final secondDid = second.targetDid?.trim();
  if (firstDid != null &&
      firstDid.isNotEmpty &&
      secondDid != null &&
      secondDid.isNotEmpty &&
      firstDid == secondDid) {
    return true;
  }
  final firstPeer = _normalizedDirectPeer(first.targetPeer);
  final secondPeer = _normalizedDirectPeer(second.targetPeer);
  if (firstPeer != null && secondPeer != null) {
    return firstPeer == secondPeer;
  }
  return false;
}

String? _normalizedDirectPeer(String? value) {
  final peer = value?.trim();
  if (peer == null || peer.isEmpty) {
    return null;
  }
  return peer.startsWith('did:') ? peer : peer.toLowerCase();
}

AppThreadRef _historyThreadRefFor(ConversationSummary conversation) {
  final groupId = conversation.groupId?.trim();
  if (conversation.isGroup && groupId != null && groupId.isNotEmpty) {
    return AppThreadRef.group(groupId);
  }
  final peerDid = conversation.targetDid?.trim();
  final peer = conversation.targetPeer?.trim();
  if (!conversation.isGroup && peer != null && peer.isNotEmpty) {
    return AppThreadRef.direct(peer);
  }
  if (!conversation.isGroup && peerDid != null && peerDid.isNotEmpty) {
    return AppThreadRef.direct(peerDid);
  }
  return AppThreadRef.thread(conversation.threadId);
}

AppThreadRef _sendThreadRefFor(ConversationSummary conversation) {
  final groupId = conversation.groupId?.trim();
  if (conversation.isGroup && groupId != null && groupId.isNotEmpty) {
    return AppThreadRef.group(groupId);
  }
  final peerDid = conversation.targetDid?.trim();
  final peer = conversation.targetPeer?.trim();
  if (!conversation.isGroup && peer != null && peer.isNotEmpty) {
    return AppThreadRef.direct(peer);
  }
  if (!conversation.isGroup && peerDid != null && peerDid.isNotEmpty) {
    return AppThreadRef.direct(peerDid);
  }
  throw StateError('Cannot send without a direct peer or group id.');
}

ChatMessage _withThreadId(ChatMessage message, String threadId) {
  if (message.threadId == threadId) {
    return message;
  }
  return ChatMessage(
    localId: message.localId,
    remoteId: message.remoteId,
    threadId: threadId,
    senderDid: message.senderDid,
    senderName: message.senderName,
    receiverDid: message.receiverDid,
    groupId: message.groupId,
    content: message.content,
    originalType: message.originalType,
    createdAt: message.createdAt,
    isMine: message.isMine,
    sendState: message.sendState,
    serverSequence: message.serverSequence,
    isEncrypted: message.isEncrypted,
    attachment: message.attachment,
  );
}

String? _normalizedOptionalText(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
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
