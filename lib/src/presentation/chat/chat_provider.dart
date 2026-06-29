import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/message_sync_service.dart';
import '../../application/models/attachment_models.dart';
import '../../application/models/app_thread_ref.dart';
import '../../application/models/thread_message_patch.dart';
import '../../application/messaging_service.dart';
import '../../application/thread_id_utils.dart';
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

class _ThreadPatchSubscription {
  const _ThreadPatchSubscription({
    required this.token,
    required this.ownerDid,
    required this.threadRef,
    required this.threadKind,
    required this.threadId,
    required this.subscription,
    this.lastVersion = 0,
  });

  final int token;
  final String ownerDid;
  final AppThreadRef threadRef;
  final String threadKind;
  final String threadId;
  final StreamSubscription<ThreadMessagePatch> subscription;
  final int lastVersion;

  String get threadRefKey => threadRef.stableId;

  _ThreadPatchSubscription copyWith({
    StreamSubscription<ThreadMessagePatch>? subscription,
    int? lastVersion,
  }) {
    return _ThreadPatchSubscription(
      token: token,
      ownerDid: ownerDid,
      threadRef: threadRef,
      threadKind: threadKind,
      threadId: threadId,
      subscription: subscription ?? this.subscription,
      lastVersion: lastVersion ?? this.lastVersion,
    );
  }
}

class ThreadMemoryCachePolicy {
  const ThreadMemoryCachePolicy({
    this.hotThreadMessageLimit = 120,
    this.warmThreadMessageLimit = 60,
    this.coldThreadMessageLimit = 20,
    this.maxTotalCachedMessages = 1200,
    this.maxCachedCanonicalThreads = 100,
    this.maxMessageRouteEntries = 4000,
    this.messageRouteTtl = const Duration(hours: 24),
    this.warmSubscriptionTtl = const Duration(minutes: 5),
  });

  final int hotThreadMessageLimit;
  final int warmThreadMessageLimit;
  final int coldThreadMessageLimit;
  final int maxTotalCachedMessages;
  final int maxCachedCanonicalThreads;
  final int maxMessageRouteEntries;
  final Duration messageRouteTtl;
  final Duration warmSubscriptionTtl;
}

class _ThreadCacheEnforcementResult {
  const _ThreadCacheEnforcementResult({
    required this.messages,
    required this.trimmedCount,
    required this.protectedOverflow,
  });

  final List<ChatMessage> messages;
  final int trimmedCount;
  final int protectedOverflow;
}

class ChatThreadCacheStats {
  const ChatThreadCacheStats({
    required this.rawThreadStateCount,
    required this.canonicalThreadCount,
    required this.totalRetainedMessages,
    required this.activePatchSubscriptionCount,
    required this.messageRouteEntryCount,
    required this.trimmedMessageCount,
    required this.evictedThreadCount,
    required this.protectedOverflowCount,
  });

  final int rawThreadStateCount;
  final int canonicalThreadCount;
  final int totalRetainedMessages;
  final int activePatchSubscriptionCount;
  final int messageRouteEntryCount;
  final int trimmedMessageCount;
  final int evictedThreadCount;
  final int protectedOverflowCount;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'cache.raw_thread_state_count': rawThreadStateCount,
      'cache.canonical_thread_count': canonicalThreadCount,
      'cache.total_retained_messages': totalRetainedMessages,
      'cache.active_patch_subscription_count': activePatchSubscriptionCount,
      'cache.message_route_entry_count': messageRouteEntryCount,
      'cache.trimmed_message_count': trimmedMessageCount,
      'cache.evicted_thread_count': evictedThreadCount,
      'cache.protected_overflow_count': protectedOverflowCount,
    };
  }
}

class _ThreadCacheMetadata {
  const _ThreadCacheMetadata({
    required this.canonicalKey,
    required this.lastTouchedAt,
    this.isVisible = false,
    this.hiddenAt,
  });

  final String canonicalKey;
  final DateTime lastTouchedAt;
  final bool isVisible;
  final DateTime? hiddenAt;

  _ThreadCacheMetadata copyWith({
    String? canonicalKey,
    DateTime? lastTouchedAt,
    bool? isVisible,
    Object? hiddenAt = _threadCacheMetadataUnset,
  }) {
    return _ThreadCacheMetadata(
      canonicalKey: canonicalKey ?? this.canonicalKey,
      lastTouchedAt: lastTouchedAt ?? this.lastTouchedAt,
      isVisible: isVisible ?? this.isVisible,
      hiddenAt: identical(hiddenAt, _threadCacheMetadataUnset)
          ? this.hiddenAt
          : hiddenAt as DateTime?,
    );
  }
}

const Object _threadCacheMetadataUnset = Object();

class _MessageThreadRoute {
  const _MessageThreadRoute({
    required this.threadId,
    required this.canonicalKey,
    required this.lastTouchedAt,
  });

  final String threadId;
  final String canonicalKey;
  final DateTime lastTouchedAt;
}

class ChatThreadsController
    extends StateNotifier<Map<String, ChatThreadState>> {
  ChatThreadsController(
    this.ref, {
    ThreadMemoryCachePolicy cachePolicy = const ThreadMemoryCachePolicy(),
  }) : _cachePolicy = cachePolicy,
       super(const <String, ChatThreadState>{});

  final Ref ref;
  final ThreadMemoryCachePolicy _cachePolicy;
  static const Duration _pendingMatchWindow = Duration(minutes: 2);
  static const Duration _staleSendingAge = Duration(seconds: 30);
  static const Duration _sendTimeout = Duration(seconds: 20);
  static const Duration _attachmentSendTimeout = Duration(minutes: 3);
  static const int _initialLocalHistoryLimit = 50;
  static const Duration _attachmentStaleSendingAge = Duration(
    minutes: 3,
    seconds: 30,
  );
  static const Duration agentProcessingOverdueAfter = Duration(seconds: 75);
  static const Duration _agentProcessingReplyClockSkew = Duration(seconds: 2);
  static const Duration _threadPatchStreamResubscribeCooldown = Duration(
    seconds: 2,
  );

  final Map<String, Timer> _agentProcessingTimers = <String, Timer>{};
  final Map<String, _PendingHistorySync> _pendingHistorySyncs =
      <String, _PendingHistorySync>{};
  final Set<String> _activeLocalHistoryLoads = <String>{};
  final Set<String> _activeRemoteHistorySyncs = <String>{};
  final Map<String, _ThreadPatchSubscription> _threadPatchSubscriptions =
      <String, _ThreadPatchSubscription>{};
  final Map<String, _ThreadCacheMetadata> _cacheMetadataByThreadId =
      <String, _ThreadCacheMetadata>{};
  final Map<String, Set<String>> _cacheAliasesByThreadId =
      <String, Set<String>>{};
  final Map<String, Set<String>> _canonicalAliases = <String, Set<String>>{};
  final Map<String, _MessageThreadRoute> _messageThreadRoutes =
      <String, _MessageThreadRoute>{};
  final Map<String, Timer> _threadPatchSubscriptionTtlTimers =
      <String, Timer>{};
  final Map<String, Timer> _hiddenThreadCacheTrimTimers = <String, Timer>{};
  final Map<String, DateTime> _lastThreadPatchStreamEndAt =
      <String, DateTime>{};
  final Set<String> _activeReadReceipts = <String>{};
  final Set<String> _completedReadReceipts = <String>{};
  int _trimmedMessageCount = 0;
  int _evictedThreadCount = 0;
  int _protectedOverflowCount = 0;
  int _threadPatchToken = 0;

  ChatThreadState thread(String threadId) {
    return state[threadId] ?? ChatThreadState(threadId: threadId);
  }

  Future<void> openConversation(
    ConversationSummary conversation, {
    String? displayThreadId,
  }) async {
    final targetThreadId = _displayThreadIdFor(conversation, displayThreadId);
    _touchConversationCache(conversation, targetThreadId);
    AwikiPerformanceLogger.log(
      'chat.open_conversation',
      fields: <String, Object?>{
        ...AwikiPerformanceLogger.threadField(targetThreadId),
        'unread': conversation.unreadCount,
        'is_group': conversation.isGroup,
      },
      level: AwikiPerformanceLogLevel.verbose,
    );
    _ensureThreadPatchSubscription(
      conversation,
      displayThreadId: targetThreadId,
    );
    unawaited(
      _openConversationLocalFirst(
        conversation,
        displayThreadId: targetThreadId,
      ),
    );
    acknowledgeVisibleConversationRead(
      conversation,
      displayThreadId: targetThreadId,
      reason: 'open',
      requireVisible: false,
    );
  }

  Future<void> _openConversationLocalFirst(
    ConversationSummary conversation, {
    required String displayThreadId,
  }) async {
    _warmDisplayThreadFromConversationAliases(
      conversation,
      displayThreadId: displayThreadId,
    );
    final currentBeforeLocal = thread(displayThreadId);
    if (currentBeforeLocal.isLoading ||
        _activeLocalHistoryLoads.contains(displayThreadId) ||
        _activeRemoteHistorySyncs.contains(displayThreadId)) {
      return;
    }
    if (_hasRenderableMessages(currentBeforeLocal)) {
      _logOpenFirstPaintSource(
        displayThreadId,
        source: 'memory_tail',
        items: currentBeforeLocal.messages.length,
      );
      unawaited(
        _syncThreadAfterLocalMax(
          conversation,
          displayThreadId: displayThreadId,
        ),
      );
      return;
    }

    final localResult = await _loadLocalHistory(
      conversation,
      intoThreadId: displayThreadId,
      limit: _initialLocalHistoryLimit,
    );
    if (!mounted) {
      return;
    }
    unawaited(
      _syncThreadAfterLocalMax(conversation, displayThreadId: displayThreadId),
    );
    final currentAfterLocal = thread(displayThreadId);
    if (_hasRenderableMessages(currentAfterLocal)) {
      _logOpenFirstPaintSource(
        displayThreadId,
        source: localResult.loadedAny ? 'local_history' : 'memory_tail',
        items: currentAfterLocal.messages.length,
      );
      return;
    }
    if (_activeRemoteHistorySyncs.contains(displayThreadId)) {
      return;
    }
    final shouldShowRemoteFailure =
        localResult.failed || !localResult.loadedAny;
    unawaited(
      syncHistoryForConversation(
        conversation,
        displayThreadId: displayThreadId,
        force: true,
        reportFailure: shouldShowRemoteFailure,
        showLoading: true,
      ),
    );
  }

  int _warmDisplayThreadFromConversationAliases(
    ConversationSummary conversation, {
    required String displayThreadId,
  }) {
    final aliases = _conversationCacheAliases(
      conversation,
      displayThreadId: displayThreadId,
    );
    final messages = <ChatMessage>[];
    final messageIds = <String>{};
    final sourceThreadIds = <String>{};
    for (final alias in aliases) {
      if (alias == displayThreadId) {
        continue;
      }
      final aliasThread = state[alias];
      if (aliasThread == null || !_hasRenderableMessages(aliasThread)) {
        continue;
      }
      sourceThreadIds.add(alias);
      for (final message in aliasThread.messages) {
        if (!message.hasRenderableContent) {
          continue;
        }
        final displayMessage = _withThreadId(message, displayThreadId);
        final messageId = _stableMessageId(displayMessage);
        if (messageId.isNotEmpty && !messageIds.add(messageId)) {
          continue;
        }
        messages.add(displayMessage);
      }
    }
    if (messages.isEmpty) {
      return 0;
    }
    _mergeMessages(displayThreadId, messages, isLoading: false);
    AwikiPerformanceLogger.log(
      'chat.open.alias_prewarm',
      fields: <String, Object?>{
        ...AwikiPerformanceLogger.threadField(displayThreadId),
        'source_count': sourceThreadIds.length,
        'messages': messages.length,
      },
      level: AwikiPerformanceLogLevel.verbose,
    );
    return messages.length;
  }

  List<String> _conversationCacheAliases(
    ConversationSummary conversation, {
    required String displayThreadId,
  }) {
    final aliases = <String>{};
    void add(String? value) {
      final key = value?.trim();
      if (key != null && key.isNotEmpty) {
        aliases.add(key);
      }
    }

    add(displayThreadId);
    add(conversation.threadId);
    for (final key in conversation.visibilityKeys) {
      add(key);
    }
    for (final key in conversationVisibilityIdentity(
      conversation,
      includeHandleAliasesForStrongIdentity: true,
    ).keys) {
      add(key);
    }
    final canonicalKey =
        _cacheMetadataByThreadId[displayThreadId]?.canonicalKey ??
        _canonicalKeyForConversation(conversation);
    for (final key in _canonicalAliases[canonicalKey] ?? const <String>{}) {
      add(key);
    }
    var expanded = true;
    while (expanded) {
      expanded = false;
      for (final alias in List<String>.from(aliases)) {
        final metadata = _cacheMetadataByThreadId[alias];
        if (metadata != null) {
          for (final key
              in _canonicalAliases[metadata.canonicalKey] ?? const <String>{}) {
            final before = aliases.length;
            add(key);
            expanded = expanded || aliases.length != before;
          }
        }
        for (final key in _cacheAliasesByThreadId[alias] ?? const <String>{}) {
          final before = aliases.length;
          add(key);
          expanded = expanded || aliases.length != before;
        }
      }
    }
    return aliases.toList();
  }

  bool _hasRenderableMessages(ChatThreadState current) {
    return current.messages.any((message) => message.hasRenderableContent);
  }

  void _logOpenFirstPaintSource(
    String threadId, {
    required String source,
    required int items,
  }) {
    AwikiPerformanceLogger.log(
      'chat.open.first_paint',
      fields: <String, Object?>{
        ...AwikiPerformanceLogger.threadField(threadId),
        'source': source,
        'items': items,
      },
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
      _updateConversationPreviewFromMessages(conversation, messages);
      await ref.read(conversationListProvider.notifier).refreshFastLocal();
    } catch (_) {
      AwikiPerformanceLogger.log(
        'chat.thread_after.failed',
        fields: AwikiPerformanceLogger.threadField(displayThreadId),
      );
    }
  }

  void acknowledgeVisibleConversationRead(
    ConversationSummary conversation, {
    String? displayThreadId,
    String reason = 'visible',
    bool requireVisible = true,
  }) {
    if (conversation.unreadCount <= 0 && conversation.unreadMentionCount <= 0) {
      return;
    }
    final targetThreadId = _displayThreadIdFor(conversation, displayThreadId);
    final metadata = _cacheMetadataByThreadId[targetThreadId];
    if (requireVisible && metadata?.isVisible != true) {
      return;
    }
    final readToken = _readReceiptToken(conversation);
    if (_completedReadReceipts.contains(readToken) ||
        _activeReadReceipts.contains(readToken)) {
      ref
          .read(conversationListProvider.notifier)
          .markConversationReadLocal(conversation);
      return;
    }
    final localClearWatch = Stopwatch()..start();
    ref
        .read(conversationListProvider.notifier)
        .markConversationReadLocal(conversation);
    localClearWatch.stop();
    AwikiPerformanceLogger.log(
      'chat.mark_read.local_clear',
      elapsed: localClearWatch.elapsed,
      fields: <String, Object?>{
        ...AwikiPerformanceLogger.threadField(conversation.threadId),
        'reason': reason,
      },
      level: AwikiPerformanceLogLevel.verbose,
    );
    _markConversationReadBestEffort(conversation, readToken: readToken);
  }

  Future<int?> _repairThreadFromLocalProjection(
    ConversationSummary conversation, {
    required String displayThreadId,
    AppThreadRef? threadRef,
  }) async {
    final messaging = ref.read(messagingServiceProvider);
    final effectiveThreadRef =
        threadRef ??
        _threadPatchSubscriptions[displayThreadId]?.threadRef ??
        _localHistoryThreadRefFor(conversation);
    if (messaging is ThreadPatchMessagingService) {
      final threadPatchMessaging = messaging as ThreadPatchMessagingService;
      try {
        final patch = await threadPatchMessaging.repairThreadStore(
          effectiveThreadRef,
        );
        if (!mounted) {
          return null;
        }
        final ownerDid = ref.read(sessionProvider).session?.did.trim();
        final patchOwnerDid = patch.ownerDid.trim();
        if ((ownerDid == null ||
                ownerDid.isEmpty ||
                patchOwnerDid == ownerDid) &&
            _threadPatchMatchesThreadRef(patch, effectiveThreadRef)) {
          _recordThreadPatchRepairVersion(displayThreadId, patch);
          await _applyThreadPatchBody(displayThreadId, patch, conversation);
          return patch.version;
        }
      } catch (_) {
        // Fall through to local history. Patch stream repair must never
        // escalate to remote full history from an upper-layer summary update.
      }
    }
    await _loadLocalHistory(
      conversation,
      intoThreadId: displayThreadId,
      limit: _initialLocalHistoryLimit,
    );
    return null;
  }

  void _recordThreadPatchRepairVersion(
    String displayThreadId,
    ThreadMessagePatch patch,
  ) {
    final subscription = _threadPatchSubscriptions[displayThreadId];
    if (subscription == null ||
        !_threadPatchMatchesSubscription(patch, subscription) ||
        patch.version <= subscription.lastVersion) {
      return;
    }
    _threadPatchSubscriptions[displayThreadId] = subscription.copyWith(
      lastVersion: patch.version,
    );
  }

  void _ensureThreadPatchSubscription(
    ConversationSummary conversation, {
    required String displayThreadId,
    int initialLastVersion = 0,
  }) {
    _cancelThreadPatchSubscriptionTtl(displayThreadId);
    final messaging = ref.read(messagingServiceProvider);
    if (messaging is! ThreadPatchMessagingService) {
      return;
    }
    final threadPatchMessaging = messaging as ThreadPatchMessagingService;
    final session = ref.read(sessionProvider).session;
    final ownerDid = session?.did.trim();
    if (ownerDid == null || ownerDid.isEmpty) {
      return;
    }
    final threadRef = _localHistoryThreadRefFor(conversation);
    final expectedPatchKey = _threadPatchKeyFor(threadRef);
    final existing = _threadPatchSubscriptions[displayThreadId];
    if (existing != null &&
        existing.ownerDid == ownerDid &&
        existing.threadRefKey == threadRef.stableId &&
        existing.threadKind == expectedPatchKey.kind &&
        existing.threadId == expectedPatchKey.id) {
      return;
    }
    unawaited(existing?.subscription.cancel());
    final token = ++_threadPatchToken;
    late final StreamSubscription<ThreadMessagePatch> subscription;
    subscription = threadPatchMessaging
        .watchThreadPatches(threadRef)
        .listen(
          (patch) => _applyThreadPatch(
            displayThreadId,
            patch,
            token: token,
            ownerDid: ownerDid,
            conversation: conversation,
          ),
          onError: (_) {
            unawaited(
              _handleThreadPatchStreamEnded(
                displayThreadId,
                conversation: conversation,
                token: token,
              ),
            );
          },
          onDone: () {
            unawaited(
              _handleThreadPatchStreamEnded(
                displayThreadId,
                conversation: conversation,
                token: token,
              ),
            );
          },
        );
    _threadPatchSubscriptions[displayThreadId] = _ThreadPatchSubscription(
      token: token,
      ownerDid: ownerDid,
      threadRef: threadRef,
      threadKind: expectedPatchKey.kind,
      threadId: expectedPatchKey.id,
      subscription: subscription,
      lastVersion: initialLastVersion,
    );
  }

  Future<void> _handleThreadPatchStreamEnded(
    String displayThreadId, {
    required ConversationSummary conversation,
    required int token,
  }) async {
    if (!mounted) {
      return;
    }
    final subscription = _threadPatchSubscriptions[displayThreadId];
    if (subscription == null || subscription.token != token) {
      return;
    }
    _threadPatchSubscriptions.remove(displayThreadId);
    unawaited(subscription.subscription.cancel());
    final now = DateTime.now();
    final previousEndAt = _lastThreadPatchStreamEndAt[displayThreadId];
    _lastThreadPatchStreamEndAt[displayThreadId] = now;
    if (previousEndAt != null &&
        now.difference(previousEndAt) < _threadPatchStreamResubscribeCooldown) {
      return;
    }
    final repairedVersion = await _repairThreadFromLocalProjection(
      conversation,
      displayThreadId: displayThreadId,
      threadRef: subscription.threadRef,
    );
    if (!mounted ||
        _cacheMetadataByThreadId[displayThreadId]?.isVisible != true) {
      return;
    }
    _ensureThreadPatchSubscription(
      conversation,
      displayThreadId: displayThreadId,
      initialLastVersion: repairedVersion ?? subscription.lastVersion,
    );
  }

  Future<void> _applyThreadPatch(
    String displayThreadId,
    ThreadMessagePatch patch, {
    required int token,
    required String ownerDid,
    required ConversationSummary conversation,
  }) async {
    if (!mounted) {
      return;
    }
    final currentSubscription = _threadPatchSubscriptions[displayThreadId];
    if (currentSubscription == null ||
        currentSubscription.token != token ||
        currentSubscription.ownerDid != ownerDid) {
      return;
    }
    if (patch.ownerDid.trim() != ownerDid) {
      return;
    }
    if (!_threadPatchMatchesSubscription(patch, currentSubscription)) {
      return;
    }
    if (patch.version <= currentSubscription.lastVersion) {
      return;
    }
    if (patch.version > currentSubscription.lastVersion + 1 &&
        currentSubscription.lastVersion != 0) {
      await _repairThreadPatchSubscription(
        displayThreadId,
        conversation: conversation,
        token: token,
      );
      return;
    }
    _threadPatchSubscriptions[displayThreadId] = currentSubscription.copyWith(
      lastVersion: patch.version,
    );
    await _applyThreadPatchBody(displayThreadId, patch, conversation);
  }

  Future<void> _applyThreadPatchBody(
    String displayThreadId,
    ThreadMessagePatch patch,
    ConversationSummary conversation,
  ) async {
    switch (patch.kind) {
      case ThreadMessagePatchKind.reset:
        final messages = patch.messages
            .map((message) => _withThreadId(message, displayThreadId))
            .toList();
        _mergeMessages(displayThreadId, messages, isLoading: false);
        _updateConversationPreviewFromMessages(conversation, messages);
      case ThreadMessagePatchKind.upsert:
        final message = patch.message;
        if (message == null) {
          return;
        }
        final messages = <ChatMessage>[_withThreadId(message, displayThreadId)];
        _mergeMessages(displayThreadId, messages, isLoading: false);
        _updateConversationPreviewFromMessages(conversation, messages);
      case ThreadMessagePatchKind.remove:
        final messageId = patch.messageId?.trim();
        if (messageId == null || messageId.isEmpty) {
          return;
        }
        _removeMessageById(displayThreadId, messageId);
      case ThreadMessagePatchKind.repairRequired:
        final token = _threadPatchSubscriptions[displayThreadId]?.token;
        if (token == null) {
          return;
        }
        await _repairThreadPatchSubscription(
          displayThreadId,
          conversation: conversation,
          token: token,
        );
    }
  }

  Future<void> _repairThreadPatchSubscription(
    String displayThreadId, {
    required ConversationSummary conversation,
    required int token,
  }) async {
    if (!mounted) {
      return;
    }
    final messaging = ref.read(messagingServiceProvider);
    final currentSubscription = _threadPatchSubscriptions[displayThreadId];
    if (currentSubscription == null ||
        currentSubscription.token != token ||
        messaging is! ThreadPatchMessagingService) {
      return;
    }
    final threadPatchMessaging = messaging as ThreadPatchMessagingService;
    try {
      final patch = await threadPatchMessaging.repairThreadStore(
        currentSubscription.threadRef,
      );
      if (!mounted ||
          _threadPatchSubscriptions[displayThreadId]?.token != token) {
        return;
      }
      if (patch.ownerDid.trim() != currentSubscription.ownerDid ||
          !_threadPatchMatchesSubscription(patch, currentSubscription)) {
        await _loadLocalHistory(conversation, intoThreadId: displayThreadId);
        return;
      }
      _threadPatchSubscriptions[displayThreadId] = currentSubscription.copyWith(
        lastVersion: patch.version,
      );
      await _applyThreadPatchBody(displayThreadId, patch, conversation);
    } catch (_) {
      await _loadLocalHistory(conversation, intoThreadId: displayThreadId);
    }
  }

  void _markConversationReadBestEffort(
    ConversationSummary conversation, {
    required String readToken,
  }) {
    try {
      final thread = _readThreadRefFor(conversation);
      final watch = Stopwatch()..start();
      _activeReadReceipts.add(readToken);
      final operation = ref
          .read(conversationServiceProvider)
          .markThreadRead(thread)
          .then<void>((_) {
            watch.stop();
            _activeReadReceipts.remove(readToken);
            _completedReadReceipts.add(readToken);
            AwikiPerformanceLogger.log(
              'chat.mark_read',
              elapsed: watch.elapsed,
              fields: AwikiPerformanceLogger.threadField(conversation.threadId),
            );
          })
          .catchError((_) {
            _activeReadReceipts.remove(readToken);
          });
      unawaited(operation);
    } catch (_) {
      // Thread-level mark-read is best effort. Opening a conversation must
      // still clear unread locally and continue rendering messages.
    }
  }

  Future<_HistoryLoadResult> _loadLocalHistory(
    ConversationSummary conversation, {
    String? intoThreadId,
    int limit = 100,
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
          limit: limit,
        ),
        fields: <String, Object?>{
          ...AwikiPerformanceLogger.threadField(targetThreadId),
          'limit': limit,
        },
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
      _updateConversationPreviewFromMessages(conversation, history);
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
      _updateConversationPreviewFromMessages(conversation, history);
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
      final sentConversation = _withConversationPreview(
        conversation,
        sentInThread,
      );
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(sentConversation);
    } catch (_) {
      final failed = pending.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(targetThreadId, pending.localId, failed);
      final failedConversation = _withConversationPreview(conversation, failed);
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(failedConversation);
    }
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
      final sentConversation = _withConversationPreview(
        conversation,
        sentInThread,
      );
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(sentConversation);
    } catch (_) {
      final failed = pending.copyWith(sendState: MessageSendState.failed);
      _replaceMessage(targetThreadId, pending.localId, failed);
      final failedConversation = _withConversationPreview(conversation, failed);
      ref
          .read(conversationListProvider.notifier)
          .upsertConversation(failedConversation);
    }
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
    _cancelThreadPatchSubscriptionTtl(threadId);
    _removeThreadCacheMetadata(threadId);
    state = next;
    await ref.read(conversationListProvider.notifier).refresh();
  }

  void applyRealtimeUpdate(
    ChatMessage message, {
    ConversationSummary? conversation,
  }) {
    final targetThreadIds = _threadIdsForRealtimeMessage(message, conversation);
    for (final targetThreadId in targetThreadIds) {
      _mergeMessages(targetThreadId, <ChatMessage>[
        _withThreadId(message, targetThreadId),
      ], trustIncomingAgentReply: true);
    }
  }

  void _updateConversationPreviewFromMessages(
    ConversationSummary conversation,
    List<ChatMessage> messages,
  ) {
    final latest = _latestRenderableMessage(messages);
    if (latest == null) {
      return;
    }
    final current = _refreshedConversationFor(conversation);
    ref
        .read(conversationListProvider.notifier)
        .upsertConversation(_withConversationPreview(current, latest));
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
    final shouldLoad = _shouldLoadHistory(current, conversation);
    if (current.isLoading ||
        _activeRemoteHistorySyncs.contains(targetThreadId)) {
      if (force || shouldLoad) {
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
    if (!force && !shouldLoad) {
      return Future<void>.value();
    }
    return _loadHistory(
      conversation,
      intoThreadId: targetThreadId,
      reportFailure: reportFailure,
      showLoading: showLoading,
    );
  }

  void clear() {
    _cancelAgentProcessingTimers();
    _cancelThreadPatchSubscriptions();
    _cancelThreadPatchSubscriptionTtls();
    _cancelHiddenThreadCacheTrimTimers();
    _pendingHistorySyncs.clear();
    _lastThreadPatchStreamEndAt.clear();
    _activeReadReceipts.clear();
    _completedReadReceipts.clear();
    _activeLocalHistoryLoads.clear();
    _activeRemoteHistorySyncs.clear();
    _clearMemoryCacheMetadata();
    state = const <String, ChatThreadState>{};
  }

  void markConversationVisible(
    ConversationSummary conversation, {
    String? displayThreadId,
  }) {
    final threadId = _displayThreadIdFor(conversation, displayThreadId);
    _cancelHiddenThreadCacheTrim(threadId);
    _touchConversationCache(conversation, threadId, visible: true);
    _cancelThreadPatchSubscriptionTtl(threadId);
    _ensureThreadPatchSubscription(conversation, displayThreadId: threadId);
  }

  void markConversationHidden(
    ConversationSummary conversation, {
    String? displayThreadId,
  }) {
    final threadId = _displayThreadIdFor(conversation, displayThreadId);
    final metadata = _cacheMetadataByThreadId[threadId];
    if (metadata != null) {
      _cacheMetadataByThreadId[threadId] = metadata.copyWith(
        isVisible: false,
        hiddenAt: DateTime.now(),
      );
    } else {
      _touchConversationCache(conversation, threadId, visible: false);
    }
    _scheduleThreadPatchSubscriptionTtl(threadId);
    _scheduleHiddenThreadCacheTrim(threadId);
  }

  void trimForAppBackground() {
    _trimInactiveThreads(
      hiddenLimit: _cachePolicy.coldThreadMessageLimit,
      evictUnprotectedHidden: false,
    );
  }

  void trimForMemoryPressure() {
    _trimInactiveThreads(hiddenLimit: 1, evictUnprotectedHidden: true);
  }

  ChatThreadCacheStats debugCacheStats() => _cacheStats();

  String? debugThreadIdForSourceMessage(String? messageId) {
    return _threadIdForSourceMessage(messageId);
  }

  void debugDropMessagesForTesting(String threadId) {
    final current = state[threadId];
    if (current == null) {
      return;
    }
    _touchThreadCache(threadId, current.messages);
    state = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(messages: const <ChatMessage>[]),
    };
  }

  ChatThreadCacheStats _cacheStats() {
    final canonicalKeys = <String>{
      for (final threadId in state.keys) _canonicalKeyForThreadId(threadId),
    };
    return ChatThreadCacheStats(
      rawThreadStateCount: state.length,
      canonicalThreadCount: canonicalKeys.length,
      totalRetainedMessages: state.values.fold<int>(
        0,
        (total, thread) => total + thread.messages.length,
      ),
      activePatchSubscriptionCount: _threadPatchSubscriptions.length,
      messageRouteEntryCount: _messageThreadRoutes.length,
      trimmedMessageCount: _trimmedMessageCount,
      evictedThreadCount: _evictedThreadCount,
      protectedOverflowCount: _protectedOverflowCount,
    );
  }

  void _touchConversationCache(
    ConversationSummary conversation,
    String threadId, {
    bool? visible,
  }) {
    final aliases = <String>{
      threadId,
      conversation.threadId,
      for (final key in conversation.visibilityKeys) key,
      for (final key in conversationVisibilityIdentity(
        conversation,
        includeHandleAliasesForStrongIdentity: true,
      ).keys)
        key,
    };
    _touchThreadCache(
      threadId,
      const <ChatMessage>[],
      canonicalKey: _canonicalKeyForConversation(conversation),
      aliases: aliases,
      visible: visible,
    );
  }

  void _touchThreadCache(
    String threadId,
    List<ChatMessage> messages, {
    String? canonicalKey,
    Iterable<String> aliases = const <String>[],
    bool? visible,
  }) {
    final now = DateTime.now();
    final existingMetadata = _cacheMetadataByThreadId[threadId];
    final canonical =
        _normalizedCacheKey(canonicalKey) ??
        _canonicalKeyForMessages(threadId, messages) ??
        existingMetadata?.canonicalKey ??
        threadId;
    final previous = existingMetadata?.canonicalKey;
    if (previous != null && previous != canonical) {
      final previousAliases = _canonicalAliases[previous];
      for (final alias
          in _cacheAliasesByThreadId[threadId] ?? <String>{threadId}) {
        previousAliases?.remove(alias);
      }
      if (previousAliases != null && previousAliases.isEmpty) {
        _canonicalAliases.remove(previous);
      }
    }
    final threadAliases = <String>{threadId};
    if (previous == canonical) {
      threadAliases.addAll(
        _cacheAliasesByThreadId[threadId] ?? const <String>{},
      );
    }
    for (final alias in aliases) {
      final key = alias.trim();
      if (key.isNotEmpty) {
        threadAliases.add(key);
      }
    }
    _cacheAliasesByThreadId[threadId] = threadAliases;
    final isVisible = visible ?? existingMetadata?.isVisible ?? false;
    _cacheMetadataByThreadId[threadId] = _ThreadCacheMetadata(
      canonicalKey: canonical,
      lastTouchedAt: now,
      isVisible: isVisible,
      hiddenAt: isVisible ? null : existingMetadata?.hiddenAt,
    );
    final aliasSet = _canonicalAliases.putIfAbsent(canonical, () => <String>{});
    aliasSet.addAll(threadAliases);
  }

  String? _canonicalKeyForConversation(ConversationSummary conversation) {
    if (conversation.isGroup) {
      final group = conversation.groupId?.trim();
      if (group != null && group.isNotEmpty) {
        return canonicalGroupThreadId(group);
      }
    } else {
      final peerDid = conversation.targetDid?.trim();
      if (peerDid != null && peerDid.isNotEmpty) {
        return canonicalDirectThreadId(_ownerDidForCache(), peerDid);
      }
      final peer = normalizedDirectPeer(conversation.targetPeer);
      if (peer != null && peer.startsWith('did:')) {
        return canonicalDirectThreadId(_ownerDidForCache(), peer);
      }
    }
    return conversationVisibilityIdentity(
      conversation,
      includeHandleAliasesForStrongIdentity: true,
    ).primaryKey;
  }

  String? _canonicalKeyForMessages(
    String threadId,
    List<ChatMessage> messages,
  ) {
    for (final message in messages.reversed) {
      final group = message.groupId?.trim();
      if (group != null && group.isNotEmpty) {
        return canonicalGroupThreadId(group);
      }
    }
    final peerDid = directPeerDidFromMessages(messages)?.trim();
    if (peerDid != null && peerDid.isNotEmpty) {
      return canonicalDirectThreadId(_ownerDidForCache(), peerDid);
    }
    final normalizedThread = threadId.trim();
    return normalizedThread.isEmpty ? null : normalizedThread;
  }

  String _ownerDidForCache() {
    return ref.read(sessionProvider).session?.did.trim() ?? '';
  }

  String? _normalizedCacheKey(String? value) {
    final key = value?.trim();
    return key == null || key.isEmpty ? null : key;
  }

  void _recordMessageRoutes(String threadId, List<ChatMessage> messages) {
    if (messages.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final canonicalKey =
        _cacheMetadataByThreadId[threadId]?.canonicalKey ??
        _canonicalKeyForMessages(threadId, messages) ??
        threadId;
    for (final message in messages) {
      for (final id in <String>[message.localId, ?message.remoteId]) {
        final key = id.trim();
        if (key.isEmpty) {
          continue;
        }
        final existing = _messageThreadRoutes[key];
        if (existing != null && state.containsKey(existing.threadId)) {
          _messageThreadRoutes[key] = _MessageThreadRoute(
            threadId: existing.threadId,
            canonicalKey: existing.canonicalKey,
            lastTouchedAt: now,
          );
          continue;
        }
        _messageThreadRoutes[key] = _MessageThreadRoute(
          threadId: threadId,
          canonicalKey: canonicalKey,
          lastTouchedAt: now,
        );
      }
    }
  }

  void _cleanupMessageRoutes() {
    final maxEntries = _cachePolicy.maxMessageRouteEntries;
    if (maxEntries <= 0) {
      _messageThreadRoutes.clear();
      return;
    }
    final now = DateTime.now();
    final ttl = _cachePolicy.messageRouteTtl;
    _messageThreadRoutes.removeWhere((_, route) {
      return ttl > Duration.zero && now.difference(route.lastTouchedAt) > ttl;
    });
    if (_messageThreadRoutes.length <= maxEntries) {
      return;
    }
    final entries = _messageThreadRoutes.entries.toList()
      ..sort((a, b) => a.value.lastTouchedAt.compareTo(b.value.lastTouchedAt));
    final removeCount = _messageThreadRoutes.length - maxEntries;
    for (final entry in entries.take(removeCount)) {
      _messageThreadRoutes.remove(entry.key);
    }
  }

  void _removeMessageRoutesForIds(Set<String> messageIds) {
    if (messageIds.isEmpty) {
      return;
    }
    _messageThreadRoutes.removeWhere((id, _) => messageIds.contains(id));
  }

  void _removeThreadCacheMetadata(String threadId) {
    _cancelHiddenThreadCacheTrim(threadId);
    _cancelThreadPatchSubscriptionTtl(threadId);
    final metadata = _cacheMetadataByThreadId.remove(threadId);
    final threadAliases =
        _cacheAliasesByThreadId.remove(threadId) ?? <String>{threadId};
    final canonicalKey = metadata?.canonicalKey;
    if (canonicalKey != null) {
      final aliases = _canonicalAliases[canonicalKey];
      for (final alias in threadAliases) {
        aliases?.remove(alias);
      }
      if (aliases != null && aliases.isEmpty) {
        _canonicalAliases.remove(canonicalKey);
      }
    }
    _messageThreadRoutes.removeWhere((_, route) => route.threadId == threadId);
  }

  void _clearMemoryCacheMetadata() {
    _cancelHiddenThreadCacheTrimTimers();
    _cacheMetadataByThreadId.clear();
    _cacheAliasesByThreadId.clear();
    _canonicalAliases.clear();
    _messageThreadRoutes.clear();
    _trimmedMessageCount = 0;
    _evictedThreadCount = 0;
    _protectedOverflowCount = 0;
  }

  _ThreadCacheEnforcementResult _enforceThreadMessageCache(
    String threadId,
    ChatThreadState thread,
    List<ChatMessage> sortedMessages, {
    int? overrideLimit,
  }) {
    final limit = overrideLimit ?? _messageLimitForThread(threadId);
    if (limit <= 0 || sortedMessages.length <= limit) {
      return _ThreadCacheEnforcementResult(
        messages: sortedMessages,
        trimmedCount: 0,
        protectedOverflow: 0,
      );
    }
    final protectedIds = _protectedMessageIds(threadId, thread, sortedMessages);
    final retained = <ChatMessage>[];
    final retainedIds = <String>{};
    for (final message in sortedMessages.reversed) {
      if (retained.length >= limit) {
        break;
      }
      retained.add(message);
      retainedIds.add(_stableMessageId(message));
    }
    for (final message in sortedMessages) {
      final stableId = _stableMessageId(message);
      if (!protectedIds.contains(stableId) || retainedIds.contains(stableId)) {
        continue;
      }
      retained.add(message);
      retainedIds.add(stableId);
    }
    final trimmedCount = sortedMessages.length - retained.length;
    final protectedOverflow = retained.length > limit
        ? retained.length - limit
        : 0;
    if (trimmedCount <= 0 && protectedOverflow <= 0) {
      return _ThreadCacheEnforcementResult(
        messages: sortedMessages,
        trimmedCount: 0,
        protectedOverflow: protectedOverflow,
      );
    }
    _trimmedMessageCount += trimmedCount > 0 ? trimmedCount : 0;
    _protectedOverflowCount += protectedOverflow;
    final sortedRetained = _sortMessages(retained);
    AwikiPerformanceLogger.log(
      protectedOverflow > 0
          ? 'chat.cache.protected_overflow'
          : 'chat.cache.trim_thread',
      fields: <String, Object?>{
        ...AwikiPerformanceLogger.threadField(threadId),
        'before': sortedMessages.length,
        'after': sortedRetained.length,
        'limit': limit,
        'trimmed': trimmedCount,
        'protected_overflow': protectedOverflow,
      },
      minMs: 1,
    );
    return _ThreadCacheEnforcementResult(
      messages: sortedRetained,
      trimmedCount: trimmedCount > 0 ? trimmedCount : 0,
      protectedOverflow: protectedOverflow,
    );
  }

  Map<String, ChatThreadState> _enforceGlobalCachePolicy(
    Map<String, ChatThreadState> candidate,
  ) {
    if (candidate.isEmpty) {
      return candidate;
    }
    final maxTotal = _cachePolicy.maxTotalCachedMessages;
    final maxCanonical = _cachePolicy.maxCachedCanonicalThreads;
    if (maxTotal <= 0 && maxCanonical <= 0) {
      return candidate;
    }
    var changed = false;
    var nextState = Map<String, ChatThreadState>.from(candidate);
    final canonicalKeys = <String>{
      for (final threadId in nextState.keys) _canonicalKeyForThreadId(threadId),
    };
    if (maxCanonical > 0 && canonicalKeys.length > maxCanonical) {
      final coldThreadIds = nextState.keys.toList()
        ..sort((a, b) => _lastTouchedAt(a).compareTo(_lastTouchedAt(b)));
      final retainedCanonical = <String>{
        for (final entry in coldThreadIds.reversed.take(maxCanonical))
          _canonicalKeyForThreadId(entry),
      };
      for (final threadId in coldThreadIds) {
        if (retainedCanonical.contains(_canonicalKeyForThreadId(threadId))) {
          continue;
        }
        final thread = nextState[threadId];
        if (thread == null) {
          continue;
        }
        if (_threadHasHardProtectedMessages(thread, thread.messages)) {
          final enforced = _enforceThreadMessageCache(
            threadId,
            thread,
            thread.messages,
            overrideLimit: _cachePolicy.coldThreadMessageLimit,
          );
          if (enforced.messages.length != thread.messages.length) {
            changed = true;
            nextState[threadId] = thread.copyWith(messages: enforced.messages);
          }
          continue;
        }
        _evictThreadFromCacheCandidate(nextState, threadId, thread);
        changed = true;
      }
      final canonicalAfterEvict = <String>{
        for (final threadId in nextState.keys)
          _canonicalKeyForThreadId(threadId),
      };
      if (canonicalAfterEvict.length > maxCanonical) {
        _protectedOverflowCount += canonicalAfterEvict.length - maxCanonical;
      }
    }
    var total = _totalRetainedMessages(nextState);
    if (maxTotal > 0 && total > maxTotal) {
      var madeProgress = true;
      while (total > maxTotal && madeProgress) {
        madeProgress = false;
        final threadIds = nextState.keys.toList()
          ..sort((a, b) => _lastTouchedAt(a).compareTo(_lastTouchedAt(b)));
        for (final threadId in threadIds) {
          if (total <= maxTotal) {
            break;
          }
          final thread = nextState[threadId];
          if (thread == null || thread.messages.length <= 1) {
            continue;
          }
          final targetLimit = _globalQuotaTargetLimit(thread.messages.length);
          final enforced = _enforceThreadMessageCache(
            threadId,
            thread,
            thread.messages,
            overrideLimit: targetLimit,
          );
          if (enforced.messages.length == thread.messages.length) {
            continue;
          }
          changed = true;
          madeProgress = true;
          nextState[threadId] = thread.copyWith(messages: enforced.messages);
          total = _totalRetainedMessages(nextState);
        }
        if (!madeProgress) {
          final evicted = _evictOldestUnprotectedThread(nextState);
          if (evicted) {
            changed = true;
            madeProgress = true;
            total = _totalRetainedMessages(nextState);
            continue;
          }
          _protectedOverflowCount += total - maxTotal;
          break;
        }
      }
    }
    if (changed) {
      AwikiPerformanceLogger.log(
        'chat.cache.enforce',
        fields: <String, Object?>{
          'raw_threads': nextState.length,
          'canonical_threads': <String>{
            for (final threadId in nextState.keys)
              _canonicalKeyForThreadId(threadId),
          }.length,
          'total_retained_messages': _totalRetainedMessages(nextState),
          'trimmed_total': _trimmedMessageCount,
          'protected_overflow_total': _protectedOverflowCount,
        },
        minMs: 1,
      );
    }
    return nextState;
  }

  int _globalQuotaTargetLimit(int currentLength) {
    final coldLimit = _cachePolicy.coldThreadMessageLimit;
    if (coldLimit > 0 && currentLength > coldLimit + 1) {
      return coldLimit;
    }
    return currentLength - 1;
  }

  int _totalRetainedMessages(Map<String, ChatThreadState> threads) {
    return threads.values.fold<int>(
      0,
      (total, thread) => total + thread.messages.length,
    );
  }

  int _messageLimitForThread(String threadId) {
    final metadata = _cacheMetadataByThreadId[threadId];
    if (metadata?.isVisible == true) {
      return _cachePolicy.hotThreadMessageLimit;
    }
    final hiddenAt = metadata?.hiddenAt;
    if (hiddenAt != null &&
        DateTime.now().difference(hiddenAt) > const Duration(minutes: 30)) {
      return _cachePolicy.coldThreadMessageLimit;
    }
    final touchedAt = _lastTouchedAt(threadId);
    final age = DateTime.now().difference(touchedAt);
    if (age <= const Duration(minutes: 30)) {
      return _cachePolicy.warmThreadMessageLimit;
    }
    return _cachePolicy.coldThreadMessageLimit;
  }

  void _trimInactiveThreads({
    required int hiddenLimit,
    required bool evictUnprotectedHidden,
  }) {
    if (state.isEmpty) {
      return;
    }
    var nextState = Map<String, ChatThreadState>.from(state);
    var changed = false;
    for (final entry in state.entries) {
      final metadata = _cacheMetadataByThreadId[entry.key];
      if (metadata?.isVisible == true) {
        continue;
      }
      if (evictUnprotectedHidden &&
          !_threadHasHardProtectedMessages(entry.value, entry.value.messages)) {
        _evictThreadFromCacheCandidate(nextState, entry.key, entry.value);
        changed = true;
        continue;
      }
      final enforced = _enforceThreadMessageCache(
        entry.key,
        entry.value,
        entry.value.messages,
        overrideLimit: hiddenLimit,
      );
      if (enforced.messages.length != entry.value.messages.length) {
        changed = true;
        nextState[entry.key] = entry.value.copyWith(
          messages: enforced.messages,
        );
      }
      _scheduleThreadPatchSubscriptionTtl(
        entry.key,
        immediate: evictUnprotectedHidden,
      );
    }
    nextState = _enforceGlobalCachePolicy(nextState);
    if (changed || !identical(nextState, state)) {
      state = nextState;
    }
  }

  void _enforceThreadCacheForExistingState(String threadId) {
    final current = state[threadId];
    if (current == null) {
      return;
    }
    final enforced = _enforceThreadMessageCache(
      threadId,
      current,
      current.messages,
    );
    if (enforced.messages.length == current.messages.length) {
      return;
    }
    state = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(messages: enforced.messages),
    };
  }

  DateTime _lastTouchedAt(String threadId) {
    return _cacheMetadataByThreadId[threadId]?.lastTouchedAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _canonicalKeyForThreadId(String threadId) {
    return _cacheMetadataByThreadId[threadId]?.canonicalKey ?? threadId;
  }

  bool _evictOldestUnprotectedThread(Map<String, ChatThreadState> nextState) {
    final candidates =
        nextState.entries
            .where(
              (entry) => !_threadHasHardProtectedMessages(
                entry.value,
                entry.value.messages,
              ),
            )
            .toList()
          ..sort(
            (a, b) => _lastTouchedAt(a.key).compareTo(_lastTouchedAt(b.key)),
          );
    if (candidates.isEmpty) {
      return false;
    }
    final entry = candidates.first;
    _evictThreadFromCacheCandidate(nextState, entry.key, entry.value);
    return true;
  }

  void _evictThreadFromCacheCandidate(
    Map<String, ChatThreadState> nextState,
    String threadId,
    ChatThreadState thread,
  ) {
    nextState.remove(threadId);
    _evictedThreadCount += 1;
    _removeThreadCacheMetadata(threadId);
    AwikiPerformanceLogger.log(
      'chat.cache.evict_thread',
      fields: <String, Object?>{
        ...AwikiPerformanceLogger.threadField(threadId),
        'messages': thread.messages.length,
      },
      minMs: 1,
    );
  }

  Set<String> _protectedMessageIds(
    String threadId,
    ChatThreadState thread,
    List<ChatMessage> messages,
  ) {
    final ids = _hardProtectedMessageIds(thread, messages);
    if (messages.isNotEmpty) {
      ids.add(_stableMessageId(messages.last));
    }
    final routedIds = <String>{
      for (final id in ids)
        if (_messageThreadRoutes[id]?.threadId == threadId) id,
    };
    ids.addAll(routedIds);
    return ids;
  }

  bool _threadHasHardProtectedMessages(
    ChatThreadState thread,
    List<ChatMessage> messages,
  ) {
    return _hardProtectedMessageIds(thread, messages).isNotEmpty;
  }

  Set<String> _hardProtectedMessageIds(
    ChatThreadState thread,
    List<ChatMessage> messages,
  ) {
    final ids = <String>{};
    void add(String? value) {
      final key = value?.trim();
      if (key != null && key.isNotEmpty) {
        ids.add(key);
      }
    }

    for (final message in messages) {
      if (message.sendState == MessageSendState.sending ||
          message.sendState == MessageSendState.failed) {
        add(_stableMessageId(message));
      }
      for (final turn in thread.agentPendingTurns) {
        if (turn.isActive && turn.matchesMessage(message)) {
          add(_stableMessageId(message));
        }
      }
    }
    for (final turn in thread.agentPendingTurns) {
      if (!turn.isActive) {
        continue;
      }
      add(turn.localMessageId);
      add(turn.remoteMessageId);
    }
    for (final record in thread.messageAgentSyncs) {
      if (record.isTerminal) {
        continue;
      }
      add(record.messageId);
    }
    for (final record in thread.appActionRecords.values) {
      if (record.isTerminal) {
        continue;
      }
      add(record.request?.sourceMessageId);
    }
    return ids;
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
    _touchThreadCache(threadId, messages);
    _recordMessageRoutes(threadId, messages);
    _cleanupMessageRoutes();
    final sortedMessages = _sortMessages(messages);
    final enforcedMessages = _enforceThreadMessageCache(
      threadId,
      current.copyWith(messages: sortedMessages),
      sortedMessages,
    ).messages;
    final nextState = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(messages: enforcedMessages),
    };
    state = _enforceGlobalCachePolicy(nextState);
  }

  void _removeMessageById(String threadId, String messageId) {
    final current = thread(threadId);
    final removedRouteIds = <String>{};
    for (final message in current.messages) {
      if (message.localId == messageId || message.remoteId == messageId) {
        removedRouteIds.add(message.localId);
        final remoteId = message.remoteId?.trim();
        if (remoteId != null && remoteId.isNotEmpty) {
          removedRouteIds.add(remoteId);
        }
      }
    }
    final nextMessages = current.messages
        .where(
          (message) =>
              message.localId != messageId && message.remoteId != messageId,
        )
        .toList();
    if (nextMessages.length == current.messages.length) {
      return;
    }
    _removeMessageRoutesForIds(removedRouteIds);
    _touchThreadCache(threadId, nextMessages);
    final enforcedMessages = _enforceThreadMessageCache(
      threadId,
      current.copyWith(messages: nextMessages),
      nextMessages,
    ).messages;
    final nextState = <String, ChatThreadState>{
      ...state,
      threadId: current.copyWith(messages: enforcedMessages),
    };
    state = _enforceGlobalCachePolicy(nextState);
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
    _recordMessageRoutes(threadId, <ChatMessage>[replacement]);
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
    _touchThreadCache(threadId, incoming);
    _recordMessageRoutes(threadId, incoming);
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
    final enforced = _enforceThreadMessageCache(
      threadId,
      previous.copyWith(
        messages: sortedMessages,
        agentPendingTurns: nextAgentPendingTurns,
      ),
      sortedMessages,
    );
    final nextState = <String, ChatThreadState>{
      ...state,
      threadId: ChatThreadState(
        threadId: threadId,
        messages: enforced.messages,
        isLoading: isLoading ?? previous.isLoading,
        agentPendingTurns: nextAgentPendingTurns,
        messageAgentSyncs: previous.messageAgentSyncs,
        appActionRecords: previous.appActionRecords,
      ),
    };
    state = _enforceGlobalCachePolicy(nextState);
    totalWatch.stop();
    AwikiPerformanceLogger.log(
      'chat.messages.merge',
      elapsed: totalWatch.elapsed,
      fields: <String, Object?>{
        ...AwikiPerformanceLogger.threadField(threadId),
        'incoming': incoming.length,
        'new': newlyMergedMessages.length,
        'total': enforced.messages.length,
        'trimmed': enforced.trimmedCount,
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
    final route = _messageThreadRoutes[normalized];
    if (route != null) {
      if (state.containsKey(route.threadId)) {
        return route.threadId;
      }
      final aliases = _canonicalAliases[route.canonicalKey];
      if (aliases != null) {
        for (final alias in aliases) {
          if (state.containsKey(alias)) {
            return alias;
          }
        }
      }
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

  void _cancelThreadPatchSubscriptions() {
    for (final session in _threadPatchSubscriptions.values) {
      unawaited(session.subscription.cancel());
    }
    _threadPatchSubscriptions.clear();
  }

  void _scheduleThreadPatchSubscriptionTtl(
    String threadId, {
    bool immediate = false,
  }) {
    final subscription = _threadPatchSubscriptions[threadId];
    if (subscription == null) {
      return;
    }
    if (_cacheMetadataByThreadId[threadId]?.isVisible == true) {
      _cancelThreadPatchSubscriptionTtl(threadId);
      return;
    }
    final ttl = immediate ? Duration.zero : _cachePolicy.warmSubscriptionTtl;
    _cancelThreadPatchSubscriptionTtl(threadId);
    if (ttl <= Duration.zero) {
      _cancelThreadPatchSubscription(threadId);
      return;
    }
    _threadPatchSubscriptionTtlTimers[threadId] = Timer(ttl, () {
      if (!mounted || _cacheMetadataByThreadId[threadId]?.isVisible == true) {
        return;
      }
      _cancelThreadPatchSubscription(threadId);
    });
  }

  void _cancelThreadPatchSubscription(String threadId) {
    _cancelThreadPatchSubscriptionTtl(threadId);
    final subscription = _threadPatchSubscriptions.remove(threadId);
    if (subscription != null) {
      unawaited(subscription.subscription.cancel());
    }
  }

  void _cancelThreadPatchSubscriptionTtl(String threadId) {
    _threadPatchSubscriptionTtlTimers.remove(threadId)?.cancel();
  }

  void _cancelThreadPatchSubscriptionTtls() {
    for (final timer in _threadPatchSubscriptionTtlTimers.values) {
      timer.cancel();
    }
    _threadPatchSubscriptionTtlTimers.clear();
  }

  void _scheduleHiddenThreadCacheTrim(String threadId) {
    _cancelHiddenThreadCacheTrim(threadId);
    _hiddenThreadCacheTrimTimers[threadId] = Timer(Duration.zero, () {
      _hiddenThreadCacheTrimTimers.remove(threadId);
      if (!mounted || _cacheMetadataByThreadId[threadId]?.isVisible == true) {
        return;
      }
      _enforceThreadCacheForExistingState(threadId);
    });
  }

  void _cancelHiddenThreadCacheTrim(String threadId) {
    _hiddenThreadCacheTrimTimers.remove(threadId)?.cancel();
  }

  void _cancelHiddenThreadCacheTrimTimers() {
    for (final timer in _hiddenThreadCacheTrimTimers.values) {
      timer.cancel();
    }
    _hiddenThreadCacheTrimTimers.clear();
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
    _cancelThreadPatchSubscriptions();
    _cancelThreadPatchSubscriptionTtls();
    _cancelHiddenThreadCacheTrimTimers();
    _lastThreadPatchStreamEndAt.clear();
    _clearMemoryCacheMetadata();
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
    final renderableMessages = current.messages
        .where((message) => message.hasRenderableContent)
        .toList(growable: false);
    if (renderableMessages.isEmpty) {
      return true;
    }
    final latestLocalAt = renderableMessages
        .map((message) => message.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    // unreadCount means the list badge/read state is stale, not necessarily
    // that the message timeline is stale.  If the latest local message already
    // covers the summary timestamp, repeatedly reloading history only creates
    // a conversation-list -> history-sync feedback loop.
    return conversation.lastMessageAt.isAfter(latestLocalAt);
  }

  ChatMessage? _latestRenderableMessage(List<ChatMessage> messages) {
    ChatMessage? latest;
    for (final message in messages) {
      if (!message.hasRenderableContent) {
        continue;
      }
      if (latest == null ||
          message.createdAt.isAfter(latest.createdAt) ||
          (message.createdAt.isAtSameMomentAs(latest.createdAt) &&
              (message.serverSequence ?? -1) > (latest.serverSequence ?? -1))) {
        latest = message;
      }
    }
    return latest;
  }

  ConversationSummary _refreshedConversationFor(ConversationSummary fallback) {
    final refreshed = ref
        .read(conversationListProvider)
        .conversations
        .where((item) => sameConversationTarget(item, fallback));
    return refreshed.isEmpty ? fallback : refreshed.first;
  }

  List<String> _threadIdsForRealtimeMessage(
    ChatMessage message,
    ConversationSummary? conversation,
  ) {
    final aliases = <String>[];
    void add(String? value) {
      final key = value?.trim();
      if (key != null && key.isNotEmpty && !aliases.contains(key)) {
        aliases.add(key);
      }
    }

    if (conversation == null) {
      add(message.threadId);
      return aliases;
    }

    for (final entry in state.entries) {
      if (sameConversationTarget(
        _conversationIdentityForThread(entry.key, entry.value),
        conversation,
      )) {
        add(entry.key);
      }
    }
    add(conversation.threadId);
    add(message.threadId);
    for (final key in conversation.visibilityKeys) {
      add(key);
    }
    for (final key in conversationVisibilityIdentity(
      conversation,
      includeHandleAliasesForStrongIdentity: true,
    ).keys) {
      add(key);
    }

    final ownerDid = ref.read(sessionProvider).session?.did.trim() ?? '';
    if (conversation.isGroup) {
      _addRealtimeGroupAliases(
        add,
        conversation.groupId,
        message.groupId,
        conversation.threadId,
        message.threadId,
      );
    } else {
      _addRealtimeDirectAliases(add, conversation, message, ownerDid);
    }
    if (aliases.isEmpty) {
      add(message.threadId);
    }
    return aliases;
  }

  void _addRealtimeGroupAliases(
    void Function(String? value) add,
    String? conversationGroupId,
    String? messageGroupId,
    String conversationThreadId,
    String messageThreadId,
  ) {
    for (final value in <String?>[
      conversationGroupId,
      messageGroupId,
      conversationThreadId,
      messageThreadId,
    ]) {
      final group = value?.trim();
      if (group == null || group.isEmpty) {
        continue;
      }
      add(group);
      add(canonicalGroupThreadId(group));
    }
  }

  void _addRealtimeDirectAliases(
    void Function(String? value) add,
    ConversationSummary conversation,
    ChatMessage message,
    String ownerDid,
  ) {
    final peerDid = _directPeerDidForRealtimeMessage(message, ownerDid);
    final targetDid = conversation.targetDid?.trim();
    final normalizedTargetPeer = normalizedDirectPeer(conversation.targetPeer);
    final peerDids = <String?>[
      targetDid,
      normalizedTargetPeer != null && normalizedTargetPeer.startsWith('did:')
          ? normalizedTargetPeer
          : null,
      peerDid,
    ];
    for (final did in peerDids) {
      final peer = did?.trim();
      if (peer == null || peer.isEmpty) {
        continue;
      }
      add(peer);
      add('direct:$peer');
      add('direct-did:$peer');
      if (ownerDid.isNotEmpty) {
        add(canonicalDirectThreadId(ownerDid, peer));
      }
    }

    if (normalizedTargetPeer == null ||
        normalizedTargetPeer.startsWith('did:')) {
      return;
    }
    add(normalizedTargetPeer);
    add('direct:$normalizedTargetPeer');
    add('direct-handle:$normalizedTargetPeer');
    add('dm:pending:$normalizedTargetPeer');
    final localPart = _handleLocalPart(normalizedTargetPeer);
    add('direct:$localPart');
    add('direct-handle:$localPart');
  }

  String? _directPeerDidForRealtimeMessage(
    ChatMessage message,
    String ownerDid,
  ) {
    final owner = ownerDid.trim();
    final sender = message.senderDid.trim();
    final receiver = message.receiverDid?.trim();
    if (owner.isNotEmpty) {
      if (sender == owner && receiver != null && receiver.isNotEmpty) {
        return receiver;
      }
      if (receiver == owner && sender.isNotEmpty) {
        return sender;
      }
    }
    if (!message.isMine && sender.isNotEmpty) {
      return sender;
    }
    if (receiver != null && receiver.isNotEmpty) {
      return receiver;
    }
    return sender.isEmpty ? null : sender;
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

String _readReceiptToken(ConversationSummary conversation) {
  final thread = _readThreadRefFor(conversation).stableId;
  return [
    thread,
    conversation.lastMessageAt.toUtc().microsecondsSinceEpoch,
    conversation.unreadCount,
    conversation.unreadMentionCount,
    conversation.firstUnreadMentionMessageId ?? '',
  ].join('|');
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

({String kind, String id}) _threadPatchKeyFor(AppThreadRef thread) {
  return switch (thread) {
    AppDirectThreadRef(:final peerDidOrHandle) => (
      kind: 'direct',
      id: peerDidOrHandle.trim(),
    ),
    AppGroupThreadRef(:final groupDid) => (kind: 'group', id: groupDid.trim()),
    AppMessageThreadRef(:final threadId) => (
      kind: 'thread',
      id: threadId.trim(),
    ),
  };
}

bool _threadPatchMatchesSubscription(
  ThreadMessagePatch patch,
  _ThreadPatchSubscription subscription,
) {
  return patch.threadKind.trim() == subscription.threadKind &&
      patch.threadId.trim() == subscription.threadId;
}

bool _threadPatchMatchesThreadRef(ThreadMessagePatch patch, AppThreadRef ref) {
  final key = _threadPatchKeyFor(ref);
  return patch.threadKind.trim() == key.kind && patch.threadId.trim() == key.id;
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
