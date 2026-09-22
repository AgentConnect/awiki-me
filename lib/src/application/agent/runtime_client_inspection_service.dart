import 'dart:async';
import '../../domain/entities/agent/agent_command.dart';
import '../../domain/entities/agent/agent_control_payloads.dart';
import '../../domain/entities/agent/runtime_client_installation.dart';
import '../../domain/entities/chat_message.dart';
import '../messaging_service.dart';
import '../models/app_thread_ref.dart';
import '../models/thread_message_patch.dart';

class RuntimeClientInspectionService {
  const RuntimeClientInspectionService(this.messages);
  final MessagingService messages;

  Future<RuntimeClientInstallationReport> inspect(
    String daemonDid, {
    bool refresh = false,
  }) async {
    final source = messages;
    if (source is! CommittedControlMessagingService) {
      throw StateError('client_inspection_unavailable');
    }
    final controls = source as CommittedControlMessagingService;
    final commandId = agentCommandId('cmd_clients');
    final thread = AppThreadRef.direct(daemonDid);
    final result = Completer<RuntimeClientInstallationReport>();
    final subscription = controls
        .watchControlThreadPatches(thread)
        .listen(
          (patch) async {
            try {
              final committed =
                  patch.kind == ThreadMessagePatchKind.repairRequired
                  ? await controls.repairControlThreadStore(thread)
                  : patch;
              for (final message in [
                ...committed.messages,
                if (committed.message != null) committed.message!,
              ]) {
                if (message.senderDid != daemonDid ||
                    message.sendState != MessageSendState.sent ||
                    message.groupId?.isNotEmpty == true ||
                    result.isCompleted) {
                  continue;
                }
                final payload = AgentControlPayloads.decode(
                  message.payloadJson,
                );
                if (payload?['schema'] != AgentControlPayloads.statusSchema ||
                    payload?['daemon_agent_did'] != daemonDid ||
                    payload?['command_id'] != commandId) {
                  continue;
                }
                final details = payload?['result'];
                if (details is! Map ||
                    details['command'] != 'runtime.clients.inspect') {
                  continue;
                }
                if (payload?['state'] == 'failed') {
                  throw StateError('client_inspection_failed');
                }
                final report = details['installation'];
                if (report is! Map) {
                  throw const FormatException('invalid_client_inspection');
                }
                result.complete(
                  RuntimeClientInstallationReport.parse(
                    Map<String, Object?>.from(report),
                  ),
                );
              }
            } on Object catch (error, stack) {
              if (!result.isCompleted) result.completeError(error, stack);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!result.isCompleted) result.completeError(error, stack);
          },
        );
    final response = result.future.timeout(const Duration(seconds: 30));
    unawaited(
      response.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    try {
      await messages
          .sendPayload(
            thread: thread,
            payload: {
              'schema': AgentControlPayloads.commandSchema,
              'command': 'runtime.clients.inspect',
              'command_id': commandId,
              'target_agent_kind': 'daemon',
              'args': {'refresh': refresh},
            },
            idempotencyKey: 'client-inspection:$daemonDid:$commandId',
          )
          .timeout(const Duration(seconds: 30));
      return await response;
    } finally {
      await subscription.cancel();
    }
  }
}
