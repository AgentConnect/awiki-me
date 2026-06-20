import 'package:awiki_me/src/domain/entities/agent/message_agent_runtime_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Hermes is the only enabled Message Agent provider in MVP', () {
    expect(defaultMessageAgentRuntimeProvider.id, 'hermes');
    expect(defaultMessageAgentRuntimeProvider.enabled, isTrue);
    expect(MessageAgentRuntimeProviders.enabled, [
      MessageAgentRuntimeProviders.hermes,
    ]);
  });

  test('future providers are schema-expressible but unavailable', () {
    expect(MessageAgentRuntimeProviders.byId('codex')?.enabled, isFalse);
    expect(MessageAgentRuntimeProviders.byId('claude_code')?.enabled, isFalse);
    expect(
      MessageAgentRuntimeProviders.byId('claude-code'),
      MessageAgentRuntimeProviders.claudeCode,
    );
    expect(
      MessageAgentRuntimeProviders.byRuntime('codex-cli'),
      MessageAgentRuntimeProviders.codex,
    );
    expect(
      MessageAgentRuntimeProviders.byRuntime('claude-code'),
      MessageAgentRuntimeProviders.claudeCode,
    );
    expect(MessageAgentRuntimeProviders.codex.disabledReason, isNotEmpty);
    expect(MessageAgentRuntimeProviders.claudeCode.disabledReason, isNotEmpty);
  });

  test('Hermes metadata preserves bootstrap and runtime compatibility', () {
    const provider = MessageAgentRuntimeProviders.hermes;

    expect(provider.runtime, 'hermes');
    expect(provider.runtimeProfile, 'message_agent');
    expect(provider.runtimeDisplayName, 'Hermes Message Agent');
    expect(provider.capabilityLabel, 'Hermes message runtime');
    expect(provider.matchesRuntime(' Hermes '), isTrue);
    expect(provider.matchesHandle('hermes-msg-app-default'), isTrue);
  });
}
