// One process registers exactly one existing suite; imports never run its main.
import 'dart:io';
import 'package:awiki_me/src/app/e2e_fault_hooks.dart';
import 'package:awiki_me/src/app/e2e_build_metadata.dart';
import '../runtime_control/invocation.dart';
import '../runtime_control/shared_host_contract.dart';
import 'app/registration_domain_discovery_test.dart'
    as registration_domain_discovery;
import 'desktop_cli_peer/desktop_agent_avatar_test.dart' as agent_avatars;
import 'desktop_cli_peer/desktop_avatar_test.dart' as avatars;
import 'app/app_smoke_test.dart' as smoke_app;
import 'native/im_core_open_smoke_test.dart' as smoke_core;
import 'desktop_cli_peer/desktop_cli_peer_smoke_test.dart' as messaging;
import 'desktop_cli_peer/desktop_cli_peer_direct_test.dart' as direct;
import 'desktop_cli_peer/desktop_cli_peer_group_test.dart' as group;
import 'desktop_cli_peer/desktop_cli_peer_attachment_test.dart' as attachment;
import 'desktop_cli_peer/desktop_cli_peer_contacts_test.dart' as contacts;
import 'desktop_cli_peer/desktop_cli_peer_contact_first_test.dart'
    as contact_first;
import 'desktop_cli_peer/desktop_cli_peer_inbound_test.dart' as inbound;
import 'desktop_cli_peer/desktop_identity_switch_test.dart' as identity_switch;
import 'desktop_cli_peer/desktop_cli_peer_display_name_fallback_test.dart'
    as display_name_fallback;
import 'desktop_cli_peer/desktop_cli_peer_performance_test.dart' as performance;
import 'app/multi_device_capability_gate_test.dart' as multi_device;
import 'app/multi_device_join_ui_test.dart' as pair;
import 'app/handle_recovery_ui_test.dart' as recovery;
import 'desktop_cli_peer/desktop_cli_peer_e2e.dart' as restart;
import 'app/personal_agent_full_ui_test.dart' as personal_agent;
import 'app/registration_account_first_test.dart' as registration_account_first;
import 'app/hosted_gateway_join_ui_test.dart' as hosted_gateway_join;
import 'app/hosted_gateway_resume_ui_test.dart' as hosted_gateway_resume;

Map<SharedHostEntry, void Function()> sharedDesktopHostHandlers(
  E2eInvocation invocation,
) => {
  SharedHostEntry.registrationDomainDiscovery:
      registration_domain_discovery.main,
  SharedHostEntry.agentAvatars: agent_avatars.main,
  SharedHostEntry.avatars: avatars.main,
  SharedHostEntry.smokeApp: smoke_app.main,
  SharedHostEntry.smokeCore: smoke_core.main,
  SharedHostEntry.messaging: messaging.main,
  SharedHostEntry.direct: direct.main,
  SharedHostEntry.group: group.main,
  SharedHostEntry.attachment: attachment.main,
  SharedHostEntry.contacts: contacts.main,
  SharedHostEntry.contactFirst: contact_first.main,
  SharedHostEntry.inbound: inbound.main,
  SharedHostEntry.identitySwitch: identity_switch.main,
  SharedHostEntry.displayNameFallback: display_name_fallback.main,
  SharedHostEntry.performance: performance.main,
  SharedHostEntry.multiDevice: multi_device.main,
  SharedHostEntry.remoteJoin: pair.main,
  SharedHostEntry.appPairAdmin: pair.appPairAdminMain,
  SharedHostEntry.appPairJoiner: pair.appPairJoinerMain,
  SharedHostEntry.recovery: recovery.main,
  SharedHostEntry.restart: () {
    switch (invocation.mode.phase) {
      case 'restart-a':
        return restart.runDesktopCliPeerProcessRestartPhaseA();
      case 'restart-b':
        return restart.runDesktopCliPeerProcessRestartPhaseB();
      case 'restart-c':
        return restart.runDesktopCliPeerCredentialDeletePhaseC();
      default:
        throw const FormatException('Unknown restart phase.');
    }
  },
  SharedHostEntry.personalAgent: personal_agent.realBackendMain,
  SharedHostEntry.registrationAccountFirst: registration_account_first.main,
  SharedHostEntry.hostedGatewayJoin: hosted_gateway_join.main,
  SharedHostEntry.hostedGatewayResume: hosted_gateway_resume.main,
};

void main() {
  if (!e2eFaultHooksEnabled) {
    throw StateError('Shared test hosts require a non-Release E2E build.');
  }
  final invocation = E2eInvocation.load(Platform.environment);
  if (invocation == null) {
    throw const FormatException(
      'Shared desktop host requires a bound invocation.',
    );
  }
  const slot = String.fromEnvironment('AWIKI_E2E_HOST_SLOT');
  if (sharedHostSlot(invocation.artifact) != slot) {
    throw const FormatException('Invocation selected the wrong host.');
  }
  if (invocation.artifact.startsWith('hosted-gateway-')) {
    e2eBuildMetadata.useLegacyHostedRelease();
  }
  dispatchSharedHost(
    artifact: invocation.artifact,
    compiledSlot: slot,
    handlers: sharedDesktopHostHandlers(invocation),
  );
}
