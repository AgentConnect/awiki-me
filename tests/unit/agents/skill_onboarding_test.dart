import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/models/onboarding_server_info.dart';
import 'package:awiki_me/src/application/ports/skill_onboarding_port.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:awiki_me/src/domain/entities/agent/skill_onboarding_instruction.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/skill_onboarding_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support.dart';

const _enabledCapability = SkillOnboardingCapability(
  enabled: true,
  protocolVersion: skillOnboardingProtocolVersion,
  onboardingPath: skillOnboardingDocumentPath,
  displayNameBinding: skillOnboardingDisplayNameBinding,
);

void main() {
  test(
    'prompt is domestic, scoped, redacted in diagnostics, and contains token once',
    () {
      const rawToken = 'awsk1_unit_test_secret_value';
      final instruction = buildSkillOnboardingInstruction(
        grant: SkillOnboardingGrant(
          token: rawToken,
          tokenId: 'agtok_skill_1',
          controllerHandle: 'alice.awiki.info',
          agentHandle: 'skill-test.awiki.info',
          displayName: 'Research Copilot',
          serviceOrigin: 'https://awiki.info',
          expiresAt: DateTime.utc(2026, 7, 21, 12, 30),
        ),
        capability: _enabledCapability,
        expectedServiceOrigin: 'https://awiki.info',
        expectedControllerDid: 'did:wba:awiki.info:user:alice',
        expectedControllerHandle: '@Alice.AWIKI.INFO',
        now: () => DateTime.utc(2026, 7, 21, 12),
      );

      expect(
        instruction.prompt,
        contains('https://awiki.info/cli/onboarding.md'),
      );
      expect(instruction.prompt, contains('AWIKI_SKILL_ONBOARDING_V1'));
      expect(
        instruction.prompt,
        contains('controller_handle=alice.awiki.info'),
      );
      expect(
        instruction.prompt,
        contains('agent_handle=skill-test.awiki.info'),
      );
      expect(rawToken.allMatches(instruction.prompt), hasLength(1));
      expect(instruction.prompt, isNot(contains('awiki.ai')));
      expect(
        instruction.prompt,
        isNot(contains('did:wba:awiki.info:user:alice')),
      );
      expect(instruction.prompt, isNot(contains('user_id')));
      expect(instruction.prompt, isNot(contains('--token')));
      expect(instruction.displayName, 'Research Copilot');
      expect(
        instruction.prompt,
        contains('automatic follow of its controller'),
      );
      expect(instruction.toString(), isNot(contains(rawToken)));
    },
  );

  test(
    'prompt builder fails closed for foreign origin or mismatched handle',
    () {
      SkillOnboardingGrant grant({
        String origin = 'https://awiki.info',
        String controller = 'alice.awiki.info',
      }) => SkillOnboardingGrant(
        token: 'awsk1_unit_test_secret_value',
        tokenId: 'agtok_skill_1',
        controllerHandle: controller,
        agentHandle: 'skill-test.awiki.info',
        displayName: 'Research Copilot',
        serviceOrigin: origin,
        expiresAt: DateTime.utc(2026, 7, 21, 12, 30),
      );

      for (final value in <SkillOnboardingGrant>[
        grant(origin: 'https://awiki.ai'),
        grant(controller: 'mallory.awiki.info'),
      ]) {
        expect(
          () => buildSkillOnboardingInstruction(
            grant: value,
            capability: _enabledCapability,
            expectedServiceOrigin: 'https://awiki.info',
            expectedControllerDid: 'did:wba:awiki.info:user:alice',
            expectedControllerHandle: 'alice.awiki.info',
            now: () => DateTime.utc(2026, 7, 21, 12),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('prompt builder accepts the advertised anpclaw.com tenant', () {
    final instruction = buildSkillOnboardingInstruction(
      grant: SkillOnboardingGrant(
        token: 'awsk1_anpclaw_test_secret',
        tokenId: 'agtok_skill_anpclaw',
        controllerHandle: 'newhandle1.anpclaw.com',
        agentHandle: 'skill-test.anpclaw.com',
        displayName: 'Research Copilot',
        serviceOrigin: 'https://anpclaw.com',
        expiresAt: DateTime.utc(2026, 7, 30, 13),
      ),
      capability: _enabledCapability,
      expectedServiceOrigin: 'https://anpclaw.com',
      expectedControllerDid:
          'did:wba:anpclaw.com:user:newhandle1:e1_controller',
      expectedControllerHandle: 'newhandle1.anpclaw.com',
      now: () => DateTime.utc(2026, 7, 30, 12),
    );

    expect(
      instruction.prompt,
      contains('https://anpclaw.com/cli/onboarding.md'),
    );
    expect(
      instruction.prompt,
      contains('service_base_url=https://anpclaw.com'),
    );
    expect(instruction.prompt, contains('agent_handle=skill-test.anpclaw.com'));
  });

  test('prompt builder rejects disabled or malformed capabilities', () {
    final grant = SkillOnboardingGrant(
      token: 'awsk1_unit_test_secret_value',
      tokenId: 'agtok_skill_1',
      controllerHandle: 'alice.awiki.info',
      agentHandle: 'skill-test.awiki.info',
      displayName: 'Research Copilot',
      serviceOrigin: 'https://awiki.info',
      expiresAt: DateTime.utc(2026, 7, 21, 12, 30),
    );

    for (final capability in <SkillOnboardingCapability>[
      const SkillOnboardingCapability.disabled(),
      const SkillOnboardingCapability(
        enabled: true,
        protocolVersion: 2,
        onboardingPath: skillOnboardingDocumentPath,
      ),
      const SkillOnboardingCapability(
        enabled: true,
        protocolVersion: skillOnboardingProtocolVersion,
        onboardingPath: 'https://example.com/onboarding.md',
      ),
      const SkillOnboardingCapability(
        enabled: true,
        protocolVersion: skillOnboardingProtocolVersion,
        onboardingPath: skillOnboardingDocumentPath,
      ),
    ]) {
      expect(
        () => buildSkillOnboardingInstruction(
          grant: grant,
          capability: capability,
          expectedServiceOrigin: 'https://awiki.info',
          expectedControllerDid: 'did:wba:awiki.info:user:alice',
          expectedControllerHandle: 'alice.awiki.info',
          now: () => DateTime.utc(2026, 7, 21, 12),
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'controller keeps the instruction in memory and clears on session change',
    () async {
      final port = _FakeSkillOnboardingPort();
      final gateway = FakeAwikiGateway()..serverInfo = _skillServerInfo();
      final container = ProviderContainer(
        overrides: <Override>[
          awikiEnvironmentConfigProvider.overrideWithValue(
            AwikiEnvironmentConfig(
              baseUrl: 'https://awiki.info',
              didDomain: 'awiki.info',
            ),
          ),
          onboardingSupportServiceProvider.overrideWithValue(
            FakeOnboardingSupportService(gateway),
          ),
          skillOnboardingPortProvider.overrideWithValue(port),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:wba:awiki.info:user:alice',
              credentialName: 'alice',
              displayName: 'Alice',
              handle: 'alice.awiki.info',
            ),
          );

      await container
          .read(skillOnboardingProvider.notifier)
          .generate(displayName: 'Research Copilot');

      expect(port.calls, 1);
      expect(port.controllerDid, 'did:wba:awiki.info:user:alice');
      expect(port.controllerHandle, 'alice.awiki.info');
      expect(port.displayName, 'Research Copilot');
      expect(container.read(skillOnboardingProvider).instruction, isNotNull);

      container.read(sessionProvider.notifier).clear();
      expect(container.read(skillOnboardingProvider).instruction, isNull);
    },
  );

  test(
    'controller issues a token for the advertised Singapore tenant',
    () async {
      final port = _FakeSkillOnboardingPort(domain: 'anpclaw.com');
      final gateway = FakeAwikiGateway()..serverInfo = _skillServerInfo();
      final container = ProviderContainer(
        overrides: <Override>[
          awikiEnvironmentConfigProvider.overrideWithValue(
            AwikiEnvironmentConfig(
              baseUrl: 'https://anpclaw.com',
              didDomain: 'anpclaw.com',
            ),
          ),
          onboardingSupportServiceProvider.overrideWithValue(
            FakeOnboardingSupportService(gateway),
          ),
          skillOnboardingPortProvider.overrideWithValue(port),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:wba:anpclaw.com:user:newhandle1:e1_controller',
              credentialName: 'newhandle1',
              displayName: 'newhandle1',
              handle: 'newhandle1.anpclaw.com',
            ),
          );

      await container
          .read(skillOnboardingProvider.notifier)
          .generate(displayName: 'Research Copilot');

      expect(container.read(skillOnboardingProvider).error, isNull);
      expect(container.read(skillOnboardingProvider).instruction, isNotNull);
    },
  );

  test(
    'controller rejects a server without display-name binding before issue',
    () async {
      final port = _FakeSkillOnboardingPort();
      final gateway = FakeAwikiGateway()
        ..serverInfo = _skillServerInfo(displayNameBinding: false);
      final container = ProviderContainer(
        overrides: <Override>[
          awikiEnvironmentConfigProvider.overrideWithValue(
            AwikiEnvironmentConfig(
              baseUrl: 'https://awiki.info',
              didDomain: 'awiki.info',
            ),
          ),
          onboardingSupportServiceProvider.overrideWithValue(
            FakeOnboardingSupportService(gateway),
          ),
          skillOnboardingPortProvider.overrideWithValue(port),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:wba:awiki.info:user:alice',
              credentialName: 'alice',
              displayName: 'Alice',
              handle: 'alice.awiki.info',
            ),
          );

      await container
          .read(skillOnboardingProvider.notifier)
          .generate(displayName: 'Research Copilot');

      expect(port.calls, 0);
      expect(
        container.read(skillOnboardingProvider).error,
        SkillOnboardingError.serverUpgradeRequired,
      );
    },
  );

  test(
    'controller rejects an untrusted tenant before capability discovery',
    () async {
      final port = _FakeSkillOnboardingPort(domain: 'example.com');
      final gateway = FakeAwikiGateway()..serverInfo = _skillServerInfo();
      final container = ProviderContainer(
        overrides: <Override>[
          awikiEnvironmentConfigProvider.overrideWithValue(
            AwikiEnvironmentConfig(
              baseUrl: 'https://example.com',
              didDomain: 'example.com',
            ),
          ),
          onboardingSupportServiceProvider.overrideWithValue(
            FakeOnboardingSupportService(gateway),
          ),
          skillOnboardingPortProvider.overrideWithValue(port),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:wba:example.com:user:alice',
              credentialName: 'alice',
              displayName: 'Alice',
              handle: 'alice.example.com',
            ),
          );

      await container
          .read(skillOnboardingProvider.notifier)
          .generate(displayName: 'Research Copilot');

      expect(port.calls, 0);
      expect(gateway.loadServerInfoCalls, 0);
      expect(
        container.read(skillOnboardingProvider).error,
        SkillOnboardingError.unsupportedTenant,
      );
    },
  );

  test(
    'controller rejects a trusted tenant that has not enabled Skill',
    () async {
      final port = _FakeSkillOnboardingPort(domain: 'anpclaw.com');
      final gateway = FakeAwikiGateway()
        ..serverInfo = _skillServerInfo(enabled: false);
      final container = ProviderContainer(
        overrides: <Override>[
          awikiEnvironmentConfigProvider.overrideWithValue(
            AwikiEnvironmentConfig(baseUrl: 'https://anpclaw.com'),
          ),
          onboardingSupportServiceProvider.overrideWithValue(
            FakeOnboardingSupportService(gateway),
          ),
          skillOnboardingPortProvider.overrideWithValue(port),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:wba:anpclaw.com:user:alice',
              credentialName: 'alice',
              displayName: 'Alice',
              handle: 'alice.anpclaw.com',
            ),
          );

      await container
          .read(skillOnboardingProvider.notifier)
          .generate(displayName: 'Research Copilot');

      expect(gateway.loadServerInfoCalls, 1);
      expect(port.calls, 0);
      expect(
        container.read(skillOnboardingProvider).error,
        SkillOnboardingError.unsupportedTenant,
      );
    },
  );

  test('session changes cancel an in-flight capability request', () async {
    final port = _FakeSkillOnboardingPort(domain: 'anpclaw.com');
    final capability = Completer<OnboardingServerInfo>();
    final gateway = FakeAwikiGateway()..serverInfoCompleter = capability;
    final container = ProviderContainer(
      overrides: <Override>[
        awikiEnvironmentConfigProvider.overrideWithValue(
          AwikiEnvironmentConfig(baseUrl: 'https://anpclaw.com'),
        ),
        onboardingSupportServiceProvider.overrideWithValue(
          FakeOnboardingSupportService(gateway),
        ),
        skillOnboardingPortProvider.overrideWithValue(port),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:wba:anpclaw.com:user:alice',
            credentialName: 'alice',
            displayName: 'Alice',
            handle: 'alice.anpclaw.com',
          ),
        );

    final pending = container
        .read(skillOnboardingProvider.notifier)
        .generate(displayName: 'Research Copilot');
    await Future<void>.delayed(Duration.zero);
    container.read(sessionProvider.notifier).clear();
    capability.complete(_skillServerInfo());
    await pending;

    expect(port.calls, 0);
    expect(container.read(skillOnboardingProvider).isLoading, isFalse);
    expect(container.read(skillOnboardingProvider).instruction, isNull);
  });

  test('a server-side rollout race maps to unsupported tenant', () async {
    final port = _FakeSkillOnboardingPort(
      domain: 'anpclaw.com',
      error: const AwikiOnboardingUtilityError(
        rpcCode: -32001,
        message: 'disabled',
        data: <String, Object?>{
          'reason': 'skill_onboarding_capability_disabled',
        },
      ),
    );
    final gateway = FakeAwikiGateway()..serverInfo = _skillServerInfo();
    final container = ProviderContainer(
      overrides: <Override>[
        awikiEnvironmentConfigProvider.overrideWithValue(
          AwikiEnvironmentConfig(baseUrl: 'https://anpclaw.com'),
        ),
        onboardingSupportServiceProvider.overrideWithValue(
          FakeOnboardingSupportService(gateway),
        ),
        skillOnboardingPortProvider.overrideWithValue(port),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:wba:anpclaw.com:user:alice',
            credentialName: 'alice',
            displayName: 'Alice',
            handle: 'alice.anpclaw.com',
          ),
        );

    await container
        .read(skillOnboardingProvider.notifier)
        .generate(displayName: 'Research Copilot');

    expect(
      container.read(skillOnboardingProvider).error,
      SkillOnboardingError.unsupportedTenant,
    );
  });

  test('regeneration limit preserves the current usable instruction', () async {
    final port = _FakeSkillOnboardingPort(domain: 'anpclaw.com');
    final gateway = FakeAwikiGateway()..serverInfo = _skillServerInfo();
    final container = ProviderContainer(
      overrides: <Override>[
        awikiEnvironmentConfigProvider.overrideWithValue(
          AwikiEnvironmentConfig(baseUrl: 'https://anpclaw.com'),
        ),
        onboardingSupportServiceProvider.overrideWithValue(
          FakeOnboardingSupportService(gateway),
        ),
        skillOnboardingPortProvider.overrideWithValue(port),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:wba:anpclaw.com:user:alice',
            credentialName: 'alice',
            displayName: 'Alice',
            handle: 'alice.anpclaw.com',
          ),
        );

    await container
        .read(skillOnboardingProvider.notifier)
        .generate(displayName: 'Research Copilot');
    final original = container.read(skillOnboardingProvider).instruction;
    expect(original, isNotNull);

    port.error = const AwikiOnboardingUtilityError(
      rpcCode: -32004,
      message: 'active token limit',
      data: <String, Object?>{'reason': 'skill_onboarding_active_token_limit'},
    );
    await container
        .read(skillOnboardingProvider.notifier)
        .generate(displayName: 'Research Copilot');

    final state = container.read(skillOnboardingProvider);
    expect(state.error, SkillOnboardingError.activeTokenLimit);
    expect(state.instruction, same(original));
    expect(port.calls, 2);
  });
}

OnboardingServerInfo _skillServerInfo({
  bool enabled = true,
  bool displayNameBinding = true,
}) {
  final base = OnboardingServerInfo.userServiceDefault();
  return OnboardingServerInfo(
    schemaVersion: base.schemaVersion,
    service: base.service,
    identity: base.identity,
    agents: OnboardingAgentCapabilities(
      skillOnboarding: enabled
          ? SkillOnboardingCapability(
              enabled: true,
              protocolVersion: skillOnboardingProtocolVersion,
              onboardingPath: skillOnboardingDocumentPath,
              displayNameBinding: displayNameBinding
                  ? skillOnboardingDisplayNameBinding
                  : '',
            )
          : const SkillOnboardingCapability.disabled(),
    ),
  );
}

class _FakeSkillOnboardingPort implements SkillOnboardingPort {
  _FakeSkillOnboardingPort({this.domain = 'awiki.info', this.error});

  final String domain;
  Object? error;
  int calls = 0;
  String? controllerDid;
  String? controllerHandle;
  String? displayName;

  @override
  Future<SkillOnboardingGrant> issueSkillToken({
    required String controllerDid,
    required String controllerHandle,
    required String displayName,
    required String clientPlatform,
  }) async {
    calls += 1;
    if (error != null) {
      throw error!;
    }
    this.controllerDid = controllerDid;
    this.controllerHandle = controllerHandle;
    this.displayName = displayName;
    return SkillOnboardingGrant(
      token: 'awsk1_unit_test_secret_value',
      tokenId: 'agtok_skill_$calls',
      controllerHandle: controllerHandle,
      agentHandle: 'skill-test-$calls.$domain',
      displayName: displayName,
      serviceOrigin: 'https://$domain',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
    );
  }
}
