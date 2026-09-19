import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/agent/acp_control_service.dart';
import '../../domain/entities/agent/acp_session.dart';
import '../app_shell/providers/session_provider.dart';
import 'acp_session_provider.dart';

typedef AcpModelScope = ({String agentDid, String conversationId});

enum AcpModelPhase { idle, sending, uncertain, synchronizing, failed }

class AcpModelOperation {
  const AcpModelOperation({
    this.phase = AcpModelPhase.idle,
    this.attempted = false,
    this.targetModel,
    this.errorCode,
  });
  final AcpModelPhase phase;
  final bool attempted;
  final String? targetModel;
  final String? errorCode;
  bool get blocksSending =>
      phase == AcpModelPhase.sending ||
      phase == AcpModelPhase.uncertain ||
      phase == AcpModelPhase.synchronizing;
}

/// Owns uncertain commands beyond the lifetime of a model sheet or chat page.
/// The response confirms execution; only the Core-routed projection confirms
/// which conversation can display it. A transport retry uses the exact command.
class AcpModelController extends StateNotifier<AcpModelOperation> {
  AcpModelController(this.scope, this._send, this._projection)
    : super(const AcpModelOperation());
  final AcpModelScope scope;
  final Future<Map<String, Object?>> Function(
    String commandId,
    Map<String, Object?> args,
  )
  _send;
  final AcpProjection Function() _projection;
  String? _commandId;
  Map<String, Object?>? _args;
  String? _confirmedSession;
  int? _confirmedRevision;

  Future<bool> prepare() => _start(const {'action': 'prepare_session'});
  Future<bool> select(AcpSession session, String model) async {
    if (session.agentDid != scope.agentDid ||
        session.conversationId != scope.conversationId ||
        session.group ||
        !session.canSelectModel ||
        !session.models.any((m) => m['id'] == model)) {
      return false;
    }
    return _start(
      acpCommandArgs(session, 'set_model', values: {'model_id': model}),
    );
  }

  Future<bool> _start(Map<String, Object?> args) async {
    if (state.blocksSending) return false;
    _commandId = newAcpCommandId();
    _args = Map.unmodifiable(args);
    return _execute();
  }

  Future<bool> retry() async {
    if ((state.phase == AcpModelPhase.uncertain ||
            state.phase == AcpModelPhase.synchronizing) &&
        _args != null) {
      return _execute();
    }
    if (state.phase == AcpModelPhase.failed) return prepare();
    return false;
  }

  Future<bool> _execute() async {
    final target = _args!['model_id'] as String?;
    state = AcpModelOperation(
      phase: AcpModelPhase.sending,
      attempted: true,
      targetModel: target,
    );
    try {
      final result = await _send(_commandId!, _args!);
      if (!mounted) return false;
      final sessions = acpMaps(result['sessions']);
      final confirmed = sessions
          .where(
            (s) =>
                s['session_key'] == result['prepared_session_key'] &&
                s['agent_did'] == scope.agentDid &&
                s['group'] != true &&
                AcpSession.parse(s) != null,
          )
          .firstOrNull;
      if (confirmed == null) throw StateError('invalid_configuration_result');
      _confirmedSession = confirmed['session_key'] as String;
      _confirmedRevision = confirmed['revision'] as int;
      state = AcpModelOperation(
        phase: AcpModelPhase.synchronizing,
        attempted: true,
        targetModel: target,
      );
      reconcile(_projection());
      return true;
    } on Object catch (error) {
      if (!mounted) return false;
      final rejected = error is StateError;
      state = AcpModelOperation(
        phase: rejected ? AcpModelPhase.failed : AcpModelPhase.uncertain,
        attempted: true,
        targetModel: target,
        errorCode: rejected ? error.message.toString() : null,
      );
      if (rejected) {
        _commandId = null;
        _args = null;
      }
      return false;
    }
  }

  void reconcile(AcpProjection projection) {
    if (!mounted || state.phase != AcpModelPhase.synchronizing) return;
    final session = projection.sessions[_confirmedSession];
    if (session == null ||
        session.agentDid != scope.agentDid ||
        session.conversationId != scope.conversationId ||
        session.revision < _confirmedRevision!) {
      return;
    }
    _commandId = null;
    _args = null;
    state = const AcpModelOperation(attempted: true);
  }
}

final acpModelControllerProvider =
    StateNotifierProvider.family<
      AcpModelController,
      AcpModelOperation,
      AcpModelScope
    >((ref, scope) {
      ref.watch(sessionProvider.select((s) => s.activeEpoch));
      final controller = AcpModelController(
        scope,
        (id, args) => ref
            .read(acpControlServiceProvider)
            .send(agentDid: scope.agentDid, commandId: id, args: args),
        () => ref.read(acpSessionsProvider),
      );
      ref.listen(acpSessionsProvider, (_, next) => controller.reconcile(next));
      return controller;
    });
