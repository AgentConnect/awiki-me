import 'package:awiki_me/src/domain/entities/agent/agent_terminal_notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> payload({
    String eventId = 'evt_run_terminal:run_1:completed',
    String state = 'finished',
    String? outcome = 'completed',
    String summary = '任务已完成',
    String? nextStep,
    String? finalMessageId = 'msg_final_1',
  }) => <String, Object?>{
    'schema': 'awiki.agent.status.v1',
    'event_id': eventId,
    'run_id': 'run_1',
    'state': state,
    if (outcome != null) 'business_outcome': outcome,
    'summary': summary,
    'next_step': nextStep,
    'final_message_id': finalMessageId,
  };

  group('AgentTerminalNotification', () {
    test('maps all provider-neutral business outcomes', () {
      final completed = AgentTerminalNotification.fromStatusPayload(payload());
      final blocked = AgentTerminalNotification.fromStatusPayload(
        payload(eventId: 'evt_blocked', outcome: 'blocked', nextStep: '补充访问权限'),
      );
      final actionRequired = AgentTerminalNotification.fromStatusPayload(
        payload(
          eventId: 'evt_action',
          outcome: 'action_required',
          nextStep: '确认是否继续',
        ),
      );

      expect(completed?.kind, AgentTerminalKind.completed);
      expect(completed?.summary, '任务已完成');
      expect(completed?.finalMessageId, 'msg_final_1');
      expect(blocked?.kind, AgentTerminalKind.blocked);
      expect(blocked?.nextStep, '补充访问权限');
      expect(actionRequired?.kind, AgentTerminalKind.actionRequired);
    });

    test('maps a real runtime failure without inventing a business result', () {
      final notification = AgentTerminalNotification.fromStatusPayload(
        payload(
          eventId: 'evt_failed',
          state: 'failed',
          outcome: null,
          finalMessageId: null,
        ),
      );

      expect(notification?.kind, AgentTerminalKind.runtimeFailed);
      expect(notification?.summary, isNull);
    });

    test('accepts compatible fields from the first run item', () {
      final notification = AgentTerminalNotification.fromStatusPayload(
        <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'event_id': 'evt_nested',
          'runs': <Object?>[
            <String, Object?>{
              'run_id': 'run_nested',
              'status': 'finished',
              'business_outcome': 'completed',
              'summary': '任务已完成',
              'final_message_id': 'msg_nested',
            },
          ],
        },
      );

      expect(notification?.runId, 'run_nested');
      expect(notification?.kind, AgentTerminalKind.completed);
    });

    test('running and malformed or unknown terminal payloads fail closed', () {
      expect(
        AgentTerminalNotification.fromStatusPayload(payload(state: 'running')),
        isNull,
      );
      expect(
        AgentTerminalNotification.fromStatusPayload(
          payload(outcome: 'needs_help'),
        ),
        isNull,
      );
      expect(
        AgentTerminalNotification.fromStatusPayload(<String, Object?>{
          'schema': 'awiki.agent.status.v1',
        }),
        isNull,
      );
    });

    test('unsafe, oversize, and incomplete notification text fails closed', () {
      expect(
        AgentTerminalNotification.fromStatusPayload(
          payload(summary: 'token=do-not-show'),
        ),
        isNull,
      );
      expect(
        AgentTerminalNotification.fromStatusPayload(
          payload(summary: '检查路径=/srv/private/main.rs'),
        ),
        isNull,
      );
      expect(
        AgentTerminalNotification.fromStatusPayload(
          payload(summary: '```dart source code ```'),
        ),
        isNull,
      );
      expect(
        AgentTerminalNotification.fromStatusPayload(
          payload(summary: List<String>.filled(241, 'x').join()),
        ),
        isNull,
      );
      expect(
        AgentTerminalNotification.fromStatusPayload(
          payload(outcome: 'blocked'),
        ),
        isNull,
      );
    });
  });

  group('AgentTerminalNotificationDeduplicator', () {
    test('deduplicates by run and terminal kind across replay event ids', () {
      final deduplicator = AgentTerminalNotificationDeduplicator();

      expect(deduplicator.acceptStatus(payload()), isNotNull);
      expect(
        deduplicator.acceptStatus(payload(eventId: 'evt_replayed')),
        isNull,
      );
    });

    testWidgets(
      'message-first delivery lets every semantic terminal outcome win',
      (tester) async {
        for (final entry in <(String, String?)>[
          ('completed', null),
          ('blocked', '补充访问权限'),
          ('action_required', '确认是否继续'),
        ]) {
          final deduplicator = AgentTerminalNotificationDeduplicator();
          var ordinaryNotifications = 0;
          expect(
            deduplicator.acceptRuntimeMessageIds(const <String?>[
              'msg_final_1',
            ], releaseNotification: () => ordinaryNotifications += 1),
            isTrue,
          );

          final terminal = deduplicator.acceptStatus(
            payload(
              eventId: 'evt_${entry.$1}',
              outcome: entry.$1,
              nextStep: entry.$2,
            ),
          );
          expect(terminal?.kind.name, switch (entry.$1) {
            'completed' => 'completed',
            'blocked' => 'blocked',
            _ => 'actionRequired',
          });
          await tester.pump(
            AgentTerminalNotificationDeduplicator
                .runtimeMessageCorrelationWindow,
          );
          expect(ordinaryNotifications, 0);
        }
      },
    );

    testWidgets(
      'status-first delivery suppresses its matching runtime message',
      (tester) async {
        final deduplicator = AgentTerminalNotificationDeduplicator();
        var ordinaryNotifications = 0;

        expect(deduplicator.acceptStatus(payload()), isNotNull);
        expect(
          deduplicator.acceptRuntimeMessageIds(const <String?>[
            'msg_final_1',
          ], releaseNotification: () => ordinaryNotifications += 1),
          isFalse,
        );
        await tester.pump(
          AgentTerminalNotificationDeduplicator.runtimeMessageCorrelationWindow,
        );

        expect(ordinaryNotifications, 0);
      },
    );

    testWidgets(
      'timeout releases ordinary runtime notification and wins late race',
      (tester) async {
        final deduplicator = AgentTerminalNotificationDeduplicator();
        var ordinaryNotifications = 0;
        deduplicator.acceptRuntimeMessageIds(const <String?>[
          'msg_final_1',
        ], releaseNotification: () => ordinaryNotifications += 1);

        await tester.pump(
          AgentTerminalNotificationDeduplicator.runtimeMessageCorrelationWindow,
        );
        expect(ordinaryNotifications, 1);
        expect(deduplicator.acceptStatus(payload()), isNull);
        expect(ordinaryNotifications, 1);
      },
    );

    testWidgets('clear cancels pending runtime notification timers', (
      tester,
    ) async {
      final deduplicator = AgentTerminalNotificationDeduplicator();
      var ordinaryNotifications = 0;
      deduplicator.acceptRuntimeMessageIds(const <String?>[
        'msg_final_1',
      ], releaseNotification: () => ordinaryNotifications += 1);

      deduplicator.clear();
      await tester.pump(
        AgentTerminalNotificationDeduplicator.runtimeMessageCorrelationWindow,
      );

      expect(ordinaryNotifications, 0);
    });

    testWidgets('bounds pending runtime notifications and releases oldest', (
      tester,
    ) async {
      final deduplicator = AgentTerminalNotificationDeduplicator();
      var ordinaryNotifications = 0;
      for (var index = 0; index < 65; index += 1) {
        deduplicator.acceptRuntimeMessageIds(<String?>[
          'msg_pending_$index',
        ], releaseNotification: () => ordinaryNotifications += 1);
      }

      expect(ordinaryNotifications, 1);
      await tester.pump(
        AgentTerminalNotificationDeduplicator.runtimeMessageCorrelationWindow,
      );
      expect(ordinaryNotifications, 65);
    });

    test('bounds ordinary message history to the 256 most recent ids', () {
      final deduplicator = AgentTerminalNotificationDeduplicator();
      expect(
        deduplicator.acceptMessageIds(const <String?>['msg_oldest']),
        isTrue,
      );
      for (var index = 0; index < 256; index += 1) {
        expect(
          deduplicator.acceptMessageIds(<String?>['msg_new_$index']),
          isTrue,
        );
      }

      expect(
        deduplicator.acceptMessageIds(const <String?>['msg_new_255']),
        isFalse,
      );
      expect(
        deduplicator.acceptMessageIds(const <String?>['msg_oldest']),
        isTrue,
      );
    });

    test('keeps terminal replay protection beyond the ordinary id bound', () {
      final deduplicator = AgentTerminalNotificationDeduplicator();
      expect(deduplicator.acceptStatus(payload()), isNotNull);
      for (var index = 0; index < 300; index += 1) {
        expect(
          deduplicator.acceptMessageIds(<String?>['msg_new_$index']),
          isTrue,
        );
      }

      expect(
        deduplicator.acceptStatus(payload(eventId: 'evt_late_replay')),
        isNull,
      );
      expect(
        deduplicator.acceptMessageIds(const <String?>['msg_final_1']),
        isFalse,
      );
    });
  });
}
