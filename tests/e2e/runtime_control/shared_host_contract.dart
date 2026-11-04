// Logical cases select one of two fixed native host identities. No product imports.
import 'dart:convert';
import 'package:crypto/crypto.dart';

const sharedDesktopHostTarget =
    'integration_test/shared_desktop_host_test.dart';
const sharedDesktopHostSlots = {'a', 'b'};

void validateSharedHostExecutionEnvironment(Map<String, String> environment) {
  if (environment['AWIKI_E2E_USE_FLUTTER_TEST']?.trim() == '1') {
    throw const FormatException(
      'Per-scenario Flutter compilation is disabled by the two-host policy.',
    );
  }
}

enum SharedHostEntry {
  registrationDomainDiscovery,
  agentAvatars,
  avatars,
  smokeApp,
  smokeCore,
  messaging,
  direct,
  group,
  attachment,
  contacts,
  contactFirst,
  inbound,
  identitySwitch,
  displayNameFallback,
  performance,
  multiDevice,
  remoteJoin,
  appPairAdmin,
  appPairJoiner,
  recovery,
  restart,
  personalAgent,
  registrationAccountFirst,
  hostedGatewayJoin,
  hostedGatewayResume,
}

const sharedHostEntries = <String, SharedHostEntry>{
  'registration-domain-discovery': SharedHostEntry.registrationDomainDiscovery,
  'agent-avatars': SharedHostEntry.agentAvatars,
  'avatars': SharedHostEntry.avatars,
  'smoke-app': SharedHostEntry.smokeApp,
  'smoke-core': SharedHostEntry.smokeCore,
  'messaging': SharedHostEntry.messaging,
  'direct': SharedHostEntry.direct,
  'group': SharedHostEntry.group,
  'attachment': SharedHostEntry.attachment,
  'contacts': SharedHostEntry.contacts,
  'contact-first': SharedHostEntry.contactFirst,
  'inbound': SharedHostEntry.inbound,
  'identity-switch': SharedHostEntry.identitySwitch,
  'display-name-fallback': SharedHostEntry.displayNameFallback,
  'performance': SharedHostEntry.performance,
  'multi-device': SharedHostEntry.multiDevice,
  'remote-join': SharedHostEntry.remoteJoin,
  'admin': SharedHostEntry.appPairAdmin,
  'joiner': SharedHostEntry.appPairJoiner,
  'recovery-main': SharedHostEntry.recovery,
  'recovery-crash-a': SharedHostEntry.recovery,
  'recovery-crash-b': SharedHostEntry.recovery,
  'recovery-fresh-restart': SharedHostEntry.recovery,
  'recovery-registration-resume-a': SharedHostEntry.recovery,
  'recovery-registration-resume-b': SharedHostEntry.recovery,
  'identity-deletion-a': SharedHostEntry.recovery,
  'identity-deletion-b': SharedHostEntry.recovery,
  'restart-a': SharedHostEntry.restart,
  'restart-b': SharedHostEntry.restart,
  'restart-c': SharedHostEntry.restart,
  'personal-agent': SharedHostEntry.personalAgent,
  'registration-account-first': SharedHostEntry.registrationAccountFirst,
  'hosted-gateway-join': SharedHostEntry.hostedGatewayJoin,
  'hosted-gateway-resume': SharedHostEntry.hostedGatewayResume,
};

SharedHostEntry sharedHostEntry(String artifact) =>
    sharedHostEntries[artifact] ??
    (throw const FormatException('Unknown shared desktop test scenario.'));

String sharedHostSlot(String artifact) {
  sharedHostEntry(artifact);
  return artifact == 'joiner' ? 'b' : 'a';
}

String sharedHostBundleId(String slot) {
  if (!sharedDesktopHostSlots.contains(slot)) {
    throw const FormatException('Unknown shared desktop host slot.');
  }
  return 'ai.awiki.awikime.dev.e2e.host.$slot';
}

List<String> sharedHostDefines(String slot) {
  sharedHostBundleId(slot);
  return ['AWIKI_E2E=true', 'AWIKI_E2E_HOST_SLOT=$slot'];
}

void validateSharedHostSpec({
  required String name,
  required String target,
  required String bundleId,
  required List<String> defines,
}) {
  final slot = sharedHostSlot(name);
  final expected = sharedHostDefines(slot);
  if (target != sharedDesktopHostTarget ||
      bundleId != sharedHostBundleId(slot) ||
      defines.length != expected.length ||
      !defines.toSet().containsAll(expected)) {
    throw const FormatException(
      'Shared desktop tests must use only the two declared host builds.',
    );
  }
}

void dispatchSharedHost({
  required String artifact,
  required String compiledSlot,
  required Map<SharedHostEntry, void Function()> handlers,
}) {
  final entry = sharedHostEntry(artifact);
  if (sharedHostSlot(artifact) != compiledSlot) {
    throw const FormatException(
      'Invocation does not match this native host slot.',
    );
  }
  final handler = handlers[entry];
  if (handler == null) {
    throw const FormatException('Shared desktop test entry is not installed.');
  }
  handler();
}

void validateSharedHostBuild({
  required String name,
  required String target,
  required String bundleId,
  required List<String> defines,
}) {
  if (target != sharedDesktopHostTarget) return;
  const tenantKeys = {
    'AWIKI_BUILTIN_TENANTS_BASE64',
    'AWIKI_BUILTIN_TENANTS_SHA256',
  };
  final buildDefines = defines
      .where((d) => !tenantKeys.contains(d.split('=').first))
      .toList();
  validateSharedHostSpec(
    name: name,
    target: target,
    bundleId: bundleId,
    defines: buildDefines,
  );
}

/// Preserve both current hosts during low-space pruning; names and runtime plans
/// are deliberately absent from compile identity. Other build types are unchanged.
Set<String> companionSharedHostCompileKeys(Map<String, Object?> payload) {
  if (payload['target'] != sharedDesktopHostTarget) return const {};
  final bundle = payload['bundleId'];
  final matches = sharedDesktopHostSlots.where(
    (s) => sharedHostBundleId(s) == bundle,
  );
  if (matches.length != 1) {
    throw const FormatException('Shared host compile identity is invalid.');
  }
  final slot = matches.single;
  final other = slot == 'a' ? 'b' : 'a';
  final defines = (payload['dartDefines'] as List).cast<String>();
  if (!defines.contains('AWIKI_E2E_HOST_SLOT=$slot')) {
    throw const FormatException('Host compile definition is missing.');
  }
  final otherDefines =
      defines
          .map(
            (d) => d == 'AWIKI_E2E_HOST_SLOT=$slot'
                ? 'AWIKI_E2E_HOST_SLOT=$other'
                : d,
          )
          .toList()
        ..sort();
  final companion = {
    ...payload,
    'bundleId': sharedHostBundleId(other),
    'dartDefines': otherDefines,
  };
  return {sha256.convert(utf8.encode(jsonEncode(companion))).toString()};
}
