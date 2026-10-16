import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> until(WidgetTester tester, bool Function() predicate) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 300));
  }
  throw StateError('hosted_app_state_deadline');
}

Future<void> input(WidgetTester tester, String identifier, String value) async {
  final field = find.descendant(
    of: find.bySemanticsIdentifier(identifier),
    matching: find.byType(CupertinoTextField),
  );
  if (field.evaluate().length != 1) {
    throw StateError('hosted_app_field_missing');
  }
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

// Only our closed diagnostic codes may cross the private fixture boundary.
String hostedFailureCode(Object error) {
  const coreCodes = {
    'invalid_input',
    'identity_required',
    'identity_not_found',
    'identity_not_ready',
    'auth_required',
    'session_expired',
    'permission_denied',
    'local_identity_recovery_required',
    'transport_unavailable',
    'local_state_unavailable',
    'identity_unresolved',
    'identity_binding_conflict',
    'remote_error',
    'protocol_error',
    'internal',
  };
  if (error is core.AwikiImCoreException && coreCodes.contains(error.code)) {
    return 'core_${error.code}';
  }
  const codes = {
    'hosted_app_state_deadline',
    'hosted_app_field_missing',
    'hosted_fixture_permissions',
    'hosted_http_failed',
    'hosted_response_invalid',
    'hosted_request_delivery_deadline',
    'hosted_fixture_failed',
    'hosted_fixture_timeout',
    'hosted_fixture_target',
    'hosted_fixture_identity',
    'hosted_pairing_mismatch',
    'hosted_app_wrong_identity',
    'hosted_local_management_deadline',
    'hosted_root_authorized_update_failed',
  };
  if (error is StateError &&
      (codes.contains(error.message) ||
          RegExp(
            r'^hosted_http_status_[1-5][0-9]{2}$',
          ).hasMatch(error.message.toString()))) {
    return error.message;
  }
  return error.runtimeType.toString();
}

String hostedFailureLocation(StackTrace stack) {
  final matches = RegExp(
    r'(hosted_[a-z_]+\.dart):([0-9]+):([0-9]+)',
  ).allMatches(stack.toString());
  return matches.take(3).map((match) => '${match[1]}:${match[2]}').join(',');
}
