import 'package:awiki_me/src/domain/entities/agent/acp_session.dart';
import 'package:awiki_me/src/presentation/agents/acp_task_status.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'acp_responsive_test.dart' show acpSurface;
import 'acp_runtime_test.dart' show RecordingControl, snapshot;

void main() {
  for (final mode in ['controller', 'member', 'offline', 'busy']) {
    testWidgets('group recovery respects $mode and preserves group scope', (
      tester,
    ) async {
      final service = RecordingControl();
      final session = AcpSession.parse({
        ...snapshot(group: true),
        'session_key': 'group-session',
        'active': mode == 'busy' ? {'run_id': 'running'} : {},
        'waiting': {},
        'context_lost': true,
      })!;
      await tester.pumpWidget(
        acpSurface(
          AcpContextRecovery(
            session: session,
            agentName: 'Coder',
            canControl: mode != 'member',
            online: mode != 'offline',
          ),
          service: service,
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(
        const ValueKey('acp-reset_context:group-session'),
      );
      expect(find.byKey(const Key('acp-model-menu')), findsNothing);
      if (mode == 'member') {
        expect(button, findsNothing);
        expect(
          find.text('Ask this agent’s controller to start a new context.'),
          findsOneWidget,
        );
      } else if (mode != 'controller') {
        expect(tester.widget<CupertinoButton>(button).onPressed, isNull);
      } else {
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(service.requests, isEmpty);
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(service.requests.single['args'], {
          'session_key': 'group-session',
          'revision': 1,
          'action': 'reset_context',
          'confirmed': true,
        });
      }
      if (mode != 'controller') expect(service.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('multiple group recovery notices scroll at large text size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = RecordingControl();
    await tester.pumpWidget(
      acpSurface(
        Column(
          children: [
            SizedBox(
              height: 136,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < 3; i++)
                      AcpContextRecovery(
                        session: AcpSession.parse({
                          ...snapshot(group: true),
                          'session_key': 'group-$i',
                          'active': {},
                          'waiting': {},
                          'context_lost': true,
                        })!,
                        agentName: 'A long agent name $i',
                      ),
                  ],
                ),
              ),
            ),
            const CupertinoTextField(placeholder: 'Draft'),
          ],
        ),
        scale: 3,
        service: service,
      ),
    );
    await tester.pumpAndSettle();
    final last = find.byKey(const ValueKey('acp-reset_context:group-2'));
    await tester.ensureVisible(last);
    await tester.tap(last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Confirm'));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect((service.requests.single['args'] as Map)['session_key'], 'group-2');
    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
