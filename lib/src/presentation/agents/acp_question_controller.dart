import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_services.dart';
import '../../application/agent/acp_control_service.dart';
import '../../application/models/product_local_models.dart';
import '../../application/product_local_store.dart';
import '../../domain/entities/agent/acp_session.dart';
import '../app_shell/providers/session_provider.dart';
import 'acp_session_provider.dart';

typedef AcpQuestionScope = ({
  String agentDid,
  String conversationId,
  String sessionKey,
  String runId,
  String questionId,
  String definition,
});
AcpQuestionScope acpQuestionScope(
  AcpSession session,
  Map<String, Object?> question,
) => (
  agentDid: session.agentDid,
  conversationId: session.conversationId,
  sessionKey: session.key,
  runId: '${question['run_id']}',
  questionId: '${question['id']}',
  definition:
      question['definition_hash']?.toString() ??
      jsonEncode(question['request']),
);

enum AcpAnswerPhase { editing, sending, uncertain, accepted }

class AcpQuestionDraft {
  const AcpQuestionDraft({
    this.data = const {},
    this.loading = false,
    this.phase = AcpAnswerPhase.editing,
    this.action,
    this.error,
  });
  final Map<String, Object?> data;
  final bool loading;
  final AcpAnswerPhase phase;
  final String? action;
  final String? error;
  bool get editable =>
      !loading &&
      error != 'draft_load_failed' &&
      phase == AcpAnswerPhase.editing;
}

/// App-owned local edits and retry identity only. Question validity and accepted
/// answers remain Daemon facts projected through Core. Never uses chat drafts.
class AcpQuestionController extends StateNotifier<AcpQuestionDraft> {
  AcpQuestionController(
    this.scope,
    this._service,
    this._store,
    this._owner,
    this._isCurrent,
  ) : super(AcpQuestionDraft(loading: _store != null)) {
    if (_store != null) unawaited(_load());
  }
  final AcpQuestionScope scope;
  final AcpControlService _service;
  final ProductLocalStore? _store;
  final String? _owner;
  final bool Function() _isCurrent;
  Future<void> _writes = Future.value();

  /// Navigation may release a form only after its already queued local edits
  /// are saved. Network acknowledgements remain recoverable by command ID.
  Future<void> flush() => _writes;
  String? _command;
  Map<String, Object?>? _args;
  bool get _live => mounted && _isCurrent();
  String get _key =>
      'acp-question-draft:v1:${sha256.convert(utf8.encode(jsonEncode([scope.agentDid, scope.conversationId, scope.sessionKey, scope.runId, scope.questionId, scope.definition])))}';

  Future<void> reload() async {
    if (!_live || state.error != 'draft_load_failed') return;
    state = const AcpQuestionDraft(loading: true);
    await _load();
  }

  Future<void> _load() async {
    try {
      final row = await _store!.loadUiPreference(ownerDid: _owner!, key: _key);
      if (!_live) return;
      final saved = row == null
          ? <String, Object?>{}
          : acpMap(jsonDecode(row.valueJson));
      if (saved.isNotEmpty && saved['schema'] != 'awiki.question-draft.v1') {
        throw const FormatException();
      }
      _command = saved['command_id'] as String?;
      _args = saved['args'] is Map ? acpMap(saved['args']) : null;
      if ((_command == null) != (_args == null) ||
          _command != null &&
              (_command!.isEmpty ||
                  _args!['action'] != 'answer' ||
                  _args!['session_key'] != scope.sessionKey ||
                  _args!['run_id'] != scope.runId ||
                  _args!['question_id'] != scope.questionId ||
                  _args!['definition_hash'] != null &&
                      _args!['definition_hash'] != scope.definition ||
                  !const {
                    'accept',
                    'decline',
                    'cancel',
                  }.contains(acpMap(_args!['response'])['action']))) {
        throw const FormatException('invalid_saved_answer_scope');
      }
      final pending = _command != null && _args != null;
      state = AcpQuestionDraft(
        data: acpMap(saved['data']),
        phase: saved['accepted'] == true
            ? AcpAnswerPhase.accepted
            : pending
            ? AcpAnswerPhase.uncertain
            : AcpAnswerPhase.editing,
        action: acpMap(_args?['response'])['action'] as String?,
      );
    } on Object {
      if (_live) state = const AcpQuestionDraft(error: 'draft_load_failed');
    }
  }

  void edit(Map<String, Object?> data) {
    if (!_live || !state.editable) return;
    state = AcpQuestionDraft(
      data: Map.unmodifiable(acpMap(jsonDecode(jsonEncode(data)))),
    );
    unawaited(
      _persist().catchError((Object _) {
        if (_live) {
          state = AcpQuestionDraft(
            data: state.data,
            phase: state.phase,
            action: state.action,
            error: 'draft_save_failed',
          );
        }
      }),
    );
  }

  Future<void> _persist() {
    if (_store == null) return Future.value();
    final value = jsonEncode({
      'schema': 'awiki.question-draft.v1',
      'data': state.data,
      'command_id': _command,
      'args': _args,
      'accepted': state.phase == AcpAnswerPhase.accepted,
    });
    final write = _writes.catchError((Object _) {}).then((_) async {
      if (!_live) return;
      await _store.saveUiPreference(
        LocalUiPreference(
          ownerDid: _owner!,
          key: _key,
          valueJson: value,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    });
    _writes = write;
    return write;
  }

  Future<void> submit(
    AcpSession session,
    Map<String, Object?> question,
    Map<String, Object?> response,
  ) async {
    if (!_live ||
        state.loading ||
        state.error == 'draft_load_failed' ||
        state.phase == AcpAnswerPhase.sending ||
        state.phase == AcpAnswerPhase.accepted) {
      return;
    }
    if (acpQuestionScope(session, question) != scope ||
        session.stopping ||
        (_owner != null && session.active['requester_did'] != _owner) ||
        session.active['run_id'] != scope.runId ||
        question['response'] != null ||
        (question['status'] != null && question['status'] != 'pending') ||
        question['expires_at_ms'] is! int ||
        (question['expires_at_ms'] as int) <=
            DateTime.now().millisecondsSinceEpoch) {
      return;
    }
    if (state.phase == AcpAnswerPhase.uncertain) {
      if (_args == null ||
          acpMap(_args!['response'])['action'] != response['action']) {
        return;
      }
    } else {
      _command = newAcpCommandId();
      _args = acpCommandArgs(
        session,
        'answer',
        values: {
          'run_id': scope.runId,
          'question_id': scope.questionId,
          if (question['definition_hash'] != null)
            'definition_hash': question['definition_hash'],
          'response': jsonDecode(jsonEncode(response)),
        },
      );
    }
    state = AcpQuestionDraft(
      data: state.data,
      phase: AcpAnswerPhase.sending,
      action: response['action'] as String,
    );
    var sent = false;
    try {
      // Persist retry identity before sending, including on application restart.
      await _persist();
      if (!_live) return;
      sent = true;
      await _service.send(
        agentDid: scope.agentDid,
        commandId: _command!,
        args: _args!,
      );
      if (!_live) return;
      state = AcpQuestionDraft(
        data: state.data,
        phase: AcpAnswerPhase.accepted,
        action: state.action,
      );
    } on Object catch (error) {
      if (!_live) return;
      final uncertain = sent && error is! StateError;
      if (!uncertain) {
        _command = null;
        _args = null;
      }
      state = AcpQuestionDraft(
        data: state.data,
        phase: uncertain ? AcpAnswerPhase.uncertain : AcpAnswerPhase.editing,
        action: uncertain ? state.action : null,
        error: sent ? 'answer_not_accepted' : 'draft_save_failed',
      );
    }
    try {
      await _persist();
    } on Object {
      // Keep the in-memory acknowledgement. Retrying the persisted command after
      // a restart is idempotent; a storage failure cannot undo an accepted answer.
      if (_live) {
        state = AcpQuestionDraft(
          data: state.data,
          phase: state.phase,
          action: state.action,
          error: 'draft_save_failed',
        );
      }
    }
  }
}

final acpQuestionControllerProvider = StateNotifierProvider.autoDispose
    .family<AcpQuestionController, AcpQuestionDraft, AcpQuestionScope>((
      ref,
      scope,
    ) {
      final epoch = ref.watch(sessionProvider.select((s) => s.activeEpoch));
      final controller = AcpQuestionController(
        scope,
        ref.read(acpControlServiceProvider),
        epoch == null ? null : ref.read(productLocalStoreProvider),
        epoch?.ownerDid,
        () => ref.read(sessionProvider).activeEpoch == epoch,
      );
      ref.onCancel(() {
        final link = ref.keepAlive();
        unawaited(
          controller.flush().then(
            (_) => link.close(),
            onError: (Object _, StackTrace __) => link.close(),
          ),
        );
      });
      return controller;
    });
