import 'package:awiki_me/src/domain/entities/agent/acp_session.dart';
import 'package:awiki_me/src/application/models/app_session.dart';

/// A prepared fixture must restore the exact authenticated account. Missing or
/// stale state never silently registers a replacement identity.
Future<AppSession> prepareCodingAgentSession({
  required bool reusePreparedIdentity,
  required String expectedFullHandle,
  required Future<AppSession?> Function() restore,
  required Future<AppSession> Function() register,
}) async {
  if (!reusePreparedIdentity) return register();
  final session = await restore();
  if (session == null ||
      !session.authenticated ||
      session.accountBinding == null ||
      session.handle?.toLowerCase() != expectedFullHandle.toLowerCase()) {
    throw StateError(
      'Prepared ACP App identity is not the exact authenticated account.',
    );
  }
  return session;
}

Future<AppSession> restorePreparedCodingAccount({
  required String expectedFullHandle,
  required Future<List<AppSession>> Function() list,
  required Future<AppSession> Function(String identityId) login,
}) async {
  // Prior E2E teardown logs out without deleting its isolated Core identity.
  final identities = await list();
  final matches = identities
      .where(
        (identity) =>
            identity.handle?.toLowerCase() == expectedFullHandle.toLowerCase(),
      )
      .toList();
  if (matches.length != 1) {
    throw StateError('Prepared ACP App account must match exactly once.');
  }
  return login(matches.single.identityId);
}

/// Retry only text entry, before any send action, when native focus/IME updates
/// replace the value. Matches the existing desktop peer input strategy.
Future<void> enterStableCodingAgentText({
  required String expected,
  required Future<void> Function() enter,
  required String Function() read,
}) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    await enter();
    if (read() == expected) return;
  }
  throw StateError(
    'composer_text_not_retained: expected_length=${expected.length}, '
    'observed_length=${read().length}',
  );
}

/// A live, unanswered question holds the actual client task until user action.
/// A model instruction to sleep is not evidence that a task will stay busy.
bool hasAcpBlockingQuestion(AcpSession session, {required int nowMs}) =>
    session.busy &&
    !session.stopping &&
    session.questions.any(
      (question) =>
          question['run_id'] == session.active['run_id'] &&
          question['response'] == null &&
          question['expires_at_ms'] is int &&
          (question['expires_at_ms']! as int) > nowMs,
    );

/// ACP can include progress narration before a tool task's completion marker.
/// File tasks still separately verify the delivered file's exact bytes.
/// Question tasks still require the actual user's selected answer marker.
bool matchesCodingAgentFinal(
  Object? actual,
  String expected, {
  bool allowProgressText = false,
}) =>
    actual is String &&
    (allowProgressText
        ? actual.trimRight().endsWith(expected)
        : actual == expected);
