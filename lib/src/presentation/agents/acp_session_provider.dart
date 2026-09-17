import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_services.dart';
import '../../application/agent/acp_control_service.dart';
import '../../application/messaging_service.dart';
import '../../application/models/app_thread_ref.dart';
import '../../application/models/thread_message_patch.dart';
import '../../domain/entities/agent/acp_session.dart';
import '../../domain/entities/agent/acp_task.dart';
import '../../domain/entities/agent/agent_control_payloads.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/chat_message.dart';
import '../app_shell/providers/session_provider.dart';

class AcpProjection {
  const AcpProjection({
    this.sessions = const {},
    this.rejections = const {},
    this.tasks = const {},
    this.activity = const {},
  });
  final Map<String, AcpSession> sessions;
  final Map<String, Map<String, Object?>> rejections;
  final Map<String, AcpTask> tasks;
  final Map<String, AcpActivity> activity;
  List<AcpSession> forConversation(String id) => sessions.values
      .where((s) => s.conversationId == id)
      .map(_effectiveSession)
      .toList(growable: false);
  List<AcpTask> tasksForConversation(String id) =>
      tasks.values.where((t) => t.conversationId == id).toList(growable: false);
  bool? busyForAgent(String agentDid) {
    final known = activity.values.where((a) => a.agentDid == agentDid);
    final records = tasks.values.where((t) => t.agentDid == agentDid);
    if (known.isEmpty && records.isEmpty) return null;
    return records.any((t) {
          final latest = activity[t.sessionKey];
          return t.running &&
              (latest == null ||
                  latest.revision < t.revision ||
                  latest.activeRunId == t.runId);
        }) ||
        known.any(
          (a) =>
              a.activeRunId != null &&
              tasks['$agentDid:${a.activeRunId}']?.terminal != true,
        );
  }

  AcpSession _effectiveSession(AcpSession session) {
    bool ended(Map<String, Object?> work) {
      final task = tasks['${session.agentDid}:${work['run_id']}'];
      return task != null && task.terminal;
    }

    if (!ended(session.active) && !ended(session.waiting)) return session;
    return AcpSession.parse({
      ...session.data,
      if (ended(session.active)) 'active': null,
      if (ended(session.waiting)) 'waiting': null,
    }, localConversationId: session.conversationId)!;
  }
}

/// Background activity has no local conversation route. A daemon's own Direct
/// channel is authoritative about work, but not about another thread's identity.
class AcpActivity {
  const AcpActivity(this.agentDid, this.revision, this.activeRunId);
  final String agentDid;
  final int revision;
  final String? activeRunId;
}

class AcpSessionController extends StateNotifier<AcpProjection> {
  AcpSessionController() : super(const AcpProjection());

  void applyDaemon(
    Map<String, Object?> payload,
    String daemonDid,
    List<AgentSummary> inventory,
  ) {
    if (payload['schema'] != AgentControlPayloads.statusSchema ||
        payload['daemon_agent_did'] != daemonDid) {
      return;
    }
    final allowed = inventory
        .where((a) => a.isRuntime && a.daemonAgentDid == daemonDid)
        .map((a) => a.agentDid)
        .toSet();
    for (final item in acpMaps(acpMap(payload['acp_result'])['sessions'])) {
      _applyKnown(item, allowed);
    }
    for (final run in acpMaps(payload['runs'])) {
      final snapshot = acpMap(run['acp']);
      _applyKnown(snapshot, allowed);
      _applyTask(acpMap(run['acp_task']), allowed, null);
    }
  }

  void _applyKnown(Map<String, Object?> snapshot, Set<String> allowed) {
    final known = state.sessions[snapshot['session_key']];
    if (known != null &&
        (known.group != (snapshot['group'] == true) ||
            known.agentDid != snapshot['agent_did'])) {
      return;
    }
    _applyActivity(snapshot, allowed);
    // A daemon status message lives in the daemon's Direct conversation. It
    // cannot establish the runtime/group display route; Core must supply it.
    if (known == null || known.group != (snapshot['group'] == true)) return;
    _apply(
      snapshot,
      allowed.contains(snapshot['agent_did']),
      known.conversationId,
    );
  }

  void applyConversation(ChatMessage message, String conversationId) {
    if (message.conversationId != conversationId ||
        message.sendState != MessageSendState.sent) {
      return;
    }
    final payload = AgentControlPayloads.decode(message.payloadJson);
    if (payload?['schema'] == 'awiki.acp.command-result.v1') {
      final result = acpMap(payload?['acp_result']);
      for (final item in acpMaps(result['sessions'])) {
        if (result['prepared_session_key'] == item['session_key'] &&
            item['group'] == false &&
            message.groupId?.isNotEmpty != true) {
          _apply(item, item['agent_did'] == message.senderDid, conversationId);
        } else {
          _applyKnown(item, {message.senderDid});
        }
      }
      for (final item in acpMaps(acpMap(result['task_history'])['tasks'])) {
        // History includes groups; never bind it to the private control channel.
        final route = state.sessions[item['session_key']]?.conversationId;
        _applyTask(item, {message.senderDid}, route);
      }
      return;
    }
    if (payload?['schema'] != 'awiki.acp.status.v1') return;
    final snapshot = acpMap(payload?['acp']);
    _apply(
      snapshot,
      snapshot['agent_did'] == message.senderDid &&
          (snapshot['group'] == true) == (message.groupId?.isNotEmpty == true),
      conversationId,
    );
    final task = acpMap(payload?['acp_task']);
    if ((task['group'] == true) == (message.groupId?.isNotEmpty == true)) {
      _applyTask(task, {message.senderDid}, conversationId);
    }
    final rejection = acpMap(payload?['acp_rejection']);
    _reject(
      {...rejection, 'conversation_id': conversationId},
      {message.senderDid},
    );
  }

  void _apply(Object? value, bool trusted, String conversationId) {
    if (!trusted) return;
    final session = AcpSession.parse(
      value,
      localConversationId: conversationId,
    );
    if (session == null) return;
    final old = state.sessions[session.key];
    if (old != null &&
        (old.revision >= session.revision ||
            old.agentDid != session.agentDid ||
            old.conversationId != session.conversationId)) {
      return;
    }
    _applyActivity(session.data, {session.agentDid});
    // A route established by a committed runtime/group message can now bind
    // task records that previously arrived on the daemon's private channel.
    final tasks = {
      for (final entry in state.tasks.entries)
        entry.key:
            entry.value.sessionKey == session.key &&
                entry.value.agentDid == session.agentDid &&
                entry.value.group == session.group &&
                entry.value.conversationId == null
            ? entry.value.withConversation(conversationId)
            : entry.value,
    };
    state = AcpProjection(
      sessions: {...state.sessions, session.key: session},
      rejections: state.rejections,
      tasks: tasks,
      activity: state.activity,
    );
    for (final work in [session.active, session.waiting, ...session.history]) {
      if (work['run_id'] is! String) continue;
      final active = work['run_id'] == session.active['run_id'];
      final waiting = work['run_id'] == session.waiting['run_id'];
      final output = active || work['run_id'] == session.data['output_run_id'];
      _applyTask(
        {
          'schema': 'awiki.acp.task.v1',
          'session_key': session.key,
          'agent_did': session.agentDid,
          'group': session.group,
          'revision': session.revision,
          ...work,
          'state': active
              ? (session.stopping ? 'stopping' : 'running')
              : waiting
              ? (session.waitingPaused ? 'paused' : 'waiting')
              : work['state'],
          if (output) ...{
            'text': session.text,
            'tools': session.tools,
            'questions': session.questions,
            'omitted_tool_count': session.data['omitted_tool_count'],
            'error_code': session.data['error_code'],
            'error_details': session.data['error_details'],
          },
          'model_id': session.data['model_id'],
        },
        {session.agentDid},
        conversationId,
        summary: !active,
      );
    }
  }

  void _applyActivity(Map<String, Object?> snapshot, Set<String> allowed) {
    final key = snapshot['session_key'];
    final agent = snapshot['agent_did'];
    final revision = snapshot['revision'];
    if (snapshot['schema'] != 'awiki.acp.session.v1' ||
        key is! String ||
        key.isEmpty ||
        agent is! String ||
        !allowed.contains(agent) ||
        revision is! int ||
        revision < 1) {
      return;
    }
    final prior = state.activity[key];
    if (prior != null &&
        (prior.agentDid != agent || prior.revision >= revision)) {
      return;
    }
    final run = acpMap(snapshot['active'])['run_id'];
    state = AcpProjection(
      sessions: state.sessions,
      rejections: state.rejections,
      tasks: state.tasks,
      activity: {
        ...state.activity,
        key: AcpActivity(agent, revision, run is String ? run : null),
      },
    );
  }

  void _applyTask(
    Map<String, Object?> value,
    Set<String> allowed,
    String? route, {
    bool summary = false,
  }) {
    if (!allowed.contains(value['agent_did'])) return;
    final known = state.sessions[value['session_key']];
    final record = AcpTask.parse(
      value,
      localConversationId: route ?? known?.conversationId,
    );
    if (record == null ||
        known != null &&
            (known.agentDid != record.agentDid ||
                known.group != record.group ||
                record.conversationId != known.conversationId)) {
      return;
    }
    final old = state.tasks[record.key];
    if (old != null &&
        (old.sessionKey != record.sessionKey ||
            old.group != record.group ||
            old.conversationId != null &&
                record.conversationId != null &&
                old.conversationId != record.conversationId)) {
      return;
    }
    if (old != null &&
        old.terminal &&
        (!record.terminal || old.state != record.state)) {
      return;
    }
    if (old != null &&
        (old.revision > record.revision || summary && old.terminal)) {
      return;
    }
    // A session history item is only a summary. Keep the already projected
    // output while its durable terminal detail arrives on the control stream.
    var next = summary && old != null
        ? AcpTask.parse({
            ...old.data,
            ...record.data,
          }, localConversationId: record.conversationId ?? old.conversationId)!
        : record;
    if (old != null && old.revision == record.revision) {
      if (summary &&
          old.conversationId == null &&
          record.conversationId != null) {
        next = old.withConversation(record.conversationId!);
      } else if (summary) {
        return;
      }
    }
    if (next.conversationId == null && old?.conversationId != null) {
      next = next.withConversation(old!.conversationId!);
    }
    state = AcpProjection(
      sessions: state.sessions,
      rejections: state.rejections,
      activity: state.activity,
      tasks: {...state.tasks, record.key: next},
    );
  }

  void _reject(Map<String, Object?> rejection, Set<String> allowed) {
    if (rejection['schema'] != 'awiki.acp.rejection.v1' ||
        !allowed.contains(rejection['agent_did'])) {
      return;
    }
    final source = rejection['source_message_id'];
    if (source is! String || source.isEmpty) return;
    state = AcpProjection(
      sessions: state.sessions,
      tasks: state.tasks,
      activity: state.activity,
      rejections: {
        ...state.rejections,
        '${rejection['conversation_id']}:$source': rejection,
      },
    );
  }
}

final acpSessionsProvider =
    StateNotifierProvider<AcpSessionController, AcpProjection>((ref) {
      ref.watch(sessionProvider.select((s) => s.activeEpoch));
      return AcpSessionController();
    });
final acpControlServiceProvider = Provider<AcpControlService>((ref) {
  final epoch = ref.watch(sessionProvider.select((s) => s.activeEpoch));
  var active = true;
  ref.onDispose(() => active = false);
  return AcpControlService(
    ref.watch(messagingServiceProvider),
    onCommittedResponse: (message) {
      final route = message.conversationId;
      if (active &&
          route != null &&
          route.isNotEmpty &&
          ref.read(sessionProvider).activeEpoch == epoch) {
        ref
            .read(acpSessionsProvider.notifier)
            .applyConversation(message, route);
      }
    },
  );
});

typedef AcpConversationRef = ({String conversationId, String threadId});
final acpConversationProjectionProvider = StreamProvider.autoDispose
    .family<int, AcpConversationRef>((ref, conversation) async* {
      final epoch = ref.watch(sessionProvider.select((s) => s.activeEpoch));
      if (epoch == null) return;
      final messages = ref.watch(messagingServiceProvider);
      if (messages is! CommittedControlMessagingService) return;
      final controls = messages as CommittedControlMessagingService;
      // Core resolves this canonical ID for the current device. A transport
      // thread alias can select a different legacy store after device Join.
      final thread = AppThreadRef.thread(conversation.conversationId);
      var disposed = false;
      ref.onDispose(() => disposed = true);
      var sequence = 0;
      await for (final patch in controls.watchControlThreadPatches(thread)) {
        final committed = patch.kind == ThreadMessagePatchKind.repairRequired
            ? await controls.repairControlThreadStore(thread)
            : patch;
        if (disposed || ref.read(sessionProvider).activeEpoch != epoch) return;
        final projection = ref.read(acpSessionsProvider.notifier);
        for (final message in [
          ...committed.messages,
          if (committed.message != null) committed.message!,
        ]) {
          projection.applyConversation(message, conversation.conversationId);
        }
        yield ++sequence;
      }
    });
