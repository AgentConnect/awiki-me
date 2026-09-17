import 'dart:async';
import '../../domain/entities/agent/agent_command.dart';
import '../../domain/entities/agent/agent_control_payloads.dart';
import '../../domain/entities/agent/acp_session.dart';
import '../../domain/entities/chat_message.dart';
import '../messaging_service.dart';
import '../models/app_thread_ref.dart';
import '../models/thread_message_patch.dart';

class AcpControlService {
  const AcpControlService(this.messages, {this.onCommittedResponse});
  final MessagingService messages;
  final void Function(ChatMessage message)? onCommittedResponse;

  /// Subscribe before sending and wait for the committed response. Transport
  /// retries keep the caller's command ID and the exact original arguments.
  Future<Map<String, Object?>> send({
    required String agentDid,
    required String commandId,
    required Map<String, Object?> args,
  }) async {
    final source = messages;
    if (source is! CommittedControlMessagingService) {
      throw StateError('acp_control_unavailable');
    }
    final controls = source as CommittedControlMessagingService;
    final completer = Completer<Map<String, Object?>>();
    final thread = AppThreadRef.direct(agentDid);
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
                if (message.senderDid != agentDid ||
                    message.sendState != MessageSendState.sent ||
                    message.groupId?.isNotEmpty == true) {
                  continue;
                }
                final payload = AgentControlPayloads.decode(
                  message.payloadJson,
                );
                if (payload?['schema'] == 'awiki.acp.command-result.v1' &&
                    payload?['command_id'] == commandId &&
                    payload?['runtime_agent_did'] == agentDid &&
                    !completer.isCompleted) {
                  onCommittedResponse?.call(message);
                  completer.complete(payload!);
                }
              }
            } on Object catch (error, stack) {
              if (!completer.isCompleted) completer.completeError(error, stack);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!completer.isCompleted) completer.completeError(error, stack);
          },
        );
    // Install the error/timeout handler before transport can synchronously emit.
    final configuration =
        args['action'] == 'prepare_session' || args['action'] == 'set_model';
    final response = completer.future.timeout(
      configuration ? const Duration(minutes: 2) : const Duration(seconds: 25),
    );
    unawaited(
      response.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    try {
      await messages.sendPayload(
        thread: thread,
        payload: {
          'schema': AgentControlPayloads.commandSchema,
          'command': 'runtime.acp.control',
          'command_id': commandId,
          'args': args,
        },
        idempotencyKey: 'acp:$agentDid:$commandId',
      );
      final payload = await response;
      if (payload['state'] == 'failed') {
        throw StateError(
          payload['error_code']?.toString() ?? 'acp_command_failed',
        );
      }
      return acpMap(payload['acp_result']);
    } finally {
      // Observe a pending timeout/error even when sending fails first.
      unawaited(
        response.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      );
      await subscription.cancel();
    }
  }
}

Map<String, Object?> acpCommandArgs(
  AcpSession session,
  String action, {
  Map<String, Object?> values = const {},
}) => {
  'action': action,
  'session_key': session.key,
  'revision': session.revision,
  ...values,
};
String newAcpCommandId() => agentCommandId('cmd_acp');
