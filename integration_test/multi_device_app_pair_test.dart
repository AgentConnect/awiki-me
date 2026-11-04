// Dual-process App-pair entrypoint. The isolated builder freezes one role per bundle.
import 'dart:io';
import '../tests/e2e/runtime_control/invocation.dart';
import '../tests/e2e/flutter/app/multi_device_join_ui_test.dart' as join_e2e;

const String _role = String.fromEnvironment('AWIKI_MULTI_DEVICE_APP_PAIR_ROLE');

void main() {
  final invocation = E2eInvocation.load(
    Platform.environment,
    family: 'app-pair',
  );
  switch (invocation?.mode.role ?? _role) {
    case 'admin':
      return join_e2e.appPairAdminMain();
    case 'joiner':
      return join_e2e.appPairJoinerMain();
    default:
      throw StateError('The multi-device App-pair role is invalid.');
  }
}
