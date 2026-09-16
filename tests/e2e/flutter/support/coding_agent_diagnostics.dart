import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/acp_session.dart';

/// Failure diagnostics use public Core-backed reads and omit payloads, IDs,
/// credentials and content. Reading this projection cannot retry a command.
Future<Map<String, Object?>> codingAgentDeliveryDiagnostics(
  MessagingService messages,
  String daemonDid,
) async {
  final result = <String, Object?>{};
  if (messages is MessageSyncDiagnosticsService) {
    final sync = await (messages as MessageSyncDiagnosticsService)
        .syncDiagnostics();
    result.addAll({
      'sync_mode': sync.mode.name,
      'pending_mutations': sync.pendingMutationCount,
      'retry_state': sync.retryState.name,
      'dirty_domain_count': sync.dirtyDomains.length,
      'lane_degraded': sync.laneDegraded,
    });
  }
  if (messages is CommittedControlMessagingService) {
    final patch = await (messages as CommittedControlMessagingService)
        .repairControlThreadStore(AppThreadRef.direct(daemonDid));
    final controls = codingAgentControlDeliverySummary([
      ...patch.messages,
      if (patch.message != null) patch.message!,
    ]);
    result['control_count'] = controls.length;
    result['controls'] = controls
        .skip(controls.length > 8 ? controls.length - 8 : 0)
        .toList();
  }
  return result;
}

List<Map<String, Object?>> codingAgentControlDeliverySummary(
  List<ChatMessage> messages,
) => messages
    .map(
      (message) => <String, Object?>{
        'outgoing': message.isMine,
        'state': message.sendState.name,
        'remote_id_present': message.remoteId?.isNotEmpty == true,
      },
    )
    .toList(growable: false);

List<Map<String, Object?>> codingAgentAcpProjectionSummary(
  List<ChatMessage> messages,
  Set<String> conversationIds,
) => [
  for (final message in messages)
    if (AgentControlPayloads.decode(message.payloadJson)?['schema'] ==
        'awiki.acp.status.v1')
      {
        'conversation_present': message.conversationId?.isNotEmpty == true,
        'conversation_matches': conversationIds.contains(
          message.conversationId,
        ),
        'sender_matches':
            acpMap(
              AgentControlPayloads.decode(message.payloadJson)?['acp'],
            )['agent_did'] ==
            message.senderDid,
        'incoming': !message.isMine,
        'sent': message.sendState == MessageSendState.sent,
      },
];
