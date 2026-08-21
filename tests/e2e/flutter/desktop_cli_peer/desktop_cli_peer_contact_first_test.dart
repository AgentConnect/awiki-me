import 'desktop_cli_peer_e2e.dart';

void main() {
  runDesktopCliPeerE2e(
    selectedCase: DesktopCliPeerIntegrationCase.contactFirst,
    description:
        'Desktop App opens one canonical conversation from contact first',
  );
}
