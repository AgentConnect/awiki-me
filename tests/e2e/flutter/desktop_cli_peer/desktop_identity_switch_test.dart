import 'desktop_cli_peer_e2e.dart';

void main() {
  runDesktopCliPeerE2e(
    selectedCase: DesktopCliPeerIntegrationCase.identitySwitch,
    description:
        'Desktop App preserves exact messages across local identity switches',
  );
}
