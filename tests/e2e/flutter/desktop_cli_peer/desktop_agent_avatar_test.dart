import 'desktop_cli_peer_e2e.dart';

void main() => runDesktopCliPeerE2e(
  selectedCase: DesktopCliPeerIntegrationCase.agentAvatars,
  description:
      'Owned agent avatar preset cancel GIF upload and reset with the real backend',
);
