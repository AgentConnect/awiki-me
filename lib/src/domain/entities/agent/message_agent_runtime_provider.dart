const messageAgentProviderHermesId = 'hermes';
const messageAgentProviderHermesRuntime = 'hermes';
const messageAgentProviderHermesRuntimeProfile = 'message_agent';
const messageAgentProviderHermesDisplayLabel = 'Hermes';
const messageAgentProviderHermesRuntimeDisplayName = 'Hermes Message Agent';
const messageAgentProviderHermesCapabilityLabel = 'Hermes message runtime';
const messageAgentProviderHermesHandlePrefix = 'hermes-msg';

const messageAgentProviderCodexId = 'codex';
const messageAgentProviderClaudeCodeId = 'claude_code';

class MessageAgentRuntimeProvider {
  const MessageAgentRuntimeProvider({
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

  bool matchesRuntime(String? candidate) {
    final normalized = normalizeMessageAgentProviderKey(candidate);
    if (normalized == null) {
      return false;
    }
    return normalized == normalizeMessageAgentProviderKey(id) ||
        normalized == normalizeMessageAgentProviderKey(runtime) ||
        runtimeAliases
            .map(normalizeMessageAgentProviderKey)
            .whereType<String>()
            .contains(normalized);
  }

  bool matchesHandle(String? candidate) {
    final normalized = candidate?.trim().toLowerCase();
    return normalized != null && normalized.startsWith('$handlePrefix-');
  }
}

const defaultMessageAgentRuntimeProvider = MessageAgentRuntimeProviders.hermes;

abstract final class MessageAgentRuntimeProviders {
  static const hermes = MessageAgentRuntimeProvider(
    id: messageAgentProviderHermesId,
    runtime: messageAgentProviderHermesRuntime,
    runtimeProfile: messageAgentProviderHermesRuntimeProfile,
    displayLabel: messageAgentProviderHermesDisplayLabel,
    runtimeDisplayName: messageAgentProviderHermesRuntimeDisplayName,
    capabilityLabel: messageAgentProviderHermesCapabilityLabel,
    handlePrefix: messageAgentProviderHermesHandlePrefix,
    enabled: true,
  );

  static const codex = MessageAgentRuntimeProvider(
    id: messageAgentProviderCodexId,
    runtime: 'generic-cli',
    runtimeProfile: messageAgentProviderHermesRuntimeProfile,
    displayLabel: 'Codex',
    runtimeDisplayName: 'Codex Message Agent',
    capabilityLabel: 'Codex message runtime',
    handlePrefix: 'codex-msg',
    enabled: false,
    driverId: 'codex',
    disabledReason: 'Codex Message Agent 尚未开放',
    runtimeAliases: <String>['codex', 'codex-cli'],
  );

  static const claudeCode = MessageAgentRuntimeProvider(
    id: messageAgentProviderClaudeCodeId,
    runtime: 'generic-cli',
    runtimeProfile: messageAgentProviderHermesRuntimeProfile,
    displayLabel: 'Claude Code',
    runtimeDisplayName: 'Claude Code Message Agent',
    capabilityLabel: 'Claude Code message runtime',
    handlePrefix: 'claude-msg',
    enabled: false,
    driverId: 'claude-code',
    disabledReason: 'Claude Code Message Agent 尚未开放',
    runtimeAliases: <String>['claude-code', 'claude_code'],
  );

  static const all = <MessageAgentRuntimeProvider>[hermes, codex, claudeCode];

  static const enabled = <MessageAgentRuntimeProvider>[hermes];

  static MessageAgentRuntimeProvider? byId(String? id) {
    final normalized = normalizeMessageAgentProviderKey(id);
    if (normalized == null) {
      return null;
    }
    for (final provider in all) {
      if (normalizeMessageAgentProviderKey(provider.id) == normalized) {
        return provider;
      }
    }
    return null;
  }

  static MessageAgentRuntimeProvider? byRuntime(String? runtime) {
    for (final provider in all) {
      if (provider.matchesRuntime(runtime)) {
        return provider;
      }
    }
    return null;
  }
}

String? normalizeMessageAgentProviderKey(String? value) {
  final normalized = value?.trim().toLowerCase().replaceAll('-', '_');
  return normalized == null || normalized.isEmpty ? null : normalized;
}
