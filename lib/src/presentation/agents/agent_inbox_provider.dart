import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../domain/entities/agent/agent_control_payloads.dart';

enum AgentInboxScope { all, direct, group }

class AgentInboxItem {
  const AgentInboxItem({
    required this.threadId,
    required this.kind,
    required this.title,
    required this.lastMessagePreview,
    required this.unreadCount,
    required this.hasAttachments,
    required this.lastContentType,
    this.peerDid,
    this.peerHandle,
    this.peerUserId,
    this.groupId,
    this.groupDid,
    this.lastMessageAtMs,
  });

  final String threadId;
  final String kind;
  final String title;
  final String? peerDid;
  final String? peerHandle;
  final String? peerUserId;
  final String? groupId;
  final String? groupDid;
  final String lastMessagePreview;
  final int? lastMessageAtMs;
  final int unreadCount;
  final bool hasAttachments;
  final String lastContentType;

  factory AgentInboxItem.fromJson(Map<String, Object?> json) {
    return AgentInboxItem(
      threadId: _string(json['thread_id']) ?? '',
      kind: _string(json['kind']) ?? 'direct',
      title: _string(json['title']) ?? '未命名会话',
      peerDid: _string(json['peer_did']),
      peerHandle: _string(json['peer_handle']),
      peerUserId: _string(json['peer_user_id']),
      groupId: _string(json['group_id']),
      groupDid: _string(json['group_did']),
      lastMessagePreview: _string(json['last_message_preview']) ?? '',
      lastMessageAtMs: _int(json['last_message_at_ms']),
      unreadCount: _int(json['unread_count']) ?? 0,
      hasAttachments: _bool(json['has_attachments']),
      lastContentType: _string(json['last_content_type']) ?? 'text',
    );
  }

  AgentInboxItem copyWith({int? unreadCount}) {
    return AgentInboxItem(
      threadId: threadId,
      kind: kind,
      title: title,
      peerDid: peerDid,
      peerHandle: peerHandle,
      peerUserId: peerUserId,
      groupId: groupId,
      groupDid: groupDid,
      lastMessagePreview: lastMessagePreview,
      lastMessageAtMs: lastMessageAtMs,
      unreadCount: unreadCount ?? this.unreadCount,
      hasAttachments: hasAttachments,
      lastContentType: lastContentType,
    );
  }
}

class AgentInboxAttachment {
  const AgentInboxAttachment({
    required this.attachmentId,
    required this.filename,
    required this.mimeType,
    this.sizeBytes,
    this.downloadState,
  });

  final String attachmentId;
  final String filename;
  final String mimeType;
  final int? sizeBytes;
  final String? downloadState;

  factory AgentInboxAttachment.fromJson(Map<String, Object?> json) {
    return AgentInboxAttachment(
      attachmentId: _string(json['attachment_id']) ?? '',
      filename: _string(json['filename']) ?? '未命名附件',
      mimeType: _string(json['mime_type']) ?? '文件',
      sizeBytes: _int(json['size_bytes']),
      downloadState: _string(json['download_state']),
    );
  }
}

class AgentInboxMessage {
  const AgentInboxMessage({
    required this.messageId,
    required this.senderDid,
    this.senderHandle,
    required this.direction,
    required this.contentType,
    required this.text,
    required this.truncated,
    this.sentAtMs,
    this.attachments = const <AgentInboxAttachment>[],
  });

  final String messageId;
  final String senderDid;
  final String? senderHandle;
  final int? sentAtMs;
  final String direction;
  final String contentType;
  final String text;
  final bool truncated;
  final List<AgentInboxAttachment> attachments;

  factory AgentInboxMessage.fromJson(Map<String, Object?> json) {
    final attachments = json['attachments'];
    return AgentInboxMessage(
      messageId: _string(json['message_id']) ?? '',
      senderDid: _string(json['sender_did']) ?? '',
      senderHandle: _string(json['sender_handle']),
      sentAtMs: _int(json['sent_at_ms']),
      direction: _string(json['direction']) ?? 'unknown',
      contentType: _string(json['content_type']) ?? 'text',
      text: _string(json['text']) ?? '',
      truncated: _bool(json['truncated']),
      attachments: attachments is List
          ? attachments
                .whereType<Map>()
                .map(
                  (item) => AgentInboxAttachment.fromJson(
                    item.map<String, Object?>(
                      (key, value) => MapEntry(key.toString(), value),
                    ),
                  ),
                )
                .toList()
          : const <AgentInboxAttachment>[],
    );
  }
}

class AgentInboxThreadState {
  const AgentInboxThreadState({
    this.runtimeAgentDid,
    this.threadId,
    this.kind,
    this.title,
    this.messages = const <AgentInboxMessage>[],
    this.nextCursor,
    this.isLoading = false,
    this.isRefreshing = false,
    this.lastRequestId,
    this.fetchedAtMs,
    this.error,
  });

  final String? runtimeAgentDid;
  final String? threadId;
  final String? kind;
  final String? title;
  final List<AgentInboxMessage> messages;
  final String? nextCursor;
  final bool isLoading;
  final bool isRefreshing;
  final String? lastRequestId;
  final int? fetchedAtMs;
  final String? error;

  bool get hasTimeout =>
      error == _daemonNoResponseMessage && messages.isNotEmpty;

  AgentInboxThreadState copyWith({
    String? runtimeAgentDid,
    String? threadId,
    String? kind,
    String? title,
    List<AgentInboxMessage>? messages,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? isLoading,
    bool? isRefreshing,
    String? lastRequestId,
    int? fetchedAtMs,
    String? error,
    bool clearError = false,
  }) {
    return AgentInboxThreadState(
      runtimeAgentDid: runtimeAgentDid ?? this.runtimeAgentDid,
      threadId: threadId ?? this.threadId,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastRequestId: lastRequestId ?? this.lastRequestId,
      fetchedAtMs: fetchedAtMs ?? this.fetchedAtMs,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AgentInboxState {
  const AgentInboxState({
    this.runtimeAgentDid,
    this.daemonAgentDid,
    this.scope = AgentInboxScope.all,
    this.items = const <AgentInboxItem>[],
    this.nextCursor,
    this.isLoading = false,
    this.isRefreshing = false,
    this.lastRequestId,
    this.fetchedAtMs,
    this.error,
    this.thread = const AgentInboxThreadState(),
  });

  final String? runtimeAgentDid;
  final String? daemonAgentDid;
  final AgentInboxScope scope;
  final List<AgentInboxItem> items;
  final String? nextCursor;
  final bool isLoading;
  final bool isRefreshing;
  final String? lastRequestId;
  final int? fetchedAtMs;
  final String? error;
  final AgentInboxThreadState thread;

  bool get hasListTimeout =>
      error == _daemonNoResponseMessage && items.isNotEmpty;

  AgentInboxState copyWith({
    String? runtimeAgentDid,
    String? daemonAgentDid,
    AgentInboxScope? scope,
    List<AgentInboxItem>? items,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? isLoading,
    bool? isRefreshing,
    String? lastRequestId,
    int? fetchedAtMs,
    String? error,
    bool clearError = false,
    AgentInboxThreadState? thread,
  }) {
    return AgentInboxState(
      runtimeAgentDid: runtimeAgentDid ?? this.runtimeAgentDid,
      daemonAgentDid: daemonAgentDid ?? this.daemonAgentDid,
      scope: scope ?? this.scope,
      items: items ?? this.items,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastRequestId: lastRequestId ?? this.lastRequestId,
      fetchedAtMs: fetchedAtMs ?? this.fetchedAtMs,
      error: clearError ? null : (error ?? this.error),
      thread: thread ?? this.thread,
    );
  }
}

class AgentInboxController extends StateNotifier<AgentInboxState> {
  AgentInboxController(this.ref) : super(const AgentInboxState());

  @visibleForTesting
  static Duration responseTimeout = const Duration(seconds: 20);
  @visibleForTesting
  static Duration statusPollInterval = const Duration(milliseconds: 700);
  @visibleForTesting
  static int statusPollAttempts = 35;

  final Ref ref;
  Timer? _listTimeout;
  Timer? _threadTimeout;
  Timer? _listStatusPoll;
  Timer? _threadStatusPoll;
  bool _listAppending = false;
  bool _threadPrepending = false;

  Future<void> queryInbox({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    AgentInboxScope scope = AgentInboxScope.all,
    bool refresh = false,
  }) async {
    final sameMailbox =
        state.runtimeAgentDid == runtimeAgentDid && state.scope == scope;
    _listAppending = false;
    state = state.copyWith(
      daemonAgentDid: daemonAgentDid,
      runtimeAgentDid: runtimeAgentDid,
      scope: scope,
      items: sameMailbox ? state.items : const <AgentInboxItem>[],
      isLoading: !sameMailbox || state.items.isEmpty,
      isRefreshing: sameMailbox && (refresh || state.items.isNotEmpty),
      clearNextCursor: true,
      clearError: true,
      thread: sameMailbox ? state.thread : const AgentInboxThreadState(),
    );
    try {
      final requestId = await ref
          .read(agentControlServiceProvider)
          .queryRuntimeInbox(
            daemonAgentDid: daemonAgentDid,
            runtimeAgentDid: runtimeAgentDid,
            scope: _scopeName(scope),
          );
      state = state.copyWith(lastRequestId: requestId);
      _scheduleListTimeout(requestId);
      _pollListStatus(
        daemonAgentDid: daemonAgentDid,
        runtimeAgentDid: runtimeAgentDid,
        requestId: requestId,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: error.toString(),
      );
    }
  }

  Future<void> loadMoreInbox() async {
    final daemonAgentDid = state.daemonAgentDid;
    final runtimeAgentDid = state.runtimeAgentDid;
    final cursor = state.nextCursor;
    if (daemonAgentDid == null ||
        runtimeAgentDid == null ||
        cursor == null ||
        state.isLoading ||
        state.isRefreshing) {
      return;
    }
    _listAppending = true;
    state = state.copyWith(isRefreshing: true, clearError: true);
    try {
      final requestId = await ref
          .read(agentControlServiceProvider)
          .queryRuntimeInbox(
            daemonAgentDid: daemonAgentDid,
            runtimeAgentDid: runtimeAgentDid,
            scope: _scopeName(state.scope),
            cursor: cursor,
          );
      state = state.copyWith(lastRequestId: requestId);
      _scheduleListTimeout(requestId);
      _pollListStatus(
        daemonAgentDid: daemonAgentDid,
        runtimeAgentDid: runtimeAgentDid,
        requestId: requestId,
      );
    } catch (error) {
      _listAppending = false;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: error.toString(),
      );
    }
  }

  Future<void> queryThread({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required AgentInboxItem item,
    bool refresh = false,
  }) async {
    final sameThread =
        state.thread.runtimeAgentDid == runtimeAgentDid &&
        state.thread.threadId == item.threadId;
    _threadPrepending = false;
    final items = state.items
        .map((candidate) {
          if (candidate.threadId != item.threadId ||
              candidate.unreadCount == 0) {
            return candidate;
          }
          return candidate.copyWith(unreadCount: 0);
        })
        .toList(growable: false);
    state = state.copyWith(
      daemonAgentDid: daemonAgentDid,
      runtimeAgentDid: runtimeAgentDid,
      items: items,
      thread: state.thread.copyWith(
        runtimeAgentDid: runtimeAgentDid,
        threadId: item.threadId,
        kind: item.kind,
        title: item.title,
        messages: sameThread
            ? state.thread.messages
            : const <AgentInboxMessage>[],
        isLoading: !sameThread || state.thread.messages.isEmpty,
        isRefreshing:
            sameThread && (refresh || state.thread.messages.isNotEmpty),
        clearNextCursor: true,
        clearError: true,
      ),
    );
    try {
      final requestId = await ref
          .read(agentControlServiceProvider)
          .queryRuntimeInboxThread(
            daemonAgentDid: daemonAgentDid,
            runtimeAgentDid: runtimeAgentDid,
            threadId: item.threadId,
            kind: item.kind,
            peerDid: item.peerDid,
            peerHandle: item.peerHandle,
            groupDid: item.groupDid,
          );
      state = state.copyWith(
        thread: state.thread.copyWith(lastRequestId: requestId),
      );
      _scheduleThreadTimeout(requestId);
      _pollThreadStatus(
        daemonAgentDid: daemonAgentDid,
        runtimeAgentDid: runtimeAgentDid,
        requestId: requestId,
      );
    } catch (error) {
      state = state.copyWith(
        thread: state.thread.copyWith(
          isLoading: false,
          isRefreshing: false,
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> loadMoreThread() async {
    final daemonAgentDid = state.daemonAgentDid;
    final runtimeAgentDid = state.runtimeAgentDid;
    final threadId = state.thread.threadId;
    final kind = state.thread.kind;
    final cursor = state.thread.nextCursor;
    if (daemonAgentDid == null ||
        runtimeAgentDid == null ||
        threadId == null ||
        kind == null ||
        cursor == null ||
        state.thread.isLoading ||
        state.thread.isRefreshing) {
      return;
    }
    final item = state.items.firstWhere(
      (candidate) => candidate.threadId == threadId,
      orElse: () => AgentInboxItem(
        threadId: threadId,
        kind: kind,
        title: state.thread.title ?? '收件箱线程',
        lastMessagePreview: '',
        unreadCount: 0,
        hasAttachments: false,
        lastContentType: 'text',
        peerHandle: kind == 'direct' ? state.thread.title : null,
      ),
    );
    _threadPrepending = true;
    state = state.copyWith(
      thread: state.thread.copyWith(isRefreshing: true, clearError: true),
    );
    try {
      final requestId = await ref
          .read(agentControlServiceProvider)
          .queryRuntimeInboxThread(
            daemonAgentDid: daemonAgentDid,
            runtimeAgentDid: runtimeAgentDid,
            threadId: item.threadId,
            kind: item.kind,
            peerDid: item.peerDid,
            peerHandle: item.peerHandle,
            groupDid: item.groupDid,
            cursor: cursor,
          );
      state = state.copyWith(
        thread: state.thread.copyWith(lastRequestId: requestId),
      );
      _scheduleThreadTimeout(requestId);
      _pollThreadStatus(
        daemonAgentDid: daemonAgentDid,
        runtimeAgentDid: runtimeAgentDid,
        requestId: requestId,
      );
    } catch (error) {
      _threadPrepending = false;
      state = state.copyWith(
        thread: state.thread.copyWith(
          isLoading: false,
          isRefreshing: false,
          error: error.toString(),
        ),
      );
    }
  }

  void closeThread() {
    state = state.copyWith(thread: const AgentInboxThreadState());
  }

  void applyControlPayload(Map<String, Object?> payload) {
    if (payload['schema'] != AgentControlPayloads.statusSchema) {
      return;
    }
    final scope = _string(payload['status_scope']);
    if (scope == 'runtime_inbox') {
      _applyInboxPayload(payload);
    } else if (scope == 'runtime_inbox_thread') {
      _applyThreadPayload(payload);
    }
  }

  void _applyInboxPayload(Map<String, Object?> payload) {
    final requestId =
        _string(payload['request_id']) ?? _string(payload['command_id']);
    if (requestId != null &&
        state.lastRequestId != null &&
        requestId != state.lastRequestId) {
      return;
    }
    if (!_matchesCurrentMailboxPayload(payload)) {
      return;
    }
    _listTimeout?.cancel();
    _listTimeout = null;
    _listStatusPoll?.cancel();
    _listStatusPoll = null;
    final shouldAppend = _listAppending;
    _listAppending = false;
    final succeeded = _string(payload['state']) == 'succeeded';
    if (!succeeded) {
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: _string(payload['message']) ?? '收件箱查询失败',
      );
      return;
    }
    final result = _readMap(payload['result']);
    final items = result['items'];
    final parsedItems = items is List
        ? items
              .whereType<Map>()
              .map(
                (item) => AgentInboxItem.fromJson(
                  item.map<String, Object?>(
                    (key, value) => MapEntry(key.toString(), value),
                  ),
                ),
              )
              .toList()
        : const <AgentInboxItem>[];
    state = state.copyWith(
      items: shouldAppend
          ? _mergeItems(state.items, parsedItems)
          : _dedupeItems(parsedItems),
      nextCursor: _string(result['next_cursor']),
      clearNextCursor: result['next_cursor'] == null,
      fetchedAtMs: _int(result['fetched_at_ms']),
      isLoading: false,
      isRefreshing: false,
      clearError: true,
    );
  }

  void _applyThreadPayload(Map<String, Object?> payload) {
    final requestId =
        _string(payload['request_id']) ?? _string(payload['command_id']);
    if (requestId != null &&
        state.thread.lastRequestId != null &&
        requestId != state.thread.lastRequestId) {
      return;
    }
    if (!_matchesCurrentMailboxPayload(payload)) {
      return;
    }
    _threadTimeout?.cancel();
    _threadTimeout = null;
    _threadStatusPoll?.cancel();
    _threadStatusPoll = null;
    final shouldPrepend = _threadPrepending;
    _threadPrepending = false;
    final succeeded = _string(payload['state']) == 'succeeded';
    if (!succeeded) {
      state = state.copyWith(
        thread: state.thread.copyWith(
          isLoading: false,
          isRefreshing: false,
          error: _string(payload['message']) ?? '线程查询失败',
        ),
      );
      return;
    }
    final result = _readMap(payload['result']);
    final messages = result['messages'];
    final parsedMessages = messages is List
        ? messages
              .whereType<Map>()
              .map(
                (item) => AgentInboxMessage.fromJson(
                  item.map<String, Object?>(
                    (key, value) => MapEntry(key.toString(), value),
                  ),
                ),
              )
              .toList()
        : const <AgentInboxMessage>[];
    state = state.copyWith(
      thread: state.thread.copyWith(
        title: _string(result['title']),
        messages: shouldPrepend
            ? _prependMessages(state.thread.messages, parsedMessages)
            : parsedMessages,
        nextCursor: _string(result['next_cursor']),
        clearNextCursor: result['next_cursor'] == null,
        fetchedAtMs: _int(result['fetched_at_ms']),
        isLoading: false,
        isRefreshing: false,
        clearError: true,
      ),
    );
  }

  bool _matchesCurrentMailboxPayload(Map<String, Object?> payload) {
    final payloadDaemonDid = _string(payload['daemon_agent_did']);
    final payloadRuntimeDid = _string(payload['runtime_agent_did']);
    return payloadDaemonDid != null &&
        payloadRuntimeDid != null &&
        payloadDaemonDid == state.daemonAgentDid &&
        payloadRuntimeDid == state.runtimeAgentDid;
  }

  void _scheduleListTimeout(String requestId) {
    _listTimeout?.cancel();
    _listTimeout = Timer(responseTimeout, () {
      if (!mounted || state.lastRequestId != requestId) {
        return;
      }
      state = state.copyWith(
        isLoading: state.items.isEmpty,
        isRefreshing: state.items.isNotEmpty,
        error: _daemonNoResponseMessage,
      );
    });
  }

  void _scheduleThreadTimeout(String requestId) {
    _threadTimeout?.cancel();
    _threadTimeout = Timer(responseTimeout, () {
      if (!mounted || state.thread.lastRequestId != requestId) {
        return;
      }
      state = state.copyWith(
        thread: state.thread.copyWith(
          isLoading: state.thread.messages.isEmpty,
          isRefreshing: state.thread.messages.isNotEmpty,
          error: _daemonNoResponseMessage,
        ),
      );
    });
  }

  void _pollListStatus({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String requestId,
  }) {
    _listStatusPoll?.cancel();
    var attempts = 0;
    _listStatusPoll = Timer.periodic(statusPollInterval, (timer) async {
      if (!mounted || state.lastRequestId != requestId) {
        timer.cancel();
        return;
      }
      attempts += 1;
      final payload = await _findStatusPayload(
        daemonAgentDid: daemonAgentDid,
        runtimeAgentDid: runtimeAgentDid,
        requestId: requestId,
        statusScope: 'runtime_inbox',
      );
      if (!mounted || state.lastRequestId != requestId) {
        timer.cancel();
        return;
      }
      if (payload != null) {
        timer.cancel();
        _applyInboxPayload(payload);
        return;
      }
      if (attempts >= statusPollAttempts) {
        timer.cancel();
      }
    });
  }

  void _pollThreadStatus({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String requestId,
  }) {
    _threadStatusPoll?.cancel();
    var attempts = 0;
    _threadStatusPoll = Timer.periodic(statusPollInterval, (timer) async {
      if (!mounted || state.thread.lastRequestId != requestId) {
        timer.cancel();
        return;
      }
      attempts += 1;
      final payload = await _findStatusPayload(
        daemonAgentDid: daemonAgentDid,
        runtimeAgentDid: runtimeAgentDid,
        requestId: requestId,
        statusScope: 'runtime_inbox_thread',
      );
      if (!mounted || state.thread.lastRequestId != requestId) {
        timer.cancel();
        return;
      }
      if (payload != null) {
        timer.cancel();
        _applyThreadPayload(payload);
        return;
      }
      if (attempts >= statusPollAttempts) {
        timer.cancel();
      }
    });
  }

  Future<Map<String, Object?>?> _findStatusPayload({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String requestId,
    required String statusScope,
  }) {
    return ref
        .read(agentControlStatusStoreProvider)
        .findStatusPayload(
          daemonAgentDid: daemonAgentDid,
          runtimeAgentDid: runtimeAgentDid,
          requestId: requestId,
          statusScope: statusScope,
        );
  }

  @override
  void dispose() {
    _listTimeout?.cancel();
    _threadTimeout?.cancel();
    _listStatusPoll?.cancel();
    _threadStatusPoll?.cancel();
    super.dispose();
  }
}

List<AgentInboxItem> _mergeItems(
  List<AgentInboxItem> existing,
  List<AgentInboxItem> incoming,
) {
  final merged = _dedupeItems(existing);
  final aliasToIndex = <String, int>{};
  for (var index = 0; index < merged.length; index += 1) {
    _registerInboxItemAliases(aliasToIndex, index, merged[index]);
  }
  for (final item in incoming) {
    _mergeInboxItem(merged, aliasToIndex, item);
  }
  return merged;
}

List<AgentInboxItem> _dedupeItems(List<AgentInboxItem> items) {
  final merged = <AgentInboxItem>[];
  final aliasToIndex = <String, int>{};
  for (final item in items) {
    _mergeInboxItem(merged, aliasToIndex, item);
  }
  return merged;
}

void _mergeInboxItem(
  List<AgentInboxItem> merged,
  Map<String, int> aliasToIndex,
  AgentInboxItem item,
) {
  final aliases = _inboxItemAliases(item);
  int? index;
  for (final alias in aliases) {
    final candidate = aliasToIndex[alias];
    if (candidate != null) {
      index = candidate;
      break;
    }
  }
  if (index == null) {
    merged.add(item);
    _registerInboxItemAliases(aliasToIndex, merged.length - 1, item);
    return;
  }
  final preferred = _preferInboxItem(merged[index], item);
  merged[index] = preferred;
  _registerInboxItemAliases(aliasToIndex, index, item);
  _registerInboxItemAliases(aliasToIndex, index, preferred);
}

void _registerInboxItemAliases(
  Map<String, int> aliasToIndex,
  int index,
  AgentInboxItem item,
) {
  for (final alias in _inboxItemAliases(item)) {
    aliasToIndex[alias] = index;
  }
}

List<String> _inboxItemAliases(AgentInboxItem item) {
  final aliases = <String>{};
  final kind = item.kind.toLowerCase();
  if (kind == 'direct') {
    final peerUserId = _stableKey(item.peerUserId);
    final peerHandle = _normalizedHandleKey(item.peerHandle);
    final peerDid = _stableKey(item.peerDid);
    if (peerUserId != null && peerHandle != null) {
      aliases.add('direct:scope:$peerUserId:$peerHandle');
    }
    if (peerHandle != null) {
      aliases.add('direct:handle:$peerHandle');
    }
    if (peerDid != null) {
      aliases.add('direct:did:$peerDid');
    }
  } else if (kind == 'group') {
    final groupDid = _stableKey(item.groupDid);
    final groupId = _stableKey(item.groupId);
    if (groupDid != null) {
      aliases.add('group:did:$groupDid');
    }
    if (groupId != null) {
      aliases.add('group:id:$groupId');
    }
  }
  final threadId = _stableKey(item.threadId);
  if (threadId != null) {
    aliases.add('thread:$threadId');
  }
  return aliases.toList(growable: false);
}

AgentInboxItem _preferInboxItem(
  AgentInboxItem current,
  AgentInboxItem candidate,
) {
  final currentScore = _inboxItemQualityScore(current);
  final candidateScore = _inboxItemQualityScore(candidate);
  if (candidateScore != currentScore) {
    return candidateScore > currentScore ? candidate : current;
  }
  final currentTime = current.lastMessageAtMs;
  final candidateTime = candidate.lastMessageAtMs;
  if (currentTime != null &&
      candidateTime != null &&
      candidateTime != currentTime) {
    return candidateTime > currentTime ? candidate : current;
  }
  if (currentTime == null && candidateTime != null) {
    return candidate;
  }
  return current;
}

int _inboxItemQualityScore(AgentInboxItem item) {
  var score = _stableKey(item.threadId) == null ? 0 : 1;
  final kind = item.kind.toLowerCase();
  if (kind == 'direct') {
    if (item.threadId.startsWith('dm:peer-scope:v1:')) {
      score += 8;
    }
    if (_stableKey(item.peerUserId) != null &&
        _normalizedHandleKey(item.peerHandle) != null) {
      score += 8;
    } else if (_normalizedHandleKey(item.peerHandle) != null) {
      score += 4;
    }
    if (_stableKey(item.peerDid) != null) {
      score += 2;
    }
  } else if (kind == 'group') {
    if (_stableKey(item.groupDid) != null || _stableKey(item.groupId) != null) {
      score += 6;
    }
  }
  if (_stableKey(item.title) != null) {
    score += 1;
  }
  return score;
}

List<AgentInboxMessage> _prependMessages(
  List<AgentInboxMessage> existing,
  List<AgentInboxMessage> incoming,
) {
  final seen = existing.map((message) => message.messageId).toSet();
  return <AgentInboxMessage>[
    for (final message in incoming)
      if (seen.add(message.messageId)) message,
    ...existing,
  ];
}

String _scopeName(AgentInboxScope scope) {
  switch (scope) {
    case AgentInboxScope.all:
      return 'all';
    case AgentInboxScope.direct:
      return 'direct';
    case AgentInboxScope.group:
      return 'group';
  }
}

Map<String, Object?> _readMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return value.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
}

String? _string(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String? _stableKey(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

String? _normalizedHandleKey(String? value) => _stableKey(value)?.toLowerCase();

int? _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

bool _bool(Object? value) {
  if (value is bool) {
    return value;
  }
  return value?.toString().toLowerCase() == 'true';
}

const _daemonNoResponseMessage = 'Daemon 暂时没有返回，请稍后重试';

final agentInboxProvider =
    StateNotifierProvider<AgentInboxController, AgentInboxState>(
      (ref) => AgentInboxController(ref),
    );
