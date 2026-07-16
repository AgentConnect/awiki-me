import 'desktop_cli_peer_e2e.dart';

void main() {
  runDesktopCliPeerE2e(
    selectedCase: DesktopCliPeerIntegrationCase.displayNameFallback,
    description:
        'Desktop App uses one full-Handle fallback across all peer surfaces',
  );
}
