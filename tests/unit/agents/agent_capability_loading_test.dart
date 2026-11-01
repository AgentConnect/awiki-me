import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/agents/agent_ui_messages.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support.dart';

void main() {
  for (final supported in [true, false]) {
    test(
      'initial Agent load waits for capability support=$supported',
      () async {
        final capabilities = _DeferredCapabilities();
        final control = _CountingControl();
        final container = _container(capabilities, control);
        addTearDown(container.dispose);
        final loading = container.read(agentsProvider.notifier).ensureLoaded();
        await pumpEventQueue();
        expect(control.listCalls, 0);
        expect(container.read(agentsProvider).agents, isEmpty);
        capabilities.result.complete(
          supported ? capabilities.backendFeatureSources : {},
        );
        await loading;
        expect(control.listCalls, supported ? 1 : 0);
        if (supported) {
          expect(container.read(agentsProvider).agents, control.agents);
        } else {
          expect(
            container.read(agentsProvider).error,
            AgentUiMessageCodes.tenantUnsupported,
          );
        }
      },
    );
  }

  test(
    'capability completion cannot load inventory across a session switch',
    () async {
      final capabilities = _DeferredCapabilities();
      final control = _CountingControl();
      final container = _container(capabilities, control);
      addTearDown(container.dispose);
      final loading = container.read(agentsProvider.notifier).ensureLoaded();
      await pumpEventQueue();
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:new-owner',
              credentialName: 'new-owner',
              displayName: 'New owner',
            ),
          );
      capabilities.result.complete(capabilities.backendFeatureSources);
      await loading.timeout(const Duration(seconds: 3));
      expect(control.listCalls, 0);
      expect(container.read(agentsProvider).agents, isEmpty);
      expect(container.read(agentsProvider).error, isNull);
    },
  );
}

ProviderContainer _container(
  _DeferredCapabilities capabilities,
  _CountingControl control,
) => ProviderContainer(
  overrides: [
    ...fakeApplicationServiceOverrides(
      FakeAwikiGateway(),
      agentControlService: control,
    ),
    identityCorePortProvider.overrideWithValue(capabilities),
    sessionProvider.overrideWith(
      (ref) => SessionController()
        ..setSession(
          const SessionIdentity(
            did: 'did:owner',
            credentialName: 'owner',
            displayName: 'Owner',
          ),
        ),
    ),
  ],
);

class _DeferredCapabilities extends FakeIdentityCorePort {
  final result = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> backendCapabilities({bool force = false}) =>
      result.future;
}

class _CountingControl extends FakeAgentControlService {
  int listCalls = 0;
  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    listCalls += 1;
    return super.listAgents(includeInactive: includeInactive);
  }
}
