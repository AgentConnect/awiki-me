import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/message_sync_service.dart';
import '../../application/models/attachment_models.dart';
import '../../application/models/app_thread_ref.dart';
import '../../application/messaging_service.dart';
import '../../core/performance_logger.dart';
import '../../domain/entities/agent/agent_control_payloads.dart';
import '../../domain/entities/agent/agent_status.dart';
import '../../domain/entities/chat_attachment.dart';
import '../../domain/entities/chat_mention.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_identity.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../l10n/app_message.dart';
import '../../app/ui_feedback.dart';
import '../agents/agents_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../conversation_list/conversation_provider.dart';

class ChatThreadState {
  const ChatThreadState({
    required this.threadId,
    this.messages = const <ChatMessage>[],
    this.isLoading = false,
    this.agentPendingTurns = const <AgentPendingTurn>[],
    this.messageAgentSyncs = const <MessageAgentSyncRecord>[],
    this.appActionRecords = const <String, AppActionRecord>{},
  });

  final String threadId;
  final List<ChatMessage> messages;
  final bool isLoading;
  final List<AgentPendingTurn> agentPendingTurns;
  final List<MessageAgentSyncRecord> messageAgentSyncs;
  final Map<String, AppActionRecord> appActionRecords;

  bool get isAgentProcessing => agentPendingTurns.any((turn) => turn.isActive);

  bool get isAgentProcessingOverdue =>
      agentPendingTurns.any((turn) => turn.isActive && turn.isOverdue);

  int get pendingAgentReplyCount =>
      agentPendingTurns.where((turn) => turn.isActive).length;

  List<AgentPendingTurn> pendingAgentTurnsForMessage(ChatMessage message) {
    return <AgentPendingTurn>[
      for (final turn in agentPendingTurns)
        if (turn.isActive && turn.matchesMessage(message)) turn,
    ];
  }

  AgentPendingTurn? pendingAgentTurnForMessage(ChatMessage message) {
    final turns = pendingAgentTurnsForMessage(message);
    return turns.isEmpty ? null : turns.first;
  }

  int get messageAgentTimelineCount =>
      messageAgentSyncs.length + appActionRecords.length;

  ChatThreadState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    List<AgentPendingTurn>? agentPendingTurns,
    List<MessageAgentSyncRecord>? messageAgentSyncs,
    Map<String, AppActionRecord>? appActionRecords,
  }) {
    return ChatThreadState(
      threadId: threadId,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      agentPendingTurns: agentPendingTurns ?? this.agentPendingTurns,
      messageAgentSyncs: messageAgentSyncs ?? this.messageAgentSyncs,
      appActionRecords: appActionRecords ?? this.appActionRecords,
    );
  }
}

class MessageAgentSyncRecord {
  const MessageAgentSyncRecord({
    required this.identityKey,
    required this.type,
    this.messageId,
    this.conversationId,
    this.runtimeAgentDid,
    this.runtimeProfileId,
    this.runId,
    this.state,
    this.processingStatus,
    this.unsupportedReason,
    this.lastErrorCode,
    this.lastErrorSummary,
    this.retentionClass,
    this.hasText = false,
    this.summaryText,
    this.draftText,
  });

  final String identityKey;
  final String type;
  final String? messageId;
  final String? conversationId;
  final String? runtimeAgentDid;
  final String? runtimeProfileId;
  final String? runId;
  final String? state;
  final String? processingStatus;
  final String? unsupportedReason;
  final String? lastErrorCode;
  final String? lastErrorSummary;
  final String? retentionClass;
  final bool hasText;
  final String? summaryText;
  final String? draftText;

  bool get isRuntimeStatus => type == 'runtime_status';

  bool get isRuntimeFinal => type == 'runtime_final';

  bool get isUnsupported =>
      type == 'unsupported' || processingStatus == 'skipped_unsupported';

  bool get isFailed =>
      state == 'failed' || lastErrorCode != null || lastErrorSummary != null;

  bool get isTerminal =>
      isRuntimeFinal || isUnsupported || isFailed || state == 'finished';

  static MessageAgentSyncRecord fromPayload(MessageSyncPayload payload) {
    final type = payload.effectiveType;
    final messageId = payload.primaryMessageId;
    final conversationId = payload.primaryConversationId;
    final runId = payload.runId;
    return MessageAgentSyncRecord(
      identityKey: _messageAgentSyncIdentityKey(
        type: type,
        runId: runId,
        messageId: messageId,
        conversationId: conversationId,
      ),
      type: type,
      messageId: messageId,
      conversationId: conversationId,
      runtimeAgentDid: payload.runtimeAgentDid,
      runtimeProfileId: payload.runtimeProfileId,
      runId: runId,
      state: payload.state,
      processingStatus: payload.processingStatus,
      unsupportedReason: payload.unsupportedReason,
      lastErrorCode: payload.lastErrorCode,
      lastErrorSummary: payload.lastErrorSummary,
      retentionClass: payload.retentionClass,
      hasText: payload.hasText,
      summaryText: payload.summaryText,
      draftText: payload.draftText,
    );
  }
}

String _messageAgentSyncIdentityKey({
  required String type,
  required String? runId,
  required String? messageId,
  required String? conversationId,
}) {
  final run = runId?.trim();
  if (run != null && run.isNotEmpty) {
    return 'run:$run:$type';
  }
  final message = messageId?.trim();
  if (message != null && message.isNotEmpty) {
    return 'message:$message:$type';
  }
  final conversation = conversationId?.trim();
  if (conversation != null && conversation.isNotEmpty) {
    return 'conversation:$conversation:$type';
  }
  return 'message-agent:$type';
}

class AgentPendingTurn {
  const AgentPendingTurn({
    required this.agentDid,
    required this.localMessageId,
    required this.startedAt,
    this.remoteMessageId,
    this.mentionId,
    this.agentHandle,
    this.isOverdue = false,
  });

  final String agentDid;
  final String localMessageId;
  final String? remoteMessageId;
  final String? mentionId;
  final String? agentHandle;
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
      mentionId: mentionId,
      agentHandle: agentHandle,
      startedAt: startedAt,
      isOverdue: true,
    );
  }
}

class _AgentPendingTarget {
  const _AgentPendingTarget({
    required this.agentDid,
    required this.agentHandle,
    required this.mentionId,
  });

  final String agentDid;
  final String? agentHandle;
  final String? mentionId;
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

class _PendingHistorySync {
  const _PendingHistorySync({
    required this.conversation,
    required this.force,
    required this.reportFailure,
    required this.showLoading,
  });

  final ConversationSummary conversation;
  final bool force;
  final bool reportFailure;
  final bool showLoading;
}

class _HistoryLoadResult {
  const _HistoryLoadResult({required this.loadedCount, required this.failed});

  final int loadedCount;
  final bool failed;

  bool get loadedAny => loadedCount > 0;
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
  final Map<String, _PendingHistorySync> _pendingHistorySyncs =
      <String, _PendingHistorySync>{};
  final Set<String> _activeLocalHistoryLoads = <String>{};
  final Set<String> _activeRemoteHistorySyncs = <String>{};
  final Map<String, Timer> _conversationRefreshDebounceTimers =
      <String, Timer>{};
  final Map<String, ConversationSummary> _pendingConversationRefreshFallbacks =
      <String, ConversationSummary>{};

  static const Duration postSendReconcileDebounce = Duration(seconds: 1);

  ChatThreadState thread(String threadId) {
    return state[threadId] ?? ChatThreadState(threadId: threadId);
  }

  Future<void> openConversation(
    ConversationSummary conversation, {
    String? displayThreadId,
  }) async {
    final targetThreadId = _displayThreadIdFor(conversation, displayThreadId);
    AwikiPerformanceLogger.log(
      'chat.open_conversation',
      fields: <String, Object?>{
        ...AwikiPerformanceLogger.threadField(targetThreadId),
        'unread': conversation.unreadCount,
        'is_group': conversation.isGroup,
      },
      level: AwikiPerformanceLogLevel.verbose,
    );
    unawaited(
      _openConversationLocalFirst(
        conversation,
        displayThreadId: targetThreadId,
      ),
    );
    if (conversation.unreadCount > 0) {
      final localClearWatch = Stopwatch()..start();
      ref
          .read(conversationListProvider.notifier)
          .markConversationReadLocal(conversation);
      localClearWatch.stop();
      AwikiPerformanceLogger.log(
        'chat.mark_read.local_clear',
        elapsed: localClearWatch.elapsed,
        fields: AwikiPerformanceLogger.threadField(conversation.threadId),
        level: AwikiPerformanceLogLevel.verbose,
      );
      _markConversationReadBestEffort(conversation);
    }
  }

  Future<void> _openConversationLocalFirst(
    ConversationSummary conversation, {
    required String displayThreadId,
  }) async {
    final currentBeforeLocal = thread(displayThreadId);
    if (currentBeforeLocal.isLoading ||
        _activeLocalHistoryLoads.contains(displayThreadId) ||
        _activeRemoteHistorySyncs.contains(displayThreadId)) {
      return;
    }
    if (!_shouldLoadHistory(currentBeforeLocal, conversation)) {
      return;
    }
    final localResult = await _loadLocalHistory(
      conversation,
      intoThreadId: displayThreadId,
    );
    if (!mounted) {
      return;
    }
    unawaited(
      _syncThreadAfterLocalMax(conversation, displayThreadId: displayThreadId),
    );
    final shouldReconcileRemote =
        currentBeforeLocal.messages.isEmpty ||
        localResult.failed ||
        _shouldLoadHistory(thread(displayThreadId), conversation);
    if (!shouldReconcileRemote) {
      return;
    }
    if (_activeRemoteHistorySyncs.contains(displayThreadId)) {
      return;
    }
    final hadLocalMessagesBefore = currentBeforeLocal.messages.isNotEmpty;
    final shouldShowRemoteFailure =
        localResult.failed ||
        (!localResult.loadedAny && !hadLocalMessagesBefore);
    unawaited(
      syncHistoryForConversation(
        conversation,
        displayThreadId: displayThreadId,
        force: currentBeforeLocal.messages.isEmpty || localResult.failed,
        reportFailure: shouldShowRemoteFailure,
        showLoading: !localResult.loadedAny && !hadLocalMessagesBefore,
      ),
    );
  }

  Future<void> _syncThreadAfterLocalMax(
    ConversationSummary conversation, {
    required String displayThreadId,
  }) async {
    if (!mounted) {
      return;
    }
    final afterServerSeq = maxServerSequenceForMessages(
      thread(displayThreadId).messages,
    );
    try {
      final result = await ref
          .read(messageSyncServiceProvider)
          .syncThreadAfter(
            thread: _localHistoryThreadRefFor(conversation),
            afterServerSeq: afterServerSeq,
          );
      final messages = result.messages
          .map((message) => _withThreadId(message, displayThreadId))
          .where((message) => message.hasRenderableContent)
          .toList();
      if (!mounted || messages.isEmpty) {
        return;
      }
      _mergeMessages(displayThreadId, messages, isLoading: false);
      await ref.read(conversationListProvider.notifier).refreshFastLocal();
    } catch (_) {
      AwikiPerformanceLogger.log(
        'chat.thread_after.failed',
        fields: AwikiPerformanceLogger.threadField(displayThreadId),
      );
    }
  }

  void _markConversationReadBestEffort(ConversationSummary conversation) {
    try {
      final thread = _readThreadRefFor(conversation);
      final watch = Stopwatch()..start();
      final operation = ref
          .read(conversationServiceProvider)
          .markThreadRead(thread)
          .whenComplete(() {
            watch.stop();
            AwikiPerformanceLogger.log(
              'chat.mark_read',
              elapsed: watch.elapsed,
              fields: AwikiPerformanceLogger.threadField(conversation.threadId),
            );
          });
      unawaited(operation.catchError((_) {}));
    } catch (_) {
      // Thread-level mark-read is best effort. Opening a conversation must
      // still clear unread locally and continue rendering messages.
    }
  }

  Future<_HistoryLoadResult> _loadLocalHistory(
    ConversationSummary conversation, {
    String? intoThreadId,
  }) async {
    if (!mounted) {
      return const _HistoryLoadResult(loadedCount: 0, failed: false);
    }
    final targetThreadId = _displayThreadIdFor(conversation, intoThreadId);
    final totalWatch = Stopwatch()..start();
    _activeLocalHistoryLoads.add(targetThreadId);
    final shouldShowLoading = thread(targetThreadId).messages.isEmpty;
    if (shouldShowLoading) {
      _setThreadLoading(targetThreadId, true);
    }
    final messaging = ref.read(messagingServiceProvider);
    try {
      if (messaging is! LocalHistoryMessagingService) {
        if (shouldShowLoading && mounted) {
          _setThreadLoading(targetThreadId, false);
        }
        AwikiPerformanceLogger.log(
          'chat.local_history.unsupported',
          fields: AwikiPerformanceLogger.threadField(targetThreadId),
        );
        return const _HistoryLoadResult(loadedCount: 0, failed: true);
      }
      final localMessaging = messaging as LocalHistoryMessagingService;
      final loadedHistory = await AwikiPerformanceLogger.async(
        'chat.local_history.service',
        () => localMessaging.loadLocalHistory(
          _localHistoryThreadRefFor(conversation),
        ),
        fields: AwikiPerformanceLogger.threadField(targetThreadId),
        level: AwikiPerformanceLogLevel.verbose,
      );
      final history = AwikiPerformanceLogger.sync(
        'chat.local_history.prepare',
        () => loadedHistory
            .map((message) => _withThreadId(message, targetThreadId))
            .where((message) => message.hasRenderableContent)
            .toList(),
        fields: <String, Object?>{
          ...AwikiPerformanceLogger.threadField(targetThreadId),
          'items': loadedHistory.length,
        },
        level: AwikiPerformanceLogLevel.verbose,
      );
      if (!mounted) {
        return _HistoryLoadResult(loadedCount: history.length, failed: false);
      }
      _mergeMessages(targetThreadId, history, isLoading: false);
      totalWatch.stop();
      AwikiPerformanceLogger.log(
        'chat.local_history.load',
        elapsed: totalWatch.elapsed,
        fields: <String, Object?>{
          ...AwikiPerformanceLogger.threadField(targetThreadId),
          'items': history.length,
        },
      );
      return _HistoryLoadResult(loadedCount: history.length, failed: false);
    } catch (_) {
      if (shouldShowLoading && mounted) {
        _setThreadLoading(targetThreadId, false);
      }
      totalWatch.stop();
      AwikiPerformanceLogger.log(
        'chat.local_history.failed',
        elapsed: totalWatch.elapsed,
        fields: AwikiPerformanceLogger.threadField(targetThreadId),
      );
      return const _HistoryLoadResult(loadedCount: 0, failed: true);
    } finally {
      _activeLocalHistoryLoads.remove(targetThreadId);
      if (mounted) {
        _runPendingHistorySyncIfNeeded(targetThreadId);
      }
    }
  }

  Future<void> _loadHistory(
    ConversationSummary conversation, {
    String? intoThreadId,
    bool reportFailure = false,
    bool showLoading = true,
  }) async {
    if (!mounted) {
      return;
    }
    final targetThreadId = _displayThreadIdFor(conversation, intoThreadId);
    final totalWatch = Stopwatch()..start();
    _activeRemoteHistorySyncs.add(targetThreadId);
    if (showLoading) {
      _setThreadLoading(targetThreadId, true);
    }
    try {
      final loadedHistory = await AwikiPerformanceLogger.async(
        'chat.remote_history.service',
        () => ref
            .read(messagingServiceProvider)
            .loadHistory(_historyThreadRefFor(conversation)),
        fields: AwikiPerformanceLogger.threadField(targetThreadId),
        level: AwikiPerformanceLogLevel.verbose,
      );
      final history = AwikiPerformanceLogger.sync(
        'chat.remote_history.prepare',
        () => loadedHistory
            .map((message) => _withThreadId(message, targetThreadId))
            .where((message) => message.hasRenderableContent)
            .toList(),
        fields: <String, Object?>{
          ...AwikiPerformanceLogger.threadField(targetThreadId),
          'items': loadedHistory.length,
        },
        level: AwikiPerformanceLogLevel.verbose,
      );
      AwikiPerformanceLogger.log(
        'chat.history.service',
        fields: <String, Object?>{
          ...AwikiPerformanceLogger.threadField(targetThreadId),
          'compat': true,
          'items': loadedHistory.length,
        },
        level: AwikiPerformanceLogLevel.verbose,
      );
      if (!mounted) {
        return;
      }
      _mergeMessages(
        targetThreadId,
        history,
        isLoading: false,
        resolveStaleSending: true,
      );
      totalWatch.stop();
      AwikiPerformanceLogger.log(
        'chat.remote_history.load',
        elapsed: totalWatch.elapsed,
        fields: <String, Object?>{
          ...AwikiPerformanceLogger.threadField(targetThreadId),
          'items': history.length,
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (showLoading) {
        _setThreadLoading(targetThreadId, false);
      }
      if (reportFailure) {
        ref
            .read(uiFeedbackProvider.notifier)
            .showError(AppMessage.fromError(error));
      }
    } finally {
      _activeRemoteHistorySyncs.remove(targetThreadId);
      if (mounted) {
        _runPendingHistorySyncIfNeeded(targetThreadId);
      }
    }
  }

  Future<void> sendMessage({
    required ConversationSummary conversation,
    required String content,
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
    String? expectedAgentReplyDid,
    String? displayThreadId,
  }) async {
    final session = ref.read(sessionProvider).session;
    if (session == null || content.trim().isEmpty) {
      return;
    }
    final targetThreadId = _displayThreadIdFor(conversation, displayThreadId);
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
      threadId: targetThreadId,
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
    final current = List<ChatMessage>.from(thread(targetThreadId).messages)
      ..add(pending);
    _setMessages(targetThreadId, current);
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
      final sentInThread = _withThreadId(sent, targetThreadId);
      _replaceMessage(targetThreadId, pending.localId, sentInThread);
      _startAgentProcessingForDeliveredMessage(
        conversation: conversation,
        displayThreadId: targetThreadId,
        expectedAgentReplyDid: expectedAgentReplyDid,
        mentions: validMentionDrafts,
        submittedLocalMessageId: pending.localId,
        deliveredMessage: sentInThread,
      );
      latestConversation = _withConversationPreview(conversation, sentInThread);
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(latestConversation);
    } catch (_) {
      final failed = pending.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(targetThreadId, pending.localId, failed);
      latestConversation = _withConversationPreview(conversation, failed);
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(latestConversation);
    }
    _scheduleConversationRefreshBestEffort(
      latestConversation,
      displayThreadId: targetThreadId,
    );
  }

  Future<void> sendAttachment({
    required ConversationSummary conversation,
    required AttachmentDraft attachment,
    String? caption,
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
    String? expectedAgentReplyDid,
    String? displayThreadId,
  }) async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      return;
    }
    final targetThreadId = _displayThreadIdFor(conversation, displayThreadId);
    final normalizedCaption = _normalizedOptionalText(caption);
    final captionText = normalizedCaption ?? '';
    final validMentionDrafts = conversation.isGroup
        ? mentions
              .where(
                (mention) =>
                    mention.rangeMatches(captionText) &&
                    mention.target.isP9Sendable,
              )
              .toList()
        : const <ChatMentionDraft>[];
    final mentionPayload = validMentionDrafts.isEmpty
        ? null
        : ChatMentionPayload.toP9Json(
            text: captionText,
            draftMentions: validMentionDrafts,
          );
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
      threadId: targetThreadId,
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
      payloadJson: mentionPayload == null ? null : jsonEncode(mentionPayload),
      mentions: <ChatMessageMention>[
        for (final mention in validMentionDrafts)
          ChatMessageMention.fromDraft(mention),
      ],
    );
    final current = List<ChatMessage>.from(thread(targetThreadId).messages)
      ..add(pending);
    _setMessages(targetThreadId, current);
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
            mentions: validMentionDrafts,
            idempotencyKey: pending.localId,
          )
          .timeout(_attachmentSendTimeout);
      final sentInThread = await _withCachedSentAttachment(
        sent: _withThreadId(sent, targetThreadId),
        originalAttachment: attachment,
      );
      _replaceMessage(targetThreadId, pending.localId, sentInThread);
      _startAgentProcessingForDeliveredMessage(
        conversation: conversation,
        displayThreadId: targetThreadId,
        expectedAgentReplyDid: expectedAgentReplyDid,
        mentions: validMentionDrafts,
        submittedLocalMessageId: pending.localId,
        deliveredMessage: sentInThread,
      );
      latestConversation = _withConversationPreview(conversation, sentInThread);
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(latestConversation);
    } catch (_) {
      final failed = pending.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(targetThreadId, pending.localId, failed);
      latestConversation = _withConversationPreview(conversation, failed);
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(latestConversation);
    }
    _scheduleConversationRefreshBestEffort(
      latestConversation,
      displayThreadId: targetThreadId,
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
    String? displayThreadId,
  }) async {
    if (message.isAttachmentMessage) {
      await retryAttachment(
        conversation: conversation,
        message: message,
        expectedAgentReplyDid: expectedAgentReplyDid,
        displayThreadId: displayThreadId,
      );
      return;
    }
    final targetThreadId = _displayThreadIdFor(conversation, displayThreadId);
    final retrying = message.copyWith(sendState: MessageSendState.sending);
    _setMessages(
      targetThreadId,
      thread(targetThreadId).messages
          .map((item) => item.localId == message.localId ? retrying : item)
          .toList(),
    );
    try {
      final retried = await ref
          .read(messagingServiceProvider)
          .retryByResendOriginalContent(retrying)
          .timeout(_sendTimeout);
      final retriedInThread = _withThreadId(retried, targetThreadId);
      _replaceMessage(targetThreadId, message.localId, retriedInThread);
      _startAgentProcessingForDeliveredMessage(
        conversation: conversation,
        displayThreadId: targetThreadId,
        expectedAgentReplyDid: expectedAgentReplyDid,
        mentions: _messageMentionsToDrafts(retrying.mentions),
        submittedLocalMessageId: retrying.localId,
        deliveredMessage: retriedInThread,
      );
    } catch (_) {
      final failed = retrying.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(targetThreadId, message.localId, failed);
    }
    _scheduleConversationRefreshBestEffort(
      conversation,
      displayThreadId: targetThreadId,
    );
  }

  Future<void> retryAttachment({
    required ConversationSummary conversation,
    required ChatMessage message,
    String? expectedAgentReplyDid,
    String? displayThreadId,
  }) async {
    final targetThreadId = _displayThreadIdFor(conversation, displayThreadId);
    final attachment = message.attachment;
    final localPath = attachment?.localPath?.trim();
    if (attachment == null || localPath == null || localPath.isEmpty) {
      final failed = message.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(targetThreadId, message.localId, failed);
      return;
    }
    final retrying = message.copyWith(sendState: MessageSendState.sending);
    _setMessages(
      targetThreadId,
      thread(targetThreadId).messages
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
            mentions: _messageMentionsToDrafts(retrying.mentions),
            idempotencyKey: message.localId,
          )
          .timeout(_attachmentSendTimeout);
      final retriedInThread = await _withCachedSentAttachment(
        sent: _withThreadId(retried, targetThreadId),
        originalAttachment: AttachmentDraft(
          filename: attachment.filename,
          mimeType: attachment.mimeType,
          localPath: localPath,
          sizeBytes: attachment.sizeBytes,
        ),
      );
      _replaceMessage(targetThreadId, message.localId, retriedInThread);
      _startAgentProcessingForDeliveredMessage(
        conversation: conversation,
        displayThreadId: targetThreadId,
        expectedAgentReplyDid: expectedAgentReplyDid,
        mentions: _messageMentionsToDrafts(retrying.mentions),
        submittedLocalMessageId: retrying.localId,
        deliveredMessage: retriedInThread,
      );
    } catch (_) {
      final failed = retrying.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(targetThreadId, message.localId, failed);
    }
    _scheduleConversationRefreshBestEffort(
      conversation,
      displayThreadId: targetThreadId,
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
    await syncHistoryForConversation(
      _refreshedConversationFor(conversation),
      displayThreadId: displayThreadId ?? conversation.threadId,
      force: true,
      reportFailure: true,
    );
  }

  Future<void> syncHistoryForConversation(
    ConversationSummary conversation, {
    String? displayThreadId,
    bool force = false,
    bool reportFailure = false,
    bool showLoading = true,
  }) {
    final targetThreadId = _displayThreadIdFor(conversation, displayThreadId);
    final current = thread(targetThreadId);
    if (current.isLoading ||
        _activeRemoteHistorySyncs.contains(targetThreadId)) {
      if (force || _shouldLoadHistory(current, conversation)) {
        _queuePendingHistorySync(
          targetThreadId,
          conversation,
          force: force,
          reportFailure: reportFailure,
          showLoading: showLoading,
        );
      }
      return Future<void>.value();
    }
    if (!force && !_shouldLoadHistory(current, conversation)) {
      return Future<void>.value();
    }
    return _loadHistory(
      conversation,
      intoThreadId: targetThreadId,
      reportFailure: reportFailure,
      showLoading: showLoading,
    );
  }

  void _scheduleConversationRefreshBestEffort(
    ConversationSummary fallback, {
    required String displayThreadId,
  }) {
    final pendingFallback =
        _pendingConversationRefreshFallbacks[displayThreadId];
    _pendingConversationRefreshFallbacks[displayThreadId] =
        pendingFallback == null
        ? fallback
        : _newerConversation(pendingFallback, fallback);
    _conversationRefreshDebounceTimers[displayThreadId]?.cancel();
    _conversationRefreshDebounceTimers[displayThreadId] = Timer(
      postSendReconcileDebounce,
      () {
        if (!mounted) {
          return;
        }
        _conversationRefreshDebounceTimers.remove(displayThreadId);
        final reconcileFallback =
            _pendingConversationRefreshFallbacks.remove(displayThreadId) ??
            fallback;
        unawaited(
          _refreshConversationsBestEffort(
            reconcileFallback,
            displayThreadId: displayThreadId,
          ),
        );
      },
    );
  }

  Future<void> _refreshConversationsBestEffort(
    ConversationSummary fallback, {
    required String displayThreadId,
  }) async {
    if (!mounted) {
      return;
    }
    try {
      await ref.read(conversationListProvider.notifier).refresh();
      if (!mounted) {
        return;
      }
      final remoteConversation = _refreshedConversationFor(fallback);
      final refreshedConversation = _newerConversation(
        remoteConversation,
        fallback,
      );
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(refreshedConversation);
      unawaited(
        syncHistoryForConversation(
          remoteConversation,
          displayThreadId: displayThreadId,
          force: true,
          showLoading: false,
        ),
      );
    } catch (_) {
      // The local thread has already been updated with the send result. A
      // follow-up conversation-list refresh should not turn a completed send
      // into a visible low-level SDK error.
    }
  }

  void clear() {
    _cancelAgentProcessingTimers();
    _cancelConversationRefreshTimer();
    _pendingHistorySyncs.clear();
    _activeLocalHistoryLoads.clear();
    _activeRemoteHistorySyncs.clear();
    state = const <String, ChatThreadState>{};
  }

  void _queuePendingHistorySync(
    String threadId,
    ConversationSummary conversation, {
    required bool force,
    required bool reportFailure,
    required bool showLoading,
  }) {
    final existing = _pendingHistorySyncs[threadId];
    _pendingHistorySyncs[threadId] = existing == null
        ? _PendingHistorySync(
            conversation: conversation,
            force: force,
            reportFailure: reportFailure,
            showLoading: showLoading,
          )
        : _PendingHistorySync(
            conversation: _newerConversation(
              conversation,
              existing.conversation,
            ),
            force: existing.force || force,
            reportFailure: existing.reportFailure || reportFailure,
            showLoading: existing.showLoading || showLoading,
          );
  }

  void _runPendingHistorySyncIfNeeded(String threadId) {
    final pending = _pendingHistorySyncs.remove(threadId);
    if (pending == null ||
        (!pending.force &&
            !_shouldLoadHistory(thread(threadId), pending.conversation))) {
      return;
    }
    unawaited(
      syncHistoryForConversation(
        pending.conversation,
        displayThreadId: threadId,
        force: pending.force,
        reportFailure: pending.reportFailure,
        showLoading: pending.showLoading,
      ),
    );
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
    final totalWatch = Stopwatch()..start();
    final current = List<ChatMessage>.from(thread(threadId).messages);
    final indexes = _MessageMergeIndexes(current);
    final newlyMergedMessages = <ChatMessage>[];
    AwikiPerformanceLogger.sync(
      'chat.messages.merge_loop',
      () {
        for (final message in incoming.where(
          (message) => message.hasRenderableContent,
        )) {
          final index = indexes.matchingIndex(
            current,
            message,
            _isMatchingPending,
          );
          if (index >= 0) {
            final previous = current[index];
            current[index] = _withPreservedAttachmentState(message, previous);
            indexes.replace(index, current[index]);
          } else {
            current.add(message);
            indexes.add(current.length - 1, message);
            newlyMergedMessages.add(message);
          }
        }
      },
      fields: <String, Object?>{
        ...AwikiPerformanceLogger.threadField(threadId),
        'current': current.length,
        'incoming': incoming.length,
        'indexed': true,
      },
      minMs: 1,
      level: AwikiPerformanceLogLevel.verbose,
    );
    final messages = resolveStaleSending
        ? AwikiPerformanceLogger.sync(
            'chat.messages.resolve_stale',
            () => _markStaleSendingFailed(current),
            fields: <String, Object?>{
              ...AwikiPerformanceLogger.threadField(threadId),
              'items': current.length,
            },
            minMs: 1,
            level: AwikiPerformanceLogLevel.verbose,
          )
        : current;
    final previous = thread(threadId);
    final nextAgentPendingTurns = AwikiPerformanceLogger.sync(
      'chat.messages.pending_turns',
      () => _nextAgentPendingTurnsAfterMerge(
        previous.agentPendingTurns,
        newlyMergedMessages,
        trustIncomingAgentReply: trustIncomingAgentReply,
      ),
      fields: <String, Object?>{
        ...AwikiPerformanceLogger.threadField(threadId),
        'new': newlyMergedMessages.length,
        'pending': previous.agentPendingTurns.length,
      },
      minMs: 1,
      level: AwikiPerformanceLogLevel.verbose,
    );
    final sortedMessages = AwikiPerformanceLogger.sync(
      'chat.messages.sort',
      () => _sortMessages(messages),
      fields: <String, Object?>{
        ...AwikiPerformanceLogger.threadField(threadId),
        'items': messages.length,
      },
      minMs: 1,
      level: AwikiPerformanceLogLevel.verbose,
    );
    state = <String, ChatThreadState>{
      ...state,
      threadId: ChatThreadState(
        threadId: threadId,
        messages: sortedMessages,
        isLoading: isLoading ?? previous.isLoading,
        agentPendingTurns: nextAgentPendingTurns,
        messageAgentSyncs: previous.messageAgentSyncs,
        appActionRecords: previous.appActionRecords,
      ),
    };
    totalWatch.stop();
    AwikiPerformanceLogger.log(
      'chat.messages.merge',
      elapsed: totalWatch.elapsed,
      fields: <String, Object?>{
        ...AwikiPerformanceLogger.threadField(threadId),
        'incoming': incoming.length,
        'new': newlyMergedMessages.length,
        'total': sortedMessages.length,
      },
      minMs: 1,
    );
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
    required String displayThreadId,
    required String? expectedAgentReplyDid,
    required List<ChatMentionDraft> mentions,
    required String submittedLocalMessageId,
    required ChatMessage deliveredMessage,
  }) {
    final remoteMessageId = deliveredMessage.remoteId?.trim().isNotEmpty == true
        ? deliveredMessage.remoteId!.trim()
        : deliveredMessage.localId.trim();
    final localMessageId = submittedLocalMessageId.trim().isNotEmpty
        ? submittedLocalMessageId.trim()
        : deliveredMessage.localId.trim();
    if (!deliveredMessage.isMine ||
        deliveredMessage.sendState != MessageSendState.sent ||
        localMessageId.isEmpty) {
      return;
    }
    final pendingTargets = conversation.isGroup
        ? _agentMentionPendingTargets(mentions)
        : <_AgentPendingTarget>[
            if (_directAgentPendingTarget(conversation, expectedAgentReplyDid)
                case final target?)
              target,
          ];
    if (pendingTargets.isEmpty) {
      return;
    }
    final threadId = displayThreadId;
    final current = thread(threadId);
    final nextTurns = <AgentPendingTurn>[
      ...current.agentPendingTurns.where(
        (turn) =>
            turn.localMessageId != localMessageId &&
            turn.remoteMessageId != remoteMessageId,
      ),
      for (final target in pendingTargets)
        AgentPendingTurn(
          agentDid: target.agentDid,
          localMessageId: localMessageId,
          remoteMessageId: remoteMessageId,
          mentionId: target.mentionId,
          agentHandle: target.agentHandle,
          startedAt: deliveredMessage.createdAt,
        ),
    ];
    state = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(agentPendingTurns: nextTurns),
    };
    _scheduleAgentProcessingOverdue(threadId);
  }

  _AgentPendingTarget? _directAgentPendingTarget(
    ConversationSummary conversation,
    String? expectedAgentReplyDid,
  ) {
    final agentDid = expectedAgentReplyDid?.trim();
    if (agentDid == null || agentDid.isEmpty) {
      return null;
    }
    return _AgentPendingTarget(
      agentDid: agentDid,
      agentHandle: _directAgentPendingHandle(conversation, agentDid),
      mentionId: null,
    );
  }

  String? _directAgentPendingHandle(
    ConversationSummary conversation,
    String agentDid,
  ) {
    final peer = conversation.targetPeer?.trim();
    if (peer != null && peer.isNotEmpty && !peer.startsWith('did:')) {
      return _handleLocalPart(peer);
    }
    return null;
  }

  void applyAgentRunStatusPayload(Map<String, Object?> payload) {
    if (payload['schema'] != 'awiki.agent.status.v1') {
      return;
    }
    final scope = payload['status_scope']?.toString().trim();
    if (scope != 'run' && scope != 'snapshot') {
      return;
    }
    final runs = payload['runs'];
    if (runs is! List) {
      return;
    }
    if (scope == 'snapshot') {
      final payloadAt = _parseRunTimestamp(payload['sent_at']);
      final activeRunsByAgent = <String, List<Map<String, Object?>>>{};
      final snapshotRuntimeDids = <String>{};
      final snapshotAtByRuntimeDid = <String, DateTime?>{};
      final runtimes = payload['runtimes'];
      if (runtimes is List) {
        for (final item in runtimes) {
          if (item is! Map) {
            continue;
          }
          final runtime = _stringKeyMap(item);
          final runtimeDid = runtime['agent_did']?.toString().trim().ifNotEmpty;
          if (runtimeDid == null) {
            continue;
          }
          snapshotRuntimeDids.add(runtimeDid);
          snapshotAtByRuntimeDid[runtimeDid] =
              _parseRunTimestamp(runtime['last_seen_at']) ??
              _parseRunTimestamp(runtime['updated_at']) ??
              payloadAt;
        }
      }
      for (final item in runs) {
        if (item is! Map) {
          continue;
        }
        final run = _stringKeyMap(item);
        final status = run['status']?.toString().trim();
        final agentDid =
            run['runtime_agent_did']?.toString().trim().ifNotEmpty ??
            run['agent_did']?.toString().trim().ifNotEmpty;
        if (status == null || agentDid == null || !_isActiveRunStatus(status)) {
          continue;
        }
        snapshotRuntimeDids.add(agentDid);
        activeRunsByAgent.putIfAbsent(agentDid, () => <Map<String, Object?>>[]);
        activeRunsByAgent[agentDid]!.add(run);
      }
      _reconcileAgentPendingTurnsWithSnapshot(
        activeRunsByAgent: activeRunsByAgent,
        snapshotRuntimeDids: snapshotRuntimeDids,
        snapshotAtByRuntimeDid: snapshotAtByRuntimeDid,
      );
    }
    for (final item in runs) {
      if (item is Map) {
        _applyAgentRunStatus(_stringKeyMap(item), payload);
      }
    }
  }

  void _applyAgentRunStatus(
    Map<String, Object?> run,
    Map<String, Object?> payload,
  ) {
    final status = run['status']?.toString().trim();
    if (status == null || status.isEmpty) {
      return;
    }
    final agentDid =
        run['runtime_agent_did']?.toString().trim().ifNotEmpty ??
        run['agent_did']?.toString().trim().ifNotEmpty;
    if (agentDid == null || agentDid.isEmpty) {
      return;
    }
    final conversationId =
        run['conversation_id']?.toString().trim().ifNotEmpty ??
        payload['conversation_id']?.toString().trim().ifNotEmpty;
    final sourceMessageId = run['source_message_id']
        ?.toString()
        .trim()
        .ifNotEmpty;
    final messageId =
        run['message_id']?.toString().trim().ifNotEmpty ??
        payload['task_id']?.toString().trim().ifNotEmpty;
    final mentionId = run['mention_id']?.toString().trim().ifNotEmpty;
    final startedAt = _parseRunTimestamp(run['started_at']) ?? DateTime.now();
    final agentHandle =
        run['runtime_agent_handle']?.toString().trim().ifNotEmpty ??
        run['agent_handle']?.toString().trim().ifNotEmpty;
    if (_isActiveRunStatus(status)) {
      _upsertAgentPendingTurnFromStatus(
        agentDid: agentDid,
        conversationId: conversationId,
        sourceMessageId: sourceMessageId,
        messageId: messageId,
        mentionId: mentionId,
        agentHandle: agentHandle,
        startedAt: startedAt,
      );
      return;
    }
    if (!_isTerminalRunStatus(status)) {
      return;
    }
    final nextState = Map<String, ChatThreadState>.from(state);
    var changed = false;
    final changedThreadIds = <String>[];
    for (final entry in state.entries) {
      final thread = entry.value;
      if (thread.agentPendingTurns.isEmpty) {
        continue;
      }
      final hasMatchingTurn = thread.agentPendingTurns.any(
        (turn) => _runStatusMatchesPendingTurn(
          turn,
          agentDid: agentDid,
          sourceMessageId: sourceMessageId,
          messageId: messageId,
          mentionId: mentionId,
        ),
      );
      if (conversationId != null &&
          entry.key != conversationId &&
          !hasMatchingTurn) {
        continue;
      }
      final nextTurns = <AgentPendingTurn>[
        for (final turn in thread.agentPendingTurns)
          if (!_runStatusMatchesPendingTurn(
            turn,
            agentDid: agentDid,
            sourceMessageId: sourceMessageId,
            messageId: messageId,
            mentionId: mentionId,
          ))
            turn,
      ];
      if (nextTurns.length == thread.agentPendingTurns.length) {
        continue;
      }
      changed = true;
      nextState[entry.key] = thread.copyWith(agentPendingTurns: nextTurns);
      changedThreadIds.add(entry.key);
    }
    if (changed) {
      state = nextState;
      for (final threadId in changedThreadIds) {
        if (state[threadId]?.agentPendingTurns.isEmpty ?? true) {
          _cancelAgentProcessingTimer(threadId);
        } else {
          _scheduleAgentProcessingOverdue(threadId);
        }
      }
    }
  }

  void applyMessageAgentControlPayload(Map<String, Object?> payload) {
    final payloadJson = jsonEncode(payload);
    final sync = AgentControlPayloads.decodeMessageSync(payloadJson);
    if (sync != null) {
      _applyMessageAgentSync(sync);
      return;
    }
    final request = AgentControlPayloads.decodeAppAction(payloadJson);
    if (request != null) {
      _applyAppActionRequest(request);
      return;
    }
    final result = AgentControlPayloads.decodeAppActionResult(payloadJson);
    if (result != null) {
      _applyAppActionResult(result);
    }
  }

  Future<void> confirmAppAction({
    required ConversationSummary conversation,
    required String actionId,
  }) async {
    final threadId = conversation.threadId;
    final record = thread(threadId).appActionRecords[actionId];
    final request = record?.request;
    if (record == null || request == null || record.isTerminal) {
      return;
    }
    if (!request.isAllowedInMvp) {
      await _sendAppActionResult(
        threadId: threadId,
        request: request,
        state: appActionStateFailed,
        errorCode: 'app_action_not_allowed',
        errorSummary: '此操作不在当前版本允许范围内',
      );
      return;
    }
    if (request.action != 'message.create_draft') {
      await _sendAppActionResult(
        threadId: threadId,
        request: request,
        state: appActionStateFailed,
        errorCode: 'app_action_handler_unavailable',
        errorSummary: '此操作暂未接入 Human App 执行器',
      );
      return;
    }
    if (_targetDaemonDidForAppAction(request) == null) {
      await _sendAppActionResult(
        threadId: threadId,
        request: request,
        state: appActionStateFailed,
        errorCode: 'app_action_result_target_missing',
        errorSummary: '找不到 Message Agent 所属 Daemon',
      );
      return;
    }
    final draftText = _draftTextForAppAction(request);
    if (draftText == null) {
      await _sendAppActionResult(
        threadId: threadId,
        request: request,
        state: appActionStateFailed,
        errorCode: 'app_action_missing_draft',
        errorSummary: '草稿内容为空',
      );
      return;
    }
    ref
        .read(chatComposerDraftsProvider.notifier)
        .setText(conversation, draftText);
    await _sendAppActionResult(
      threadId: threadId,
      request: request,
      state: appActionStateSucceeded,
      result: <String, Object?>{'draft_text': draftText},
    );
  }

  Future<void> rejectAppAction({
    required ConversationSummary conversation,
    required String actionId,
  }) async {
    final threadId = conversation.threadId;
    final record = thread(threadId).appActionRecords[actionId];
    final request = record?.request;
    if (record == null || request == null || record.isTerminal) {
      return;
    }
    await _sendAppActionResult(
      threadId: threadId,
      request: request,
      state: appActionStateRejected,
      errorCode: 'user_rejected',
      errorSummary: '用户已拒绝',
    );
  }

  void _applyMessageAgentSync(MessageSyncPayload payload) {
    final record = MessageAgentSyncRecord.fromPayload(payload);
    final threadId = _threadIdForMessageAgentSync(record);
    if (threadId == null || threadId.isEmpty) {
      return;
    }
    _upsertMessageAgentSyncRecord(threadId, record);
    final runtimeAgentDid = record.runtimeAgentDid?.trim();
    if (runtimeAgentDid == null || runtimeAgentDid.isEmpty) {
      return;
    }
    if (record.isRuntimeStatus && _isActiveRunStatus(record.state ?? '')) {
      _upsertAgentPendingTurnFromStatus(
        agentDid: runtimeAgentDid,
        conversationId: threadId,
        sourceMessageId: record.messageId,
        messageId: record.runId,
        mentionId: null,
        agentHandle: null,
        startedAt: DateTime.now(),
      );
      return;
    }
    if (record.isTerminal) {
      _clearAgentPendingTurnsForMessageAgent(
        threadId: threadId,
        runtimeAgentDid: runtimeAgentDid,
        sourceMessageId: record.messageId,
        runId: record.runId,
      );
    }
  }

  void _upsertMessageAgentSyncRecord(
    String threadId,
    MessageAgentSyncRecord record,
  ) {
    final current = thread(threadId);
    final nextRecords = <MessageAgentSyncRecord>[];
    var replaced = false;
    for (final item in current.messageAgentSyncs) {
      if (item.identityKey == record.identityKey) {
        nextRecords.add(record);
        replaced = true;
      } else {
        nextRecords.add(item);
      }
    }
    if (!replaced) {
      nextRecords.add(record);
    }
    state = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(
        messageAgentSyncs: _limitMessageAgentSyncs(nextRecords),
      ),
    };
  }

  List<MessageAgentSyncRecord> _limitMessageAgentSyncs(
    List<MessageAgentSyncRecord> records,
  ) {
    if (records.length <= 40) {
      return records;
    }
    return records.sublist(records.length - 40);
  }

  void _applyAppActionRequest(AppActionRequestPayload request) {
    final threadId = _threadIdForAppActionRequest(request);
    if (threadId == null || threadId.isEmpty) {
      return;
    }
    final current = thread(threadId);
    final nextRecords = <String, AppActionRecord>{
      ...current.appActionRecords,
      request.actionId: AppActionRecord(
        actionId: request.actionId,
        action: request.action,
        state: request.state,
        request: request,
        result: current.appActionRecords[request.actionId]?.result,
      ),
    };
    state = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(appActionRecords: nextRecords),
    };
  }

  void _applyAppActionResult(AppActionResultPayload result) {
    var changed = false;
    final nextState = Map<String, ChatThreadState>.from(state);
    for (final entry in state.entries) {
      final existing = entry.value.appActionRecords[result.actionId];
      if (existing == null || existing.action != result.action) {
        continue;
      }
      changed = true;
      nextState[entry.key] = entry.value.copyWith(
        appActionRecords: <String, AppActionRecord>{
          ...entry.value.appActionRecords,
          result.actionId: existing.applyResult(result),
        },
      );
    }
    if (!changed) {
      return;
    }
    state = nextState;
  }

  Future<void> _sendAppActionResult({
    required String threadId,
    required AppActionRequestPayload request,
    required String state,
    Map<String, Object?> result = const <String, Object?>{},
    String? errorCode,
    String? errorSummary,
  }) async {
    final payload = appActionResultPayload(
      request: request,
      state: state,
      result: result,
      errorCode: errorCode,
      errorSummary: errorSummary,
    );
    final targetDid = _targetDaemonDidForAppAction(request);
    if (targetDid == null || targetDid.isEmpty) {
      final failed = appActionResultPayload(
        request: request,
        state: appActionStateFailed,
        errorCode: 'app_action_result_target_missing',
        errorSummary: '找不到 Message Agent 所属 Daemon',
      );
      _applyLocalAppActionResult(threadId, failed);
      return;
    }
    try {
      await ref
          .read(messagingServiceProvider)
          .sendPayload(
            thread: AppThreadRef.direct(targetDid),
            payload: payload,
            secure: true,
            idempotencyKey: 'app-action-result:${request.actionId}:$state',
          )
          .timeout(_sendTimeout);
      _applyLocalAppActionResult(threadId, payload);
    } catch (_) {
      final failed = appActionResultPayload(
        request: request,
        state: appActionStateFailed,
        errorCode: 'app_action_result_send_failed',
        errorSummary: '回传执行结果失败',
      );
      _applyLocalAppActionResult(threadId, failed);
    }
  }

  void _applyLocalAppActionResult(
    String threadId,
    Map<String, Object?> payload,
  ) {
    final result = AgentControlPayloads.decodeAppActionResult(
      jsonEncode(payload),
    );
    if (result == null) {
      return;
    }
    final current = thread(threadId);
    final existing = current.appActionRecords[result.actionId];
    final nextRecord = existing == null
        ? AppActionRecord(
            actionId: result.actionId,
            action: result.action,
            state: result.state,
            result: result,
          )
        : existing.applyResult(result);
    state = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(
        appActionRecords: <String, AppActionRecord>{
          ...current.appActionRecords,
          result.actionId: nextRecord,
        },
      ),
    };
  }

  String? _draftTextForAppAction(AppActionRequestPayload request) {
    String? stringValue(Object? value) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty) {
        return null;
      }
      return text;
    }

    final args = request.args;
    final message = args['message'];
    return stringValue(args['draft_text']) ??
        stringValue(args['draft']) ??
        stringValue(args['text']) ??
        stringValue(args['content']) ??
        (message is Map ? stringValue(message['text']) : null);
  }

  String? _targetDaemonDidForAppAction(AppActionRequestPayload request) {
    final explicit = request.daemonAgentDid?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final runtimeDid = request.runtimeAgentDid?.trim();
    if (runtimeDid != null && runtimeDid.isNotEmpty) {
      for (final agent in ref.read(agentsProvider).agents) {
        if (agent.agentDid == runtimeDid) {
          final daemonDid = agent.daemonAgentDid?.trim();
          if (daemonDid != null && daemonDid.isNotEmpty) {
            return daemonDid;
          }
        }
      }
    }
    return null;
  }

  String? _threadIdForMessageAgentSync(MessageAgentSyncRecord record) {
    return _threadIdForSourceMessage(record.messageId) ??
        _threadIdForConversationControl(record.conversationId) ??
        (record.runtimeAgentDid == null
            ? null
            : _threadIdForAgentDid(record.runtimeAgentDid!));
  }

  String? _threadIdForAppActionRequest(AppActionRequestPayload request) {
    return _threadIdForSourceMessage(request.sourceMessageId) ??
        _threadIdForConversationControl(request.conversationId) ??
        (request.runtimeAgentDid == null
            ? null
            : _threadIdForAgentDid(request.runtimeAgentDid!));
  }

  String? _threadIdForConversationControl(String? conversationId) {
    final explicit = conversationId?.trim();
    if (explicit == null || explicit.isEmpty) {
      return null;
    }
    if (state.containsKey(explicit)) {
      return explicit;
    }
    for (final conversation
        in ref.read(conversationListProvider).conversations) {
      if (conversation.threadId == explicit ||
          conversation.visibilityKeys.contains(explicit)) {
        return conversation.threadId;
      }
    }
    for (final entry in state.entries) {
      final identity = _conversationIdentityForThread(entry.key, entry.value);
      if (identity.threadId == explicit ||
          identity.visibilityKeys.contains(explicit)) {
        return entry.key;
      }
    }
    return explicit;
  }

  String? _threadIdForSourceMessage(String? messageId) {
    final normalized = messageId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final entry in state.entries) {
      if (entry.value.messages.any(
        (message) =>
            message.localId == normalized || message.remoteId == normalized,
      )) {
        return entry.key;
      }
    }
    return null;
  }

  void _clearAgentPendingTurnsForMessageAgent({
    required String threadId,
    required String runtimeAgentDid,
    required String? sourceMessageId,
    required String? runId,
  }) {
    final current = state[threadId];
    if (current == null || current.agentPendingTurns.isEmpty) {
      return;
    }
    final nextTurns = <AgentPendingTurn>[
      for (final turn in current.agentPendingTurns)
        if (!_runStatusMatchesPendingTurn(
          turn,
          agentDid: runtimeAgentDid,
          sourceMessageId: sourceMessageId,
          messageId: runId,
          mentionId: null,
        ))
          turn,
    ];
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

  void _reconcileAgentPendingTurnsWithSnapshot({
    required Map<String, List<Map<String, Object?>>> activeRunsByAgent,
    required Set<String> snapshotRuntimeDids,
    required Map<String, DateTime?> snapshotAtByRuntimeDid,
  }) {
    if (state.isEmpty || snapshotRuntimeDids.isEmpty) {
      return;
    }
    final nextState = Map<String, ChatThreadState>.from(state);
    final changedThreadIds = <String>[];
    for (final entry in state.entries) {
      final thread = entry.value;
      if (thread.agentPendingTurns.isEmpty) {
        continue;
      }
      final nextTurns = <AgentPendingTurn>[
        for (final turn in thread.agentPendingTurns)
          if (!snapshotRuntimeDids.contains(turn.agentDid.trim()) ||
              _pendingTurnIsNewerThanSnapshot(
                turn,
                snapshotAtByRuntimeDid[turn.agentDid.trim()],
              ) ||
              _pendingTurnStillActiveInSnapshot(turn, activeRunsByAgent))
            turn,
      ];
      if (nextTurns.length == thread.agentPendingTurns.length) {
        continue;
      }
      nextState[entry.key] = thread.copyWith(agentPendingTurns: nextTurns);
      changedThreadIds.add(entry.key);
    }
    if (changedThreadIds.isEmpty) {
      return;
    }
    state = nextState;
    for (final threadId in changedThreadIds) {
      if (state[threadId]?.agentPendingTurns.isEmpty ?? true) {
        _cancelAgentProcessingTimer(threadId);
      } else {
        _scheduleAgentProcessingOverdue(threadId);
      }
    }
  }

  bool _pendingTurnIsNewerThanSnapshot(
    AgentPendingTurn turn,
    DateTime? snapshotAt,
  ) {
    return snapshotAt != null && turn.startedAt.isAfter(snapshotAt);
  }

  bool _pendingTurnStillActiveInSnapshot(
    AgentPendingTurn turn,
    Map<String, List<Map<String, Object?>>> activeRunsByAgent,
  ) {
    final runs = activeRunsByAgent[turn.agentDid.trim()];
    if (runs == null || runs.isEmpty) {
      return false;
    }
    for (final run in runs) {
      final sourceMessageId = run['source_message_id']
          ?.toString()
          .trim()
          .ifNotEmpty;
      final messageId =
          run['message_id']?.toString().trim().ifNotEmpty ??
          run['task_id']?.toString().trim().ifNotEmpty;
      final mentionId = run['mention_id']?.toString().trim().ifNotEmpty;
      if (_runStatusMatchesPendingTurn(
        turn,
        agentDid: turn.agentDid,
        sourceMessageId: sourceMessageId,
        messageId: messageId,
        mentionId: mentionId,
      )) {
        return true;
      }
    }
    return false;
  }

  bool _isActiveRunStatus(String status) {
    return isActiveAgentRunStatus(status);
  }

  bool _isTerminalRunStatus(String status) {
    return status == 'succeeded' || status == 'finished' || status == 'failed';
  }

  DateTime? _parseRunTimestamp(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text);
  }

  void _upsertAgentPendingTurnFromStatus({
    required String agentDid,
    required String? conversationId,
    required String? sourceMessageId,
    required String? messageId,
    required String? mentionId,
    required String? agentHandle,
    required DateTime startedAt,
  }) {
    final threadId = _threadIdForAgentRunStatus(
      conversationId: conversationId,
      agentDid: agentDid,
      sourceMessageId: sourceMessageId,
      messageId: messageId,
      mentionId: mentionId,
    );
    if (threadId == null || threadId.isEmpty) {
      return;
    }
    final current = thread(threadId);
    final pendingLocalMessageId =
        sourceMessageId ??
        messageId ??
        'agent-run:$agentDid:${mentionId ?? startedAt.microsecondsSinceEpoch}';
    final pendingRemoteMessageId = sourceMessageId ?? messageId;
    var found = false;
    final nextTurns = <AgentPendingTurn>[];
    for (final turn in current.agentPendingTurns) {
      if (_runStatusMatchesPendingTurn(
        turn,
        agentDid: agentDid,
        sourceMessageId: sourceMessageId,
        messageId: messageId,
        mentionId: mentionId,
      )) {
        found = true;
        nextTurns.add(
          AgentPendingTurn(
            agentDid: turn.agentDid,
            localMessageId: turn.localMessageId,
            remoteMessageId: turn.remoteMessageId ?? pendingRemoteMessageId,
            mentionId: turn.mentionId ?? mentionId,
            agentHandle: turn.agentHandle ?? agentHandle,
            startedAt: turn.startedAt,
            isOverdue: turn.isOverdue,
          ),
        );
      } else {
        nextTurns.add(turn);
      }
    }
    if (!found) {
      nextTurns.add(
        AgentPendingTurn(
          agentDid: agentDid,
          localMessageId: pendingLocalMessageId,
          remoteMessageId: pendingRemoteMessageId,
          mentionId: mentionId,
          agentHandle: agentHandle,
          startedAt: startedAt,
        ),
      );
    }
    state = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(agentPendingTurns: nextTurns),
    };
    _scheduleAgentProcessingOverdue(threadId);
  }

  String? _threadIdForAgentRunStatus({
    required String? conversationId,
    required String agentDid,
    required String? sourceMessageId,
    required String? messageId,
    required String? mentionId,
  }) {
    final explicit = conversationId?.trim();
    if (explicit != null &&
        explicit.isNotEmpty &&
        state.containsKey(explicit)) {
      return explicit;
    }
    for (final entry in state.entries) {
      final thread = entry.value;
      if (thread.agentPendingTurns.any(
        (turn) => _runStatusMatchesPendingTurn(
          turn,
          agentDid: agentDid,
          sourceMessageId: sourceMessageId,
          messageId: messageId,
          mentionId: mentionId,
        ),
      )) {
        return entry.key;
      }
    }
    if (explicit != null &&
        explicit.isNotEmpty &&
        !explicit.startsWith('direct:')) {
      return explicit;
    }
    return _threadIdForAgentDid(agentDid);
  }

  String _threadIdForAgentDid(String agentDid) {
    for (final conversation
        in ref.read(conversationListProvider).conversations) {
      if (!conversation.isGroup &&
          (conversation.targetDid == agentDid ||
              conversation.targetPeer == agentDid ||
              conversation.threadId == 'direct:$agentDid')) {
        return conversation.threadId;
      }
    }
    return 'direct:$agentDid';
  }

  bool _runStatusMatchesPendingTurn(
    AgentPendingTurn turn, {
    required String agentDid,
    required String? sourceMessageId,
    required String? messageId,
    required String? mentionId,
  }) {
    if (turn.agentDid.trim() != agentDid) {
      return false;
    }
    if (sourceMessageId != null &&
        (turn.remoteMessageId == sourceMessageId ||
            turn.localMessageId == sourceMessageId)) {
      return true;
    }
    if (sourceMessageId != null) {
      return false;
    }
    if (messageId != null &&
        (turn.remoteMessageId == messageId ||
            turn.localMessageId == messageId)) {
      return true;
    }
    if (messageId != null) {
      return false;
    }
    if (mentionId != null && turn.mentionId == mentionId) {
      return true;
    }
    return false;
  }

  List<_AgentPendingTarget> _agentMentionPendingTargets(
    List<ChatMentionDraft> mentions,
  ) {
    final targets = <_AgentPendingTarget>[];
    final seenAgentDids = <String>{};
    for (final mention in mentions) {
      final target = mention.target;
      if (target.kind != ChatMentionTargetKind.agent) {
        continue;
      }
      final agentDid = target.did?.trim();
      if (agentDid == null ||
          agentDid.isEmpty ||
          !seenAgentDids.add(agentDid)) {
        continue;
      }
      targets.add(
        _AgentPendingTarget(
          agentDid: agentDid,
          agentHandle: mentionTargetDisplayHandle(target),
          mentionId: mention.localId,
        ),
      );
    }
    return targets;
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
      final replyToMessageId = _replyToMessageId(message);
      final index = next.indexWhere((turn) {
        if (turn.agentDid.trim() != senderDid) {
          return false;
        }
        if (replyToMessageId != null && replyToMessageId.isNotEmpty) {
          return turn.remoteMessageId == replyToMessageId ||
              turn.localMessageId == replyToMessageId;
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

  String? _replyToMessageId(ChatMessage message) {
    final payloadJson = message.payloadJson?.trim();
    if (payloadJson == null || payloadJson.isEmpty) {
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(payloadJson);
    } on Object {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    final annotations = decoded['annotations'];
    if (annotations is! Map) {
      return null;
    }
    final value = annotations['awiki_reply_to_message_id']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
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

  void _cancelConversationRefreshTimer() {
    for (final timer in _conversationRefreshDebounceTimers.values) {
      timer.cancel();
    }
    _conversationRefreshDebounceTimers.clear();
    _pendingConversationRefreshFallbacks.clear();
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
    _cancelConversationRefreshTimer();
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
    return _MessageMergeIndexes(
      current,
    ).matchingIndex(current, incoming, _isMatchingPending);
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

class _MessageMergeIndexes {
  _MessageMergeIndexes(List<ChatMessage> messages) {
    for (var i = 0; i < messages.length; i += 1) {
      add(i, messages[i]);
    }
  }

  final Map<String, List<int>> _byRemoteId = <String, List<int>>{};
  final Map<String, List<int>> _byLocalId = <String, List<int>>{};
  final Set<int> _pendingIndexes = <int>{};

  int matchingIndex(
    List<ChatMessage> current,
    ChatMessage incoming,
    bool Function(ChatMessage pending, ChatMessage sent) isMatchingPending,
  ) {
    final remoteId = _nonEmptyKey(incoming.remoteId);
    if (remoteId != null) {
      final remoteIndex = _firstMatchingIndex(
        _byRemoteId[remoteId],
        current,
        (message) => message.remoteId == remoteId,
      );
      if (remoteIndex != null) {
        return remoteIndex;
      }
    }
    final localId = _nonEmptyKey(incoming.localId);
    if (localId != null) {
      final localIndex = _firstMatchingIndex(
        _byLocalId[localId],
        current,
        (message) => message.localId == localId,
      );
      if (localIndex != null) {
        return localIndex;
      }
    }
    if (!incoming.isMine || incoming.sendState != MessageSendState.sent) {
      return -1;
    }
    for (final index in _pendingIndexes) {
      if (index >= current.length) {
        continue;
      }
      if (isMatchingPending(current[index], incoming)) {
        return index;
      }
    }
    return -1;
  }

  void add(int index, ChatMessage message) {
    final remoteId = _nonEmptyKey(message.remoteId);
    if (remoteId != null) {
      _addIndex(_byRemoteId.putIfAbsent(remoteId, () => <int>[]), index);
    }
    final localId = _nonEmptyKey(message.localId);
    if (localId != null) {
      _addIndex(_byLocalId.putIfAbsent(localId, () => <int>[]), index);
    }
    if (_isPendingCandidate(message)) {
      _pendingIndexes.add(index);
    }
  }

  void replace(int index, ChatMessage next) {
    _pendingIndexes.remove(index);
    add(index, next);
  }

  static int? _firstMatchingIndex(
    List<int>? indexes,
    List<ChatMessage> current,
    bool Function(ChatMessage message) matches,
  ) {
    if (indexes == null) {
      return null;
    }
    for (final index in indexes) {
      if (index < current.length && matches(current[index])) {
        return index;
      }
    }
    return null;
  }

  static void _addIndex(List<int> indexes, int index) {
    if (!indexes.contains(index)) {
      indexes.add(index);
    }
  }

  static bool _isPendingCandidate(ChatMessage message) {
    return message.isMine && message.sendState != MessageSendState.sent;
  }

  static String? _nonEmptyKey(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
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

AppThreadRef _localHistoryThreadRefFor(ConversationSummary conversation) {
  final groupId = conversation.groupId?.trim();
  if (conversation.isGroup && groupId != null && groupId.isNotEmpty) {
    return AppThreadRef.group(groupId);
  }
  final peerDid = conversation.targetDid?.trim();
  final peer = conversation.targetPeer?.trim();
  if (!conversation.isGroup && peerDid != null && peerDid.isNotEmpty) {
    return AppThreadRef.direct(peerDid);
  }
  if (!conversation.isGroup && peer != null && peer.isNotEmpty) {
    return AppThreadRef.direct(peer);
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

List<ChatMentionDraft> _messageMentionsToDrafts(
  Iterable<ChatMessageMention> mentions,
) {
  return mentions
      .map(
        (mention) => ChatMentionDraft(
          localId: mention.id,
          surface: mention.surface,
          start: mention.start,
          end: mention.end,
          target: mention.target,
          role: mention.role,
        ),
      )
      .toList();
}

Map<String, Object?> _stringKeyMap(Map<dynamic, dynamic> value) {
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

String _handleLocalPart(String value) {
  final normalized = value.trim();
  final withoutAt = normalized.startsWith('@')
      ? normalized.substring(1).trimLeft()
      : normalized;
  final dotIndex = withoutAt.indexOf('.');
  if (dotIndex <= 0) {
    return withoutAt;
  }
  return withoutAt.substring(0, dotIndex);
}

extension _NonEmptyStringExtension on String {
  String? get ifNotEmpty => isEmpty ? null : this;
}

final chatThreadsProvider =
    StateNotifierProvider<ChatThreadsController, Map<String, ChatThreadState>>(
      (ref) => ChatThreadsController(ref),
    );

final pendingAgentDidsProvider = Provider<Set<String>>((ref) {
  final threads = ref.watch(chatThreadsProvider);
  return activePendingAgentDids(threads);
});

final pendingAgentDidsForThreadProvider = Provider.family<Set<String>, String>((
  ref,
  threadId,
) {
  final thread = ref.watch(chatThreadProvider(threadId));
  return <String>{
    for (final turn in thread.agentPendingTurns)
      if (turn.isActive) turn.agentDid,
  };
});

Set<String> activePendingAgentDids(Map<String, ChatThreadState> threads) {
  return <String>{
    for (final thread in threads.values)
      for (final turn in thread.agentPendingTurns)
        if (turn.isActive) turn.agentDid,
  };
}

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
