import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_services.dart';
import '../../application/agent/acp_control_service.dart';
import '../../application/messaging_service.dart';
import '../../application/models/app_thread_ref.dart';
import '../../application/models/thread_message_patch.dart';
import '../../domain/entities/agent/acp_session.dart';
import '../../domain/entities/agent/agent_control_payloads.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/chat_message.dart';
import '../app_shell/providers/session_provider.dart';

class AcpProjection {
  const AcpProjection({this.sessions = const {}, this.rejections = const {}});
  final Map<String, AcpSession> sessions;
  final Map<String, Map<String, Object?>> rejections;
  List<AcpSession> forConversation(String id) => sessions.values
      .where((s) => s.conversationId == id)
      .toList(growable: false);
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
    }
  }

  void _applyKnown(Map<String, Object?> snapshot, Set<String> allowed) {
    final known = state.sessions[snapshot['session_key']];
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
    if (payload?['schema'] != 'awiki.acp.status.v1') return;
    final snapshot = acpMap(payload?['acp']);
    _apply(
      snapshot,
      snapshot['agent_did'] == message.senderDid &&
          (snapshot['group'] == true) == (message.groupId?.isNotEmpty == true),
      conversationId,
    );
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
    state = AcpProjection(
      sessions: {...state.sessions, session.key: session},
      rejections: state.rejections,
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
final acpControlServiceProvider = Provider<AcpControlService>(
  (ref) => AcpControlService(ref.watch(messagingServiceProvider)),
);

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
