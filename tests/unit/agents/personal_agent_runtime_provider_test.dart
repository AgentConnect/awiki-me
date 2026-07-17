import 'package:awiki_me/src/domain/entities/agent/personal_agent_runtime_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Hermes is the only enabled Personal Agent provider in MVP', () {
    expect(defaultPersonalAgentRuntimeProvider.id, 'hermes');
    expect(defaultPersonalAgentRuntimeProvider.enabled, isTrue);
    expect(PersonalAgentRuntimeProviders.enabled, [
      PersonalAgentRuntimeProviders.hermes,
    ]);
  });

  test('future providers are schema-expressible but unavailable', () {
    expect(PersonalAgentRuntimeProviders.byId('codex')?.enabled, isFalse);
    expect(PersonalAgentRuntimeProviders.byId('claude_code')?.enabled, isFalse);
    expect(
      PersonalAgentRuntimeProviders.byId('claude-code'),
      PersonalAgentRuntimeProviders.claudeCode,
    );
    expect(
      PersonalAgentRuntimeProviders.byRuntime('codex-cli'),
      PersonalAgentRuntimeProviders.codex,
    );
    expect(
      PersonalAgentRuntimeProviders.byRuntime('claude-code'),
      PersonalAgentRuntimeProviders.claudeCode,
    );
    expect(PersonalAgentRuntimeProviders.codex.disabledReason, isNotEmpty);
    expect(PersonalAgentRuntimeProviders.claudeCode.disabledReason, isNotEmpty);
  });

  test('Hermes metadata preserves bootstrap and runtime compatibility', () {
    const provider = PersonalAgentRuntimeProviders.hermes;

    expect(provider.runtime, 'hermes');
    expect(provider.runtimeProfile, 'personal_agent');
    expect(provider.runtimeDisplayName, 'Hermes Personal Agent');
    expect(provider.capabilityLabel, 'Hermes message runtime');
    expect(provider.matchesRuntime(' Hermes '), isTrue);
    expect(provider.matchesRuntimeProfile('personal_agent'), isTrue);
    expect(provider.matchesRuntimeProfile('message_agent'), isTrue);
    expect(provider.matchesHandle('hermes-msg-app-default'), isTrue);
  });
}
