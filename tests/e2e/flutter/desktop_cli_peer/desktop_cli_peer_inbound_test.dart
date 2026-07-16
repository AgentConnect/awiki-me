import 'desktop_cli_peer_e2e.dart';

void main() {
  runDesktopCliPeerE2e(
    selectedCase: DesktopCliPeerIntegrationCase.inboundFirst,
    description:
        'Desktop App creates one Direct from the first inbound message',
  );
}
