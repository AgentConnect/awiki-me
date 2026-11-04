import 'dart:io';
import '../tests/e2e/runtime_control/invocation.dart';
import '../tests/e2e/flutter/desktop_cli_peer/desktop_cli_peer_e2e.dart';

void main() {
  final invocation = E2eInvocation.load(
    Platform.environment,
    family: 'restart',
  );
  switch (invocation?.mode.phase) {
    case 'restart-a':
      return runDesktopCliPeerProcessRestartPhaseA();
    case 'restart-b':
      return runDesktopCliPeerProcessRestartPhaseB();
    case 'restart-c':
      return runDesktopCliPeerCredentialDeletePhaseC();
    default:
      throw StateError('Restart requires a bound runtime invocation.');
  }
}
