import '../../domain/entities/handle_recovery.dart';
import 'app_session.dart';

class HandleRecoveryCompletion {
  const HandleRecoveryCompletion({
    required this.progress,
    required this.session,
  });

  final HandleRecoveryProgress progress;

  /// Authenticated candidate for the replacement identity already persisted
  /// by Core. AppSessionService must still select/authenticate it and persist
  /// the active identity before AppRuntime initializes E2EE. This object is
  /// not Recovery proof or the persistence authority for activation retry.
  final AppSession session;
}
