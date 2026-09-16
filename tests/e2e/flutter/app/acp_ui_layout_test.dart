// Native rendering/interaction smoke with injected ACP states and a recording
// transport. This does not attest a real daemon or model call.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:awiki_me/src/domain/entities/agent/acp_session.dart';
import 'package:awiki_me/src/presentation/agents/acp_task_status.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../../unit/acp_responsive_test.dart'
    show acpSurface, richQuestion, captureKey;
import '../../../unit/acp_runtime_test.dart' show snapshot, RecordingControl;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native ACP question and model picker retain complete input', (
    tester,
  ) async {
    final service = RecordingControl();
    final session = AcpSession.parse({
      ...snapshot(),
      'text': '',
      'questions': [richQuestion()],
    })!;
    await tester.pumpWidget(
      acpSurface(
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AcpTaskStatus(
              session: session,
              task: session.taskFor({'message-a'})!,
              viewerDid: 'did:alice',
              alignEnd: true,
            ),
          ),
        ),
        service: service,
        useSystemFont: true,
      ),
    );
    await tester.pumpAndSettle();
    await _capture(tester, 'question');
    for (final key in [
      'acp-option:approach:0',
      'acp-option:platforms:0',
      'acp-option:platforms:1',
    ]) {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
    }
    final input = find.byKey(const ValueKey('acp-field:notes'));
    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    await tester.enterText(input, '保留聊天记录，并验证手机和桌面。');
    await tester.pumpAndSettle();
    await _capture(tester, 'text-input');
    await tester.ensureVisible(find.text('Submit answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit answer'));
    await tester.pumpAndSettle();
    expect(
      acpMap(acpMap(service.requests.single['args'])['response'])['content'],
      {
        'approach': 'staged',
        'platforms': ['mobile', 'desktop'],
        'notes': '保留聊天记录，并验证手机和桌面。',
      },
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final idle = AcpSession.parse({
      ...snapshot(),
      'active': {},
      'waiting': {},
      'model_id': 'm0',
      'models': [
        for (var i = 0; i < 9; i++)
          {
            'id': 'm$i',
            'name': 'Model $i · 长上下文',
            'description': '适合需要多轮工具调用、图片理解和复杂文本处理的任务。',
          },
      ],
    })!;
    await tester.pumpWidget(
      acpSurface(
        AcpSessionOptions(session: idle),
        service: service,
        useSystemFont: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acp-model-menu')));
    await tester.pumpAndSettle();
    await _capture(tester, 'model-picker');
    await tester.enterText(
      find.byKey(const Key('acp-model-search')),
      'Model 8',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('acp-model:m8')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('acp-model:m8')));
    await tester.pumpAndSettle();
    expect(acpMap(service.requests.last['args'])['model_id'], 'm8');
    expect(find.byKey(const Key('acp-model-picker')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${Directory.systemTemp.path}/awiki-acp-native-$name.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
  debugPrint('ACP native screenshot: ${file.path}');
}
