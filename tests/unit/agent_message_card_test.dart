import 'package:awiki_me/src/domain/entities/agent/agent_message_v1.dart';
import 'package:awiki_me/src/presentation/chat/parts/agent_message_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const message = AgentMessageV1(
    eventId: 'evt_task_20260811_001',
    taskName: '生产发布检查',
    kind: AgentMessageKind.alert,
    level: AgentMessageLevel.urgent,
    summary: '需要处理',
    detail: null,
    action: AgentMessageAction.openConversation,
  );
  const cardCopy = AgentMessageCardCopy(
    message: '消息',
    taskResult: '任务结果',
    alert: '告警',
    urgent: '紧急',
    urgentCall: '紧急呼叫',
  );
  const overlayCopy = AgentUrgentCalloutCopy(
    urgentCall: '紧急呼叫',
    back: '返回',
    trustedAgent: '可信 Agent',
    notAVoipNotice: '不会建立语音通话',
    cueStops: '铃声和振动将在 30 秒后停止',
    ignore: '忽略',
    act: '立即处理',
  );

  testWidgets(
    'Callout Strip renders urgent card and explicit overlay actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var opened = false;
      var ignored = false;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              children: <Widget>[
                AgentMessageCard(
                  message: message,
                  copy: cardCopy,
                  onOpenConversation: () => opened = true,
                ),
                AgentUrgentCalloutOverlay(
                  message: message,
                  senderLabel: 'Skill Agent',
                  copy: overlayCopy,
                  metaLabel: '刚刚 · 8月11日 09:16',
                  onIgnore: () => ignored = true,
                  onAct: () => opened = true,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('紧急呼叫'), findsNWidgets(2));
      expect(find.byKey(const Key('agent-message-task-name')), findsOneWidget);
      expect(find.byKey(const Key('agent-urgent-task-name')), findsOneWidget);
      expect(find.text('生产发布检查'), findsNWidgets(2));
      expect(find.text('Skill Agent'), findsOneWidget);
      expect(find.textContaining('事件编号'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('agent-urgent-act')),
          matching: find.byIcon(CupertinoIcons.check_mark),
        ),
        findsOneWidget,
      );
      expect(find.text('不会建立语音通话'), findsOneWidget);
      expect(
        tester
            .getSize(
              find.byKey(const Key('agent-message-card:evt_task_20260811_001')),
            )
            .height,
        lessThan(260),
      );
      await tester.tap(find.byKey(const Key('agent-urgent-ignore')));
      expect(ignored, isTrue);
      await tester.tap(find.byKey(const Key('agent-urgent-act')));
      expect(opened, isTrue);
    },
  );

  testWidgets('normal card displays the typed task name', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AgentMessageCard(
          message: AgentMessageV1(
            eventId: 'evt_task_20260811_002',
            taskName: 'AWiki Me release verification',
            kind: AgentMessageKind.taskResult,
            level: AgentMessageLevel.normal,
            summary: 'All checks passed',
            detail: null,
            action: AgentMessageAction.openConversation,
          ),
          copy: cardCopy,
          onOpenConversation: null,
        ),
      ),
    );

    expect(find.text('AWiki Me release verification'), findsOneWidget);
    expect(find.text('All checks passed'), findsOneWidget);
    expect(find.byKey(const Key('agent-message-task-name')), findsOneWidget);
    expect(find.byKey(const Key('agent-urgent-task-name')), findsNothing);
  });
}
