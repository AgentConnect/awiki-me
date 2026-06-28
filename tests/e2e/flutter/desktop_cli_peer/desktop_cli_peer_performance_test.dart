import 'desktop_cli_peer_e2e.dart';

void main() {
  runDesktopCliPeerE2e(
    selectedCase: DesktopCliPeerIntegrationCase.performance,
    description:
        'Desktop App and CLI peer meet startup conversation performance budgets',
  );
}
