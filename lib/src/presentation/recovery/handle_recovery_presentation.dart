import '../../domain/entities/handle_recovery.dart';
import 'handle_recovery_provider.dart';

enum HandleRecoveryViewStage {
  checking,
  verification,
  confirmation,
  continuation,
  completed,
  blocked,
}

/// Presentation only. All command permissions still come from Core actions.
class HandleRecoveryPresentation {
  HandleRecoveryPresentation(this.state);

  final HandleRecoveryState state;

  HandleRecoveryUiError? get error {
    final code = state.progress?.failureCode;
    return state.error ??
        (code == null
            ? null
            : handleRecoveryUiErrorFrom(HandleRecoveryFailure(code)));
  }

  bool get showFactorInput {
    final permitted =
        state.canRequestOtp || state.allows(HandleRecoveryAction.prepare);
    return permitted &&
        (state.progress?.commitAttempted != true ||
            error == HandleRecoveryUiError.factorRetryRequired ||
            state.progress?.failureCode ==
                HandleRecoveryFailureCode.factorRetryRequired);
  }

  bool get canRestartPreparation =>
      state.allows(HandleRecoveryAction.discardPreAttempt) &&
      state.progress?.commitAttempted == false &&
      !showFactorInput &&
      !state.allows(HandleRecoveryAction.activate) &&
      !state.allows(HandleRecoveryAction.resume) &&
      !state.allows(HandleRecoveryAction.activateIdentity);

  HandleRecoveryViewStage get stage {
    if (!state.authoritative) return HandleRecoveryViewStage.checking;
    if (state.allows(HandleRecoveryAction.activateIdentity)) {
      return HandleRecoveryViewStage.completed;
    }
    if (showFactorInput) return HandleRecoveryViewStage.verification;
    if (state.allows(HandleRecoveryAction.activate)) {
      return HandleRecoveryViewStage.confirmation;
    }
    if (state.allows(HandleRecoveryAction.resume)) {
      return HandleRecoveryViewStage.continuation;
    }
    return HandleRecoveryViewStage.blocked;
  }
}
