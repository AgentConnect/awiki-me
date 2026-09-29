import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/agent/acp_control_service.dart';
import '../../domain/entities/agent/acp_session.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_reply_reference.dart';
import '../app_shell/providers/session_provider.dart';
import 'acp_session_provider.dart';
import 'acp_task_status.dart';

typedef AcpHistoryQuery = ({
  String agentDid,
  String sessionKey,
  String conversationId,
  String sourcesJson,
});

/// Reads details only for the message window supplied by Core. No local message
/// store, guessed group route, polling loop, or replay of a model request.
final acpTaskHistoryProvider = FutureProvider.autoDispose
    .family<int, AcpHistoryQuery>((ref, query) async {
      final epoch = ref.watch(sessionProvider.select((s) => s.activeEpoch));
      var disposed = false;
      ref.onDispose(() => disposed = true);
      final sources = (jsonDecode(query.sourcesJson) as List).cast<String>();
      if (sources.isEmpty || sources.length > 50) {
        throw StateError('invalid_history_sources');
      }
      final initial = ref.read(acpSessionsProvider).sessions[query.sessionKey];
      if (initial?.agentDid != query.agentDid ||
          initial?.conversationId != query.conversationId) {
        throw StateError('unknown_history_scope');
      }
      if (initial?.data['task_history_available'] != true) return 0;
      final controls = ref.read(acpControlServiceProvider);
      int? cursor;
      var count = 0;
      final seen = <int>{};
      // One accepted task per source and agent; even byte-limited single-record
      // pages terminate within this window's size. Identity/disposal stops paging.
      for (var page = 0; page <= sources.length; page++) {
        if (disposed || ref.read(sessionProvider).activeEpoch != epoch) {
          return count;
        }
        final result = await controls.send(
          agentDid: query.agentDid,
          commandId: newAcpCommandId(),
          args: {
            'action': 'task_history',
            'session_key': query.sessionKey,
            'source_message_ids': sources,
            'limit': 10,
            if (cursor != null) 'cursor': cursor,
          },
        );
        if (disposed || ref.read(sessionProvider).activeEpoch != epoch) {
          return count;
        }
        final history = acpMap(result['task_history']);
        if (result['session_key'] != query.sessionKey ||
            history['tasks'] is! List ||
            history['has_more'] is! bool) {
          throw StateError('invalid_history_page');
        }
        // Facts have already entered the projection via the committed-response
        // callback. This result controls pagination only.
        count += acpMaps(history['tasks']).length;
        if (history['has_more'] != true) return count;
        final next = history['next_cursor'];
        if (next is! int ||
            next <= 0 ||
            cursor != null && next >= cursor ||
            !seen.add(next)) {
          throw StateError('invalid_history_cursor');
        }
        cursor = next;
      }
      throw StateError('history_page_limit');
    });

List<AcpHistoryQuery> acpHistoryQueries(
  List<AcpSession> sessions,
  List<ChatMessage> messages,
  Set<String> ownedAgents,
) {
  final sources = <String>{};
  for (final message in messages) {
    if (message.sendState != MessageSendState.sent) continue;
    sources.add(message.remoteId ?? message.localId);
    final reference = MessageReplyReference.tryParse(message.payloadJson);
    if (reference != null) sources.add(reference.sourceMessageId);
  }
  final ids = sources.toList()..sort();
  return [
    for (final session in sessions)
      if (ownedAgents.contains(session.agentDid) &&
          session.data['task_history_available'] == true)
        for (var index = 0; index < ids.length; index += 50)
          (
            agentDid: session.agentDid,
            sessionKey: session.key,
            conversationId: session.conversationId,
            sourcesJson: jsonEncode(
              ids.sublist(index, (index + 50).clamp(0, ids.length)),
            ),
          ),
  ];
}

class AcpTaskHistoryLoader extends ConsumerWidget {
  const AcpTaskHistoryLoader({super.key, required this.queries});
  final List<AcpHistoryQuery> queries;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = [
      for (final query in queries)
        if (ref.watch(acpTaskHistoryProvider(query)).hasError) query,
    ];
    if (failed.isEmpty) return const SizedBox.shrink();
    return CupertinoButton(
      key: const ValueKey('acp-history-retry'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minimumSize: const Size(44, 32),
      onPressed: () {
        for (final query in failed) {
          ref.invalidate(acpTaskHistoryProvider(query));
        }
      },
      child: Text(
        acpText(
          context,
          '部分执行记录未能加载，点击重试',
          'Some activity could not load. Retry',
        ),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
