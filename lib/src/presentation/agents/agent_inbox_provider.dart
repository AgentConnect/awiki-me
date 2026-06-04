import 'dart:async';

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
    this.groupId,
    this.groupDid,
    this.lastMessageAtMs,
  });

  final String threadId;
  final String kind;
  final String title;
  final String? peerDid;
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
      groupId: _string(json['group_id']),
      groupDid: _string(json['group_did']),
      lastMessagePreview: _string(json['last_message_preview']) ?? '',
      lastMessageAtMs: _int(json['last_message_at_ms']),
      unreadCount: _int(json['unread_count']) ?? 0,
      hasAttachments: _bool(json['has_attachments']),
      lastContentType: _string(json['last_content_type']) ?? 'text',
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
      filename: _string(json['filename']) ?? '附件',
      mimeType: _string(json['mime_type']) ?? 'application/octet-stream',
      sizeBytes: _int(json['size_bytes']),
      downloadState: _string(json['download_state']),
    );
  }
}

class AgentInboxMessage {
  const AgentInboxMessage({
    required this.messageId,
    required this.senderDid,
    required this.direction,
    required this.contentType,
    required this.text,
    required this.truncated,
    this.sentAtMs,
    this.attachments = const <AgentInboxAttachment>[],
  });

  final String messageId;
  final String senderDid;
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

  final Ref ref;
  Timer? _listTimeout;
  Timer? _threadTimeout;
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
    } catch (error) {
      _listAppending = false;
      state = state.copyWith(isRefreshing: false, error: error.toString());
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
    state = state.copyWith(
      daemonAgentDid: daemonAgentDid,
      runtimeAgentDid: runtimeAgentDid,
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
            groupDid: item.groupDid,
          );
      state = state.copyWith(
        thread: state.thread.copyWith(lastRequestId: requestId),
      );
      _scheduleThreadTimeout(requestId);
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
            groupDid: item.groupDid,
            cursor: cursor,
          );
      state = state.copyWith(
        thread: state.thread.copyWith(lastRequestId: requestId),
      );
      _scheduleThreadTimeout(requestId);
    } catch (error) {
      _threadPrepending = false;
      state = state.copyWith(
        thread: state.thread.copyWith(
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
    _listTimeout?.cancel();
    _listTimeout = null;
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
      items: shouldAppend ? _mergeItems(state.items, parsedItems) : parsedItems,
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
    _threadTimeout?.cancel();
    _threadTimeout = null;
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

  void _scheduleListTimeout(String requestId) {
    _listTimeout?.cancel();
    _listTimeout = Timer(const Duration(seconds: 20), () {
      if (!mounted || state.lastRequestId != requestId) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: 'Daemon 暂时没有返回，请稍后重试',
      );
    });
  }

  void _scheduleThreadTimeout(String requestId) {
    _threadTimeout?.cancel();
    _threadTimeout = Timer(const Duration(seconds: 20), () {
      if (!mounted || state.thread.lastRequestId != requestId) {
        return;
      }
      state = state.copyWith(
        thread: state.thread.copyWith(
          isLoading: false,
          isRefreshing: false,
          error: 'Daemon 暂时没有返回，请稍后重试',
        ),
      );
    });
  }

  @override
  void dispose() {
    _listTimeout?.cancel();
    _threadTimeout?.cancel();
    super.dispose();
  }
}

List<AgentInboxItem> _mergeItems(
  List<AgentInboxItem> existing,
  List<AgentInboxItem> incoming,
) {
  final seen = existing.map((item) => item.threadId).toSet();
  return <AgentInboxItem>[
    ...existing,
    for (final item in incoming)
      if (seen.add(item.threadId)) item,
  ];
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

final agentInboxProvider =
    StateNotifierProvider<AgentInboxController, AgentInboxState>(
      (ref) => AgentInboxController(ref),
    );
