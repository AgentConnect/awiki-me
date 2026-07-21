import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/ports/skill_onboarding_port.dart';
import 'package:awiki_me/src/domain/entities/agent/skill_onboarding_instruction.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/skill_onboarding_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
          serviceOrigin: 'https://awiki.info',
          expiresAt: DateTime.utc(2026, 7, 21, 12, 30),
        ),
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
            expectedControllerDid: 'did:wba:awiki.info:user:alice',
            expectedControllerHandle: 'alice.awiki.info',
            now: () => DateTime.utc(2026, 7, 21, 12),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'controller keeps the instruction in memory and clears on session change',
    () async {
      final port = _FakeSkillOnboardingPort();
      final container = ProviderContainer(
        overrides: <Override>[
          awikiEnvironmentConfigProvider.overrideWithValue(
            AwikiEnvironmentConfig(
              baseUrl: 'https://awiki.info',
              didDomain: 'awiki.info',
            ),
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

      await container.read(skillOnboardingProvider.notifier).generate();

      expect(port.calls, 1);
      expect(port.controllerDid, 'did:wba:awiki.info:user:alice');
      expect(port.controllerHandle, 'alice.awiki.info');
      expect(container.read(skillOnboardingProvider).instruction, isNotNull);

      container.read(sessionProvider.notifier).clear();
      expect(container.read(skillOnboardingProvider).instruction, isNull);
    },
  );

  test(
    'controller rejects non-domestic tenant before issuing a token',
    () async {
      final port = _FakeSkillOnboardingPort();
      final container = ProviderContainer(
        overrides: <Override>[
          awikiEnvironmentConfigProvider.overrideWithValue(
            AwikiEnvironmentConfig(
              baseUrl: 'https://awiki.ai',
              didDomain: 'awiki.ai',
            ),
          ),
          skillOnboardingPortProvider.overrideWithValue(port),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:wba:awiki.ai:user:alice',
              credentialName: 'alice',
              displayName: 'Alice',
              handle: 'alice.awiki.ai',
            ),
          );

      await container.read(skillOnboardingProvider.notifier).generate();

      expect(port.calls, 0);
      expect(
        container.read(skillOnboardingProvider).error,
        SkillOnboardingError.unsupportedTenant,
      );
    },
  );
}

class _FakeSkillOnboardingPort implements SkillOnboardingPort {
  int calls = 0;
  String? controllerDid;
  String? controllerHandle;

  @override
  Future<SkillOnboardingGrant> issueSkillToken({
    required String controllerDid,
    required String controllerHandle,
    required String clientPlatform,
  }) async {
    calls += 1;
    this.controllerDid = controllerDid;
    this.controllerHandle = controllerHandle;
    return SkillOnboardingGrant(
      token: 'awsk1_unit_test_secret_value',
      tokenId: 'agtok_skill_$calls',
      controllerHandle: controllerHandle,
      agentHandle: 'skill-test-$calls.awiki.info',
      serviceOrigin: 'https://awiki.info',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
    );
  }
}
