import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/models/attachment_models.dart';
import '../../application/models/app_thread_ref.dart';
import '../../domain/entities/chat_attachment.dart';
import '../../domain/entities/chat_mention.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_identity.dart';
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

class ChatComposerDraft {
  const ChatComposerDraft({
    this.text = '',
    this.pendingAttachment,
    this.mentions = const <ChatMentionDraft>[],
  });

  final String text;
  final AttachmentDraft? pendingAttachment;
  final List<ChatMentionDraft> mentions;

  bool get isEmpty =>
      text.isEmpty && pendingAttachment == null && mentions.isEmpty;

  List<ChatMentionDraft> get validMentions => mentions
      .where(
        (mention) => mention.rangeMatches(text) && mention.target.isP9Sendable,
      )
      .toList();

  List<Map<String, Object?>> p9MentionJsonForSend() {
    return <Map<String, Object?>>[
      for (final mention in validMentions) mention.toP9Json(text),
    ];
  }

  ChatComposerDraft copyWith({
    String? text,
    Object? pendingAttachment = _chatComposerDraftUnset,
    List<ChatMentionDraft>? mentions,
  }) {
    return ChatComposerDraft(
      text: text ?? this.text,
      pendingAttachment: identical(pendingAttachment, _chatComposerDraftUnset)
          ? this.pendingAttachment
          : pendingAttachment as AttachmentDraft?,
      mentions: mentions ?? this.mentions,
    );
  }
}

const Object _chatComposerDraftUnset = Object();

class ChatComposerDraftsController
    extends StateNotifier<Map<String, ChatComposerDraft>> {
  ChatComposerDraftsController() : super(const <String, ChatComposerDraft>{});

  ChatComposerDraft draftFor(ConversationSummary conversation) {
    for (final key in _draftKeysFor(conversation)) {
      final draft = state[key];
      if (draft != null) {
        return draft;
      }
    }
    return const ChatComposerDraft();
  }

  void setText(ConversationSummary conversation, String text) {
    final current = draftFor(conversation);
    _upsertDraft(
      conversation,
      current.copyWith(
        text: text,
        mentions: ChatMentionDraft.transformMentions(
          oldText: current.text,
          newText: text,
          oldMentions: current.mentions,
        ),
      ),
    );
  }

  void setAttachment(
    ConversationSummary conversation,
    AttachmentDraft? attachment,
  ) {
    _upsertDraft(
      conversation,
      draftFor(conversation).copyWith(pendingAttachment: attachment),
    );
  }

  void setDraft(ConversationSummary conversation, ChatComposerDraft draft) {
    _upsertDraft(conversation, draft);
  }

  void clearDraft(ConversationSummary conversation) {
    final next = Map<String, ChatComposerDraft>.from(state);
    for (final key in _draftKeysFor(conversation)) {
      next.remove(key);
    }
    state = next;
  }

  void _upsertDraft(ConversationSummary conversation, ChatComposerDraft draft) {
    final keys = _draftKeysFor(conversation);
    if (keys.isEmpty) {
      return;
    }
    final canonicalKey = keys.first;
    final next = Map<String, ChatComposerDraft>.from(state);
    for (final key in keys) {
      next.remove(key);
    }
    if (!draft.isEmpty) {
      next[canonicalKey] = draft;
    }
    state = next;
  }

  List<String> _draftKeysFor(ConversationSummary conversation) {
    final keys = <String>[];
    void add(String value) {
      final key = value.trim();
      if (key.isNotEmpty && !keys.contains(key)) {
        keys.add(key);
      }
    }

    for (final key in conversation.visibilityKeys) {
      add(key);
    }
    add(conversation.threadId);
    return keys;
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

  Future<void> openConversation(
    ConversationSummary conversation, {
    String? displayThreadId,
  }) async {
    final targetThreadId = _displayThreadIdFor(conversation, displayThreadId);
    final current = thread(targetThreadId);
    if (_shouldLoadHistory(current, conversation)) {
      unawaited(_loadHistory(conversation, intoThreadId: targetThreadId));
    }
    if (conversation.unreadCount > 0) {
      ref
          .read(conversationListProvider.notifier)
          .markConversationReadLocal(conversation);
      _markConversationReadBestEffort(conversation);
    }
  }

  void _markConversationReadBestEffort(ConversationSummary conversation) {
    try {
      final operation = ref
          .read(conversationServiceProvider)
          .markThreadRead(_readThreadRefFor(conversation));
      unawaited(operation.catchError((_) {}));
    } catch (_) {
      // IM Core does not expose thread-level read-state yet, and the adapter can
      // throw UnsupportedError synchronously. Opening a conversation must still
      // clear unread locally and continue rendering messages.
    }
  }

  Future<void> _loadHistory(
    ConversationSummary conversation, {
    String? intoThreadId,
  }) async {
    if (!mounted) {
      return;
    }
    final targetThreadId = _displayThreadIdFor(conversation, intoThreadId);
    _setThreadLoading(targetThreadId, true);
    try {
      final history =
          (await ref
                  .read(messagingServiceProvider)
                  .loadHistory(_historyThreadRefFor(conversation)))
              .map((message) => _withThreadId(message, targetThreadId))
              .where((message) => message.hasRenderableContent)
              .toList();
      if (!mounted) {
        return;
      }
      _mergeMessages(
        targetThreadId,
        history,
        isLoading: false,
        resolveStaleSending: true,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _setThreadLoading(targetThreadId, false);
    }
  }

  Future<void> sendMessage({
    required ConversationSummary conversation,
    required String content,
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
    String? expectedAgentReplyDid,
  }) async {
    final session = ref.read(sessionProvider).session;
    if (session == null || content.trim().isEmpty) {
      return;
    }
    final validMentionDrafts = conversation.isGroup
        ? mentions
              .where(
                (mention) =>
                    mention.rangeMatches(content) &&
                    mention.target.isP9Sendable,
              )
              .toList()
        : const <ChatMentionDraft>[];
    final mentionPayload = validMentionDrafts.isEmpty
        ? null
        : ChatMentionPayload.toP9Json(
            text: content,
            draftMentions: validMentionDrafts,
          );
    final pending = ChatMessage(
      localId: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      threadId: conversation.threadId,
      senderDid: session.did,
      senderName: session.handle ?? session.displayName,
      receiverDid: conversation.targetDid,
      groupId: conversation.groupId,
      content: validMentionDrafts.isEmpty ? content.trim() : content,
      originalType: validMentionDrafts.isEmpty ? 'text' : 'application/json',
      createdAt: DateTime.now(),
      isMine: true,
      sendState: MessageSendState.sending,
      payloadJson: mentionPayload == null ? null : jsonEncode(mentionPayload),
      mentions: <ChatMessageMention>[
        for (final mention in validMentionDrafts)
          ChatMessageMention.fromDraft(mention),
      ],
    );
    final current = List<ChatMessage>.from(
      thread(conversation.threadId).messages,
    )..add(pending);
    _setMessages(conversation.threadId, current);
    final pendingConversation = _withConversationPreview(conversation, pending);
    ref
        .read(conversationListProvider.notifier)
        .restoreConversationBestEffort(pendingConversation);
    ref
        .read(conversationListProvider.notifier)
        .upsertConversation(pendingConversation);
    var latestConversation = pendingConversation;
    try {
      final messaging = ref.read(messagingServiceProvider);
      final sent = validMentionDrafts.isEmpty
          ? await messaging
                .sendText(
                  thread: _sendThreadRefFor(conversation),
                  content: content.trim(),
                )
                .timeout(_sendTimeout)
          : await messaging
                .sendMentionText(
                  thread: _sendThreadRefFor(conversation),
                  text: content,
                  mentions: validMentionDrafts,
                  idempotencyKey: pending.localId,
                )
                .timeout(_sendTimeout);
      final sentInThread = _withThreadId(sent, conversation.threadId);
      _replaceMessage(conversation.threadId, pending.localId, sentInThread);
      _startAgentProcessingForDeliveredMessage(
        conversation: conversation,
        expectedAgentReplyDid: expectedAgentReplyDid,
        deliveredMessage: sentInThread,
      );
      latestConversation = _withConversationPreview(conversation, sentInThread);
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(latestConversation);
    } catch (_) {
      final failed = pending.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(conversation.threadId, pending.localId, failed);
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
    unawaited(
      _loadHistory(refreshedConversation, intoThreadId: conversation.threadId),
    );
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
        .restoreConversationBestEffort(pendingConversation);
    ref
        .read(conversationListProvider.notifier)
        .upsertConversation(pendingConversation);
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
      final sentInThread = await _withCachedSentAttachment(
        sent: _withThreadId(sent, conversation.threadId),
        originalAttachment: attachment,
      );
      _replaceMessage(conversation.threadId, pending.localId, sentInThread);
      _startAgentProcessingForDeliveredMessage(
        conversation: conversation,
        expectedAgentReplyDid: expectedAgentReplyDid,
        deliveredMessage: sentInThread,
      );
      latestConversation = _withConversationPreview(conversation, sentInThread);
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(latestConversation);
    } catch (_) {
      final failed = pending.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(conversation.threadId, pending.localId, failed);
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
    unawaited(
      _loadHistory(refreshedConversation, intoThreadId: conversation.threadId),
    );
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
    String? expectedAgentReplyDid,
  }) async {
    if (message.isAttachmentMessage) {
      await retryAttachment(
        conversation: conversation,
        message: message,
        expectedAgentReplyDid: expectedAgentReplyDid,
      );
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
      final retriedInThread = _withThreadId(retried, conversation.threadId);
      _replaceMessage(conversation.threadId, message.localId, retriedInThread);
      _startAgentProcessingForDeliveredMessage(
        conversation: conversation,
        expectedAgentReplyDid: expectedAgentReplyDid,
        deliveredMessage: retriedInThread,
      );
    } catch (_) {
      final failed = retrying.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(conversation.threadId, message.localId, failed);
    }
    await _refreshConversationsBestEffort();
    unawaited(
      _loadHistory(
        _refreshedConversationFor(conversation),
        intoThreadId: conversation.threadId,
      ),
    );
  }

  Future<void> retryAttachment({
    required ConversationSummary conversation,
    required ChatMessage message,
    String? expectedAgentReplyDid,
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
      final retriedInThread = await _withCachedSentAttachment(
        sent: _withThreadId(retried, conversation.threadId),
        originalAttachment: AttachmentDraft(
          filename: attachment.filename,
          mimeType: attachment.mimeType,
          localPath: localPath,
          sizeBytes: attachment.sizeBytes,
        ),
      );
      _replaceMessage(conversation.threadId, message.localId, retriedInThread);
      _startAgentProcessingForDeliveredMessage(
        conversation: conversation,
        expectedAgentReplyDid: expectedAgentReplyDid,
        deliveredMessage: retriedInThread,
      );
    } catch (_) {
      final failed = retrying.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(conversation.threadId, message.localId, failed);
    }
    await _refreshConversationsBestEffort();
    unawaited(
      _loadHistory(
        _refreshedConversationFor(conversation),
        intoThreadId: conversation.threadId,
      ),
    );
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

  void applyRealtimeUpdate(
    ChatMessage message, {
    ConversationSummary? conversation,
  }) {
    final targetThreadId = conversation == null
        ? message.threadId
        : _threadIdForRealtimeMessage(message, conversation);
    _mergeMessages(targetThreadId, <ChatMessage>[
      _withThreadId(message, targetThreadId),
    ], trustIncomingAgentReply: true);
  }

  Future<void> refreshConversation(
    ConversationSummary conversation, {
    String? displayThreadId,
  }) async {
    await ref.read(conversationListProvider.notifier).refresh();
    await _loadHistory(
      _refreshedConversationFor(conversation),
      intoThreadId: displayThreadId ?? conversation.threadId,
    );
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
    ChatMessage? existing;
    final index = current.indexWhere((item) => item.localId == localId);
    if (index >= 0) {
      existing = current.removeAt(index);
    } else if (replacement.sendState != MessageSendState.sent) {
      return;
    }
    final replacementIndex = _matchingMessageIndex(current, replacement);
    if (replacementIndex >= 0) {
      final merged = _withPreservedAttachmentState(
        replacement,
        current[replacementIndex],
      );
      current[replacementIndex] = existing == null
          ? merged
          : _withPreservedAttachmentState(
              merged,
              existing,
              trustMessageMatch: true,
            );
    } else {
      current.add(
        existing == null
            ? replacement
            : _withPreservedAttachmentState(
                replacement,
                existing,
                trustMessageMatch: true,
              ),
      );
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
        current[index] = _withPreservedAttachmentState(message, current[index]);
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

  Future<ChatMessage> _withCachedSentAttachment({
    required ChatMessage sent,
    required AttachmentDraft originalAttachment,
  }) async {
    final attachment = sent.attachment;
    if (attachment == null) {
      return sent;
    }
    final messageId = _stableMessageId(sent);
    if (messageId.isEmpty || attachment.attachmentId.trim().isEmpty) {
      return sent;
    }
    String? cachedPath;
    final sourcePath = originalAttachment.localPath?.trim();
    try {
      if (sourcePath != null && sourcePath.isNotEmpty) {
        cachedPath = await ref
            .read(attachmentCacheServiceProvider)
            .cacheLocalSource(
              messageId: messageId,
              attachmentId: attachment.attachmentId,
              filename: attachment.filename,
              mimeType: attachment.mimeType,
              sourcePath: sourcePath,
            );
      } else {
        final bytes = originalAttachment.bytes;
        if (bytes != null) {
          cachedPath = await ref
              .read(attachmentCacheServiceProvider)
              .cacheDownloadedBytes(
                messageId: messageId,
                attachmentId: attachment.attachmentId,
                filename: attachment.filename,
                mimeType: attachment.mimeType,
                bytes: bytes,
              );
        }
      }
    } catch (_) {
      cachedPath = null;
    }
    final resolvedPath = _normalizedOptionalText(cachedPath);
    if (resolvedPath == null) {
      return sent;
    }
    return sent.copyWith(
      attachment: attachment.copyWith(
        localPath: resolvedPath,
        hasLocalSource: true,
      ),
    );
  }

  ChatMessage _withPreservedAttachmentState(
    ChatMessage incoming,
    ChatMessage existing, {
    bool trustMessageMatch = false,
  }) {
    final incomingAttachment = incoming.attachment;
    final existingAttachment = existing.attachment;
    if (incomingAttachment == null || existingAttachment == null) {
      return incoming;
    }
    if (!trustMessageMatch && !_isSameAttachment(incoming, existing)) {
      return incoming;
    }
    final existingPath = existingAttachment.localPath?.trim();
    if (existingPath == null || existingPath.isEmpty) {
      return incoming;
    }
    final incomingPath = incomingAttachment.localPath?.trim();
    if (incomingPath != null && incomingPath.isNotEmpty) {
      return incoming;
    }
    return incoming.copyWith(
      attachment: incomingAttachment.copyWith(
        localPath: existingPath,
        hasLocalSource:
            incomingAttachment.hasLocalSource ||
            existingAttachment.hasLocalSource,
      ),
    );
  }

  bool _isSameAttachment(ChatMessage first, ChatMessage second) {
    final firstAttachment = first.attachment;
    final secondAttachment = second.attachment;
    if (firstAttachment == null || secondAttachment == null) {
      return false;
    }
    if (_stableMessageId(first) == _stableMessageId(second)) {
      return firstAttachment.attachmentId == secondAttachment.attachmentId;
    }
    return firstAttachment.attachmentId == secondAttachment.attachmentId &&
        firstAttachment.filename == secondAttachment.filename &&
        firstAttachment.mimeType == secondAttachment.mimeType;
  }

  String _stableMessageId(ChatMessage message) {
    final remoteId = message.remoteId?.trim();
    if (remoteId != null && remoteId.isNotEmpty) {
      return remoteId;
    }
    return message.localId.trim();
  }

  void _startAgentProcessingForDeliveredMessage({
    required ConversationSummary conversation,
    required String? expectedAgentReplyDid,
    required ChatMessage deliveredMessage,
  }) {
    final agentDid = expectedAgentReplyDid?.trim();
    final remoteMessageId = deliveredMessage.remoteId?.trim().isNotEmpty == true
        ? deliveredMessage.remoteId!.trim()
        : deliveredMessage.localId.trim();
    if (conversation.isGroup ||
        agentDid == null ||
        agentDid.isEmpty ||
        !deliveredMessage.isMine ||
        deliveredMessage.sendState != MessageSendState.sent ||
        deliveredMessage.localId.trim().isEmpty) {
      return;
    }
    final threadId = conversation.threadId;
    final current = thread(threadId);
    final nextTurns = <AgentPendingTurn>[
      ...current.agentPendingTurns.where(
        (turn) =>
            turn.localMessageId != deliveredMessage.localId &&
            turn.remoteMessageId != remoteMessageId,
      ),
      AgentPendingTurn(
        agentDid: agentDid,
        localMessageId: deliveredMessage.localId,
        remoteMessageId: remoteMessageId,
        startedAt: deliveredMessage.createdAt,
      ),
    ];
    state = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(agentPendingTurns: nextTurns),
    };
    _scheduleAgentProcessingOverdue(threadId);
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

  String _displayThreadIdFor(ConversationSummary conversation, String? value) {
    final displayThreadId = value?.trim();
    if (displayThreadId == null || displayThreadId.isEmpty) {
      return conversation.threadId;
    }
    return displayThreadId;
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
        .where((item) => sameConversationTarget(item, fallback));
    return refreshed.isEmpty ? fallback : refreshed.first;
  }

  String _threadIdForRealtimeMessage(
    ChatMessage message,
    ConversationSummary conversation,
  ) {
    for (final entry in state.entries) {
      if (sameConversationTarget(
        _conversationIdentityForThread(entry.key, entry.value),
        conversation,
      )) {
        return entry.key;
      }
    }
    return conversation.threadId.trim().isEmpty
        ? message.threadId
        : conversation.threadId;
  }

  ConversationSummary _conversationIdentityForThread(
    String threadId,
    ChatThreadState thread,
  ) {
    final latestMessage = thread.messages.isEmpty ? null : thread.messages.last;
    final groupId = latestMessage?.groupId?.trim();
    if (groupId != null && groupId.isNotEmpty) {
      return ConversationSummary(
        threadId: threadId,
        displayName: groupId,
        lastMessagePreview: latestMessage?.previewText ?? '',
        lastMessageAt: latestMessage?.createdAt ?? DateTime(1970),
        unreadCount: 0,
        isGroup: true,
        groupId: groupId,
      );
    }
    final targetDid = directPeerDidFromMessages(thread.messages);
    return ConversationSummary(
      threadId: threadId,
      displayName: targetDid ?? threadId,
      lastMessagePreview: latestMessage?.previewText ?? '',
      lastMessageAt: latestMessage?.createdAt ?? DateTime(1970),
      unreadCount: 0,
      isGroup: false,
      targetDid: targetDid,
      targetPeer: targetDid,
    );
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
    lastMessagePayloadJson:
        message.payloadJson ?? conversation.lastMessagePayloadJson,
  );
}

ConversationSummary _newerConversation(
  ConversationSummary first,
  ConversationSummary second,
) {
  return first.lastMessageAt.isBefore(second.lastMessageAt) ? second : first;
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

AppThreadRef _readThreadRefFor(ConversationSummary conversation) {
  final groupId = conversation.groupId?.trim();
  if (conversation.isGroup && groupId != null && groupId.isNotEmpty) {
    return AppThreadRef.group(groupId);
  }
  final peer = conversation.targetPeer?.trim();
  if (!conversation.isGroup && peer != null && peer.isNotEmpty) {
    return AppThreadRef.direct(peer);
  }
  final peerDid = conversation.targetDid?.trim();
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
    payloadJson: message.payloadJson,
    mentions: message.mentions,
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

final chatComposerDraftsProvider =
    StateNotifierProvider<
      ChatComposerDraftsController,
      Map<String, ChatComposerDraft>
    >((ref) => ChatComposerDraftsController());

final chatThreadProvider = Provider.family<ChatThreadState, String>((
  ref,
  threadId,
) {
  final threads = ref.watch(chatThreadsProvider);
  return threads[threadId] ?? ChatThreadState(threadId: threadId);
});
