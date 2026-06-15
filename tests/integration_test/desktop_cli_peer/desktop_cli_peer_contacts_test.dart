import 'desktop_cli_peer_e2e.dart';

void main() {
  runDesktopCliPeerE2e(
    selectedCase: DesktopCliPeerIntegrationCase.contacts,
    description: 'Desktop App and CLI peer cover contact relationship basics',
  );
}
