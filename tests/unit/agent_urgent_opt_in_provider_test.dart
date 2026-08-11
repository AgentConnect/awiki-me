import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/agent_message_presentation_store.dart';
import 'package:awiki_me/src/application/models/agent_notification_preference.dart';
import 'package:awiki_me/src/application/ports/agent_notification_preference_port.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/agent_urgent_opt_in_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  test('provider is fail-closed without an exact account binding', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        productLocalStoreProvider.overrideWithValue(
          InMemoryAwikiProductLocalStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:test:owner',
            credentialName: 'owner',
            displayName: 'Owner',
          ),
        );
    final state = container.read(agentUrgentOptInProvider);
    expect(state.enabled, isFalse);
    expect(state.available, isFalse);
    expect(state.canChange, isFalse);
  });

  test(
    'provider ignores legacy local enabled state when server is unset',
    () async {
      final local = InMemoryAwikiProductLocalStore();
      final preferences = _FakePreferencePort(
        const AgentNotificationPreference(
          schema: 'awiki.agent.message.v1',
          urgent: AgentNotificationUrgentPreference.unset,
          updatedAt: null,
        ),
      );
      final container = ProviderContainer(
        overrides: <Override>[
          productLocalStoreProvider.overrideWithValue(local),
          agentNotificationPreferencePortProvider.overrideWithValue(
            preferences,
          ),
        ],
      );
      addTearDown(container.dispose);

      final owner = AgentMessagePresentationOwnerScope(
        ownerIdentityId: 'identity-owner',
        accountId: 'account-a',
      );
      await local.saveUiPreference(
        LocalUiPreference(
          ownerDid: owner.storageOwnerKey,
          key: 'agent_message_urgent_opt_in.v1',
          valueJson:
              '{"version":1,"owner_hash":"${owner.ownerHash}","enabled":true}',
          updatedAt: DateTime.utc(2026, 8, 11, 12),
        ),
      );
      container
          .read(sessionProvider.notifier)
          .setSession(_session('account-a'));
      container.read(agentUrgentOptInProvider);
      await _settleProvider();
      expect(container.read(agentUrgentOptInProvider).enabled, isFalse);
      expect(container.read(agentUrgentOptInProvider).canChange, isTrue);
    },
  );

  test(
    'provider keeps urgent disabled until a successful server acknowledgement',
    () async {
      final preferences = _FakePreferencePort(
        const AgentNotificationPreference(
          schema: 'awiki.agent.message.v1',
          urgent: AgentNotificationUrgentPreference.disabled,
          updatedAt: null,
        ),
      );
      final container = ProviderContainer(
        overrides: <Override>[
          agentNotificationPreferencePortProvider.overrideWithValue(
            preferences,
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(sessionProvider.notifier)
          .setSession(_session('account-a'));
      container.read(agentUrgentOptInProvider);
      await _settleProvider();
      await container.read(agentUrgentOptInProvider.notifier).setEnabled(true);
      expect(container.read(agentUrgentOptInProvider).enabled, isTrue);

      preferences.setError = StateError('server unavailable');
      await container.read(agentUrgentOptInProvider.notifier).setEnabled(false);
      expect(container.read(agentUrgentOptInProvider).enabled, isFalse);
      expect(container.read(agentUrgentOptInProvider).available, isFalse);
      expect(container.read(agentUrgentOptInProvider).hasError, isTrue);
    },
  );

  test(
    'late preference response cannot cross an account-session fence',
    () async {
      final first = Completer<AgentNotificationPreference>();
      final second = Completer<AgentNotificationPreference>();
      final container = ProviderContainer(
        overrides: <Override>[
          agentNotificationPreferencePortProvider.overrideWithValue(
            _QueuedPreferencePort(<Future<AgentNotificationPreference>>[
              first.future,
              second.future,
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(sessionProvider.notifier)
          .setSession(_session('account-a'));
      container.read(agentUrgentOptInProvider);
      container
          .read(sessionProvider.notifier)
          .setSession(_session('account-b'));
      container.read(agentUrgentOptInProvider);
      second.complete(
        const AgentNotificationPreference(
          schema: 'awiki.agent.message.v1',
          urgent: AgentNotificationUrgentPreference.disabled,
          updatedAt: null,
        ),
      );
      await _settleProvider();
      first.complete(
        const AgentNotificationPreference(
          schema: 'awiki.agent.message.v1',
          urgent: AgentNotificationUrgentPreference.enabled,
          updatedAt: null,
        ),
      );
      await _settleProvider();

      expect(container.read(agentUrgentOptInProvider).enabled, isFalse);
    },
  );

  testWidgets('settings exposes an off-by-default account-fenced switch', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        session: _session('account-settings'),
        providerOverrides: <Override>[
          agentNotificationPreferencePortProvider.overrideWithValue(
            _FakePreferencePort(
              const AgentNotificationPreference(
                schema: 'awiki.agent.message.v1',
                urgent: AgentNotificationUrgentPreference.disabled,
                updatedAt: null,
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(
      const Key('settings-agent-urgent-opt-in-switch'),
    );
    expect(find.text('允许 Agent 紧急呼叫'), findsOneWidget);
    expect(tester.widget<CupertinoSwitch>(switchFinder).value, isFalse);
    expect(tester.widget<CupertinoSwitch>(switchFinder).onChanged, isNotNull);

    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoSwitch>(switchFinder).value, isTrue);
  });
}

SessionIdentity _session(String accountId) => SessionIdentity(
  did: 'did:test:owner',
  credentialName: 'owner',
  displayName: 'Owner',
  accountBinding: SessionAccountBinding(
    ownerIdentityId: 'identity-owner',
    accountId: accountId,
    currentDid: 'did:test:owner',
    protocolDeviceId: 'device-1',
    identityGeneration: '1',
    deviceAuthGeneration: '2',
  ),
);

Future<void> _settleProvider() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _FakePreferencePort implements AgentNotificationPreferencePort {
  _FakePreferencePort(this.preference);

  AgentNotificationPreference preference;
  Object? getError;
  Object? setError;

  @override
  Future<AgentNotificationPreference> getAgentNotificationPreference() async {
    final error = getError;
    if (error != null) throw error;
    return preference;
  }

  @override
  Future<AgentNotificationPreference> setAgentNotificationPreference({
    required AgentNotificationUrgentPreference urgent,
  }) async {
    final error = setError;
    if (error != null) throw error;
    preference = AgentNotificationPreference(
      schema: 'awiki.agent.message.v1',
      urgent: urgent,
      updatedAt: DateTime.utc(2026, 8, 11, 12),
    );
    return preference;
  }
}

final class _QueuedPreferencePort implements AgentNotificationPreferencePort {
  _QueuedPreferencePort(this._responses);

  final List<Future<AgentNotificationPreference>> _responses;

  @override
  Future<AgentNotificationPreference> getAgentNotificationPreference() {
    if (_responses.isEmpty) throw StateError('unexpected preference read');
    return _responses.removeAt(0);
  }

  @override
  Future<AgentNotificationPreference> setAgentNotificationPreference({
    required AgentNotificationUrgentPreference urgent,
  }) => throw UnimplementedError();
}
