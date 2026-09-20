import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/agent/acp_control_service.dart';
import '../../domain/entities/agent/acp_session.dart';
import '../app_shell/providers/session_provider.dart';
import 'acp_model_controller.dart';
import 'acp_session_provider.dart';

enum AcpModelRefreshPhase { idle, loading, synchronizing, deferred, failed }

class AcpModelRefreshState {
  const AcpModelRefreshState({
    this.phase = AcpModelRefreshPhase.idle,
    this.retryAfter,
  });
  final AcpModelRefreshPhase phase;
  final Duration? retryAfter;
  bool get pending =>
      phase == AcpModelRefreshPhase.loading ||
      phase == AcpModelRefreshPhase.synchronizing;
}

/// Metadata work never owns the composer or mutates a model selection. Like
/// configuration, display waits for the Core-routed committed snapshot.
class AcpModelRefreshController extends StateNotifier<AcpModelRefreshState> {
  AcpModelRefreshController(this.scope, this._send, this._projection)
    : super(const AcpModelRefreshState());
  final AcpModelScope scope;
  final Future<Map<String, Object?>> Function(String, Map<String, Object?>)
  _send;
  final AcpProjection Function() _projection;
  String? _confirmedKey;
  int? _confirmedRevision;

  Future<void> refresh(AcpSession session) async {
    if (state.pending ||
        !session.modelRefreshSupported ||
        session.agentDid != scope.agentDid ||
        session.conversationId != scope.conversationId ||
        !session.canSelectModel) {
      return;
    }
    state = const AcpModelRefreshState(phase: AcpModelRefreshPhase.loading);
    try {
      final result = await _send(
        newAcpCommandId(),
        acpCommandArgs(session, 'refresh_models'),
      );
      if (!mounted) return;
      final refresh = acpMap(result['model_refresh']);
      if (refresh['state'] == 'deferred') {
        final retry = refresh['retry_after_ms'];
        state = AcpModelRefreshState(
          phase: AcpModelRefreshPhase.deferred,
          retryAfter: retry is int && retry > 0
              ? Duration(milliseconds: retry.clamp(1, 65000))
              : null,
        );
        return;
      }
      final confirmed = acpMaps(result['sessions'])
          .where(
            (s) =>
                s['session_key'] == session.key &&
                s['agent_did'] == scope.agentDid &&
                s['group'] == false &&
                AcpSession.parse(s) != null,
          )
          .firstOrNull;
      if (refresh['state'] != 'refreshed' || confirmed == null) {
        throw StateError('invalid_model_catalog_result');
      }
      _confirmedKey = session.key;
      _confirmedRevision = confirmed['revision']! as int;
      state = const AcpModelRefreshState(
        phase: AcpModelRefreshPhase.synchronizing,
      );
      reconcile(_projection());
    } on Object {
      if (mounted) {
        state = const AcpModelRefreshState(phase: AcpModelRefreshPhase.failed);
      }
    }
  }

  void reconcile(AcpProjection projection) {
    if (!mounted || state.phase != AcpModelRefreshPhase.synchronizing) return;
    final session = projection.sessions[_confirmedKey];
    if (session == null ||
        session.agentDid != scope.agentDid ||
        session.conversationId != scope.conversationId ||
        session.revision < _confirmedRevision!) {
      return;
    }
    state = const AcpModelRefreshState();
  }
}

final acpModelRefreshControllerProvider =
    StateNotifierProvider.family<
      AcpModelRefreshController,
      AcpModelRefreshState,
      AcpModelScope
    >((ref, scope) {
      ref.watch(sessionProvider.select((s) => s.activeEpoch));
      final controller = AcpModelRefreshController(
        scope,
        (id, args) => ref
            .read(acpControlServiceProvider)
            .send(agentDid: scope.agentDid, commandId: id, args: args),
        () => ref.read(acpSessionsProvider),
      );
      ref.listen(acpSessionsProvider, (_, next) => controller.reconcile(next));
      return controller;
    });
