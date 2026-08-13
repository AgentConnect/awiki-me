// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

import 'package:awiki_me/src/application/ports/remote_push_sync_port.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_message_v1.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/agent_urgent_overlay_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/remote_push_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

const _session = SessionIdentity(
  did: 'did:test:me',
  credentialName: 'default',
  displayName: 'Me',
  localIdentityId: 'identity-1',
  accountBinding: SessionAccountBinding(
    ownerIdentityId: 'identity-1',
    accountId: 'account-1',
    currentDid: 'did:test:me',
    protocolDeviceId: 'device-1',
    identityGeneration: '3',
    deviceAuthGeneration: '7',
  ),
);

const _urgentAlert = AgentMessageV1(
  eventId: 'evt_task_20260811_001',
  taskName: 'Production worker recovery',
  kind: AgentMessageKind.alert,
  level: AgentMessageLevel.urgent,
  summary: 'Review needed',
  detail: null,
  action: AgentMessageAction.openConversation,
);

void main() {
  testWidgets(
    'single root overlay does not replace, acts through canonical navigation, and clears on fence mismatch',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const conversationId = 'dm:peer-scope:v1:agent';
      final navigation = _FakeRemotePushNavigation();
      final notifications = FakeNotificationFacade();
      late WidgetRef widgetRef;
      await tester.pumpWidget(
        buildLocalizedTestApp(
          session: _session,
          providerOverrides: <Override>[
            remotePushNavigationPortProvider.overrideWithValue(navigation),
            notificationFacadeProvider.overrideWithValue(notifications),
          ],
          home: Consumer(
            builder: (context, ref, child) {
              widgetRef = ref;
              return const Stack(
                fit: StackFit.expand,
                children: <Widget>[SizedBox.expand(), AgentUrgentOverlayHost()],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fence = AgentUrgentOverlaySessionFence.capture(
        widgetRef.read(sessionProvider),
      )!;
      final navigationContext = RemotePushSessionContext(
        storageScopeId: widgetRef.read(activeAppTenantProvider).storageScopeId,
        ownerDid: fence.epoch.ownerDid,
        generation: fence.epoch.generation,
      );
      final controller = widgetRef.read(agentUrgentOverlayProvider.notifier);
      expect(
        controller.tryShow(
          AgentUrgentOverlayState(
            fence: fence,
            navigationContext: navigationContext,
            conversationId: conversationId,
            senderLabel: 'Agent One',
            message: _urgentAlert,
            authoritativeReceivedAt: DateTime.utc(2026, 8, 11, 9, 16),
          ),
        ),
        isTrue,
      );
      expect(
        controller.tryShow(
          AgentUrgentOverlayState(
            fence: fence,
            navigationContext: navigationContext,
            conversationId: conversationId,
            senderLabel: 'Agent Two',
            message: const AgentMessageV1(
              eventId: 'evt_task_20260811_002',
              taskName: 'Replacement attempt',
              kind: AgentMessageKind.alert,
              level: AgentMessageLevel.urgent,
              summary: 'Must not replace',
              detail: null,
              action: AgentMessageAction.openConversation,
            ),
          ),
        ),
        isFalse,
      );
      await tester.pump();
      expect(
        find.byKey(const Key('agent-urgent-callout-overlay')),
        findsOneWidget,
      );
      expect(find.text('Review needed'), findsOneWidget);
      expect(find.text('Production worker recovery'), findsOneWidget);
      expect(find.text('Agent One'), findsOneWidget);
      expect(find.byKey(const Key('agent-urgent-task-name')), findsOneWidget);
      expect(find.text('Must not replace'), findsNothing);
      expect(find.text('Replacement attempt'), findsNothing);

      await tester.tap(find.byKey(const Key('agent-urgent-act')));
      await tester.pumpAndSettle();
      expect(navigation.calls, <String>[
        'show_conversation_list',
        'open:$conversationId',
      ]);
      expect(widgetRef.read(agentUrgentOverlayProvider), isNull);
      expect(notifications.urgentCueStopCalls, 1);

      expect(
        controller.tryShow(
          AgentUrgentOverlayState(
            fence: fence,
            navigationContext: navigationContext,
            conversationId: conversationId,
            senderLabel: 'Agent One',
            message: _urgentAlert,
          ),
        ),
        isTrue,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('agent-urgent-ignore')));
      await tester.pumpAndSettle();
      expect(widgetRef.read(agentUrgentOverlayProvider), isNull);
      expect(notifications.urgentCueStopCalls, 2);

      expect(
        controller.tryShow(
          AgentUrgentOverlayState(
            fence: fence,
            navigationContext: navigationContext,
            conversationId: conversationId,
            senderLabel: 'Agent One',
            message: _urgentAlert,
          ),
        ),
        isTrue,
      );
      await tester.pump();
      widgetRef.read(sessionProvider.notifier).clear();
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('agent-urgent-callout-overlay')),
        findsNothing,
      );
      expect(widgetRef.read(agentUrgentOverlayProvider), isNull);
      expect(notifications.urgentCueStopCalls, 3);
    },
  );

  test('controller rejects non-alert and non-urgent states', () {
    final session = SessionController()..setSession(_session);
    final fence = AgentUrgentOverlaySessionFence.capture(session.state)!;
    final navigationContext = RemotePushSessionContext(
      storageScopeId: StorageScopeId.parse(
        '44444444-4444-4444-8444-444444444444',
      ),
      ownerDid: fence.epoch.ownerDid,
      generation: fence.epoch.generation,
    );
    final controller = AgentUrgentOverlayController();
    addTearDown(controller.dispose);

    for (final message in <AgentMessageV1>[
      const AgentMessageV1(
        eventId: 'normal-alert',
        taskName: 'Normal alert task',
        kind: AgentMessageKind.alert,
        level: AgentMessageLevel.normal,
        summary: 'Normal',
        detail: null,
        action: AgentMessageAction.openConversation,
      ),
      const AgentMessageV1(
        eventId: 'urgent-task',
        taskName: 'Urgent result task',
        kind: AgentMessageKind.taskResult,
        level: AgentMessageLevel.urgent,
        summary: 'Task',
        detail: null,
        action: AgentMessageAction.openConversation,
      ),
    ]) {
      expect(
        controller.tryShow(
          AgentUrgentOverlayState(
            fence: fence,
            navigationContext: navigationContext,
            conversationId: 'conversation-1',
            senderLabel: 'Agent',
            message: message,
          ),
        ),
        isFalse,
      );
    }
    expect(controller.state, isNull);
  });

  test(
    'session fence rejects default device and non-canonical generations',
    () {
      for (final binding in <SessionAccountBinding>[
        const SessionAccountBinding(
          ownerIdentityId: 'identity-1',
          accountId: 'account-1',
          currentDid: 'did:test:me',
          protocolDeviceId: 'default',
          identityGeneration: '3',
          deviceAuthGeneration: '7',
        ),
        const SessionAccountBinding(
          ownerIdentityId: 'identity-1',
          accountId: 'account-1',
          currentDid: 'did:test:me',
          protocolDeviceId: 'device-1',
          identityGeneration: '03',
          deviceAuthGeneration: '7',
        ),
        const SessionAccountBinding(
          ownerIdentityId: 'identity-1',
          accountId: 'account-1',
          currentDid: 'did:test:me',
          protocolDeviceId: 'device-1',
          identityGeneration: '3',
          deviceAuthGeneration: '0',
        ),
      ]) {
        final controller = SessionController()
          ..setSession(
            SessionIdentity(
              did: 'did:test:me',
              credentialName: 'default',
              displayName: 'Me',
              localIdentityId: 'identity-1',
              accountBinding: binding,
            ),
          );
        expect(
          AgentUrgentOverlaySessionFence.capture(controller.state),
          isNull,
        );
        controller.dispose();
      }
    },
  );
}

final class _FakeRemotePushNavigation implements RemotePushNavigationPort {
  final List<String> calls = <String>[];

  @override
  Future<void> showConversationList(RemotePushSessionContext context) async {
    calls.add('show_conversation_list');
  }

  @override
  Future<void> openConversation(
    RemotePushSessionContext context,
    String conversationId,
  ) async {
    calls.add('open:$conversationId');
  }
}
