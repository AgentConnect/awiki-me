const personalAgentProviderHermesId = 'hermes';
const personalAgentProviderHermesRuntime = 'hermes';
const personalAgentProviderHermesRuntimeProfile = 'personal_agent';
const legacyPersonalAgentRuntimeProfile = 'message_agent';
const personalAgentProviderHermesDisplayLabel = 'Hermes';
const personalAgentProviderHermesRuntimeDisplayName = 'Hermes Personal Agent';
const legacyPersonalAgentRuntimeDisplayName = 'Hermes Message Agent';
const legacyPersonalAgentChineseDisplayMarker = '消息处理';
const personalAgentProviderHermesCapabilityLabel = 'Hermes message runtime';
const personalAgentProviderHermesHandlePrefix = 'hermes-personal';
const legacyPersonalAgentProviderHermesHandlePrefix = 'hermes-msg';

const personalAgentProviderCodexId = 'codex';
const personalAgentProviderClaudeCodeId = 'claude_code';

class PersonalAgentRuntimeProvider {
  const PersonalAgentRuntimeProvider({
    required this.id,
    required this.runtime,
    required this.runtimeProfile,
    required this.displayLabel,
    required this.runtimeDisplayName,
    required this.capabilityLabel,
    required this.handlePrefix,
    required this.enabled,
    this.driverId,
    this.disabledReason,
    this.runtimeAliases = const <String>[],
    this.handleAliases = const <String>[],
  });

  final String id;
  final String runtime;
  final String runtimeProfile;
  final String displayLabel;
  final String runtimeDisplayName;
  final String capabilityLabel;
  final String handlePrefix;
  final bool enabled;
  final String? driverId;
  final String? disabledReason;
  final List<String> runtimeAliases;
  final List<String> handleAliases;

  bool matchesRuntime(String? candidate) {
    final normalized = normalizePersonalAgentProviderKey(candidate);
    if (normalized == null) {
      return false;
    }
    return normalized == normalizePersonalAgentProviderKey(id) ||
        normalized == normalizePersonalAgentProviderKey(runtime) ||
        runtimeAliases
            .map(normalizePersonalAgentProviderKey)
            .whereType<String>()
            .contains(normalized);
  }

  bool matchesHandle(String? candidate) {
    final normalized = candidate?.trim().toLowerCase();
    return normalized != null &&
        <String>[handlePrefix, ...handleAliases].any(
          (prefix) => normalized.startsWith('$prefix-'),
        );
  }

  bool matchesRuntimeProfile(String? candidate) {
    final normalized = normalizePersonalAgentProviderKey(candidate);
    return normalized == normalizePersonalAgentProviderKey(runtimeProfile) ||
        normalized ==
            normalizePersonalAgentProviderKey(
              legacyPersonalAgentRuntimeProfile,
            );
  }
}

const defaultPersonalAgentRuntimeProvider =
    PersonalAgentRuntimeProviders.hermes;

abstract final class PersonalAgentRuntimeProviders {
  static const hermes = PersonalAgentRuntimeProvider(
    id: personalAgentProviderHermesId,
    runtime: personalAgentProviderHermesRuntime,
    runtimeProfile: personalAgentProviderHermesRuntimeProfile,
    displayLabel: personalAgentProviderHermesDisplayLabel,
    runtimeDisplayName: personalAgentProviderHermesRuntimeDisplayName,
    capabilityLabel: personalAgentProviderHermesCapabilityLabel,
    handlePrefix: personalAgentProviderHermesHandlePrefix,
    handleAliases: <String>[legacyPersonalAgentProviderHermesHandlePrefix],
    enabled: true,
  );

  static const codex = PersonalAgentRuntimeProvider(
    id: personalAgentProviderCodexId,
    runtime: 'generic-cli',
    runtimeProfile: personalAgentProviderHermesRuntimeProfile,
    displayLabel: 'Codex',
    runtimeDisplayName: 'Codex Personal Agent',
    capabilityLabel: 'Codex message runtime',
    handlePrefix: 'codex-msg',
    enabled: false,
    driverId: 'codex',
    disabledReason: 'Codex Personal Agent is not available yet',
    runtimeAliases: <String>['codex', 'codex-cli'],
  );

  static const claudeCode = PersonalAgentRuntimeProvider(
    id: personalAgentProviderClaudeCodeId,
    runtime: 'generic-cli',
    runtimeProfile: personalAgentProviderHermesRuntimeProfile,
    displayLabel: 'Claude Code',
    runtimeDisplayName: 'Claude Code Personal Agent',
    capabilityLabel: 'Claude Code message runtime',
    handlePrefix: 'claude-msg',
    enabled: false,
    driverId: 'claude-code',
    disabledReason: 'Claude Code Personal Agent is not available yet',
    runtimeAliases: <String>['claude-code', 'claude_code'],
  );

  static const all = <PersonalAgentRuntimeProvider>[hermes, codex, claudeCode];

  static const enabled = <PersonalAgentRuntimeProvider>[hermes];

  static PersonalAgentRuntimeProvider? byId(String? id) {
    final normalized = normalizePersonalAgentProviderKey(id);
    if (normalized == null) {
      return null;
    }
    for (final provider in all) {
      if (normalizePersonalAgentProviderKey(provider.id) == normalized) {
        return provider;
      }
    }
    return null;
  }

  static PersonalAgentRuntimeProvider? byRuntime(String? runtime) {
    for (final provider in all) {
      if (provider.matchesRuntime(runtime)) {
        return provider;
      }
    }
    return null;
  }
}

String? normalizePersonalAgentProviderKey(String? value) {
  final normalized = value?.trim().toLowerCase().replaceAll('-', '_');
  return normalized == null || normalized.isEmpty ? null : normalized;
}
