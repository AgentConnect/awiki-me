import 'dart:io';
import 'dart:ui' as ui;

import 'package:awiki_me/src/domain/entities/agent/acp_session.dart';
import 'package:awiki_me/src/presentation/agents/acp_session_provider.dart';
import 'package:awiki_me/src/presentation/agents/acp_task_status.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'acp_runtime_test.dart' show RecordingControl, snapshot, control;
import 'acp_presentation_test.dart' show question;

const captureKey = Key('acp-render-capture');

Future<void> loadAcpFonts() async {
  final reviewFont = Platform.environment['AWIKI_ACP_REVIEW_FONT'];
  if (reviewFont != null) {
    await (FontLoader('AwikiGoldenCjk')..addFont(
          File(reviewFont).readAsBytes().then((b) => ByteData.sublistView(b)),
        ))
        .load();
  }
  for (final font in [
    if (reviewFont == null)
      ('AwikiGoldenCjk', 'assets/fonts/awiki_golden_cjk.ttf'),
    (
      'packages/cupertino_icons/CupertinoIcons',
      'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    ),
  ]) {
    await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
  }
}

Future<void> captureAcp(WidgetTester tester, String name) async {
  final root = Platform.environment['AWIKI_ACP_UI_ARTIFACTS'];
  if (root == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(root).create(recursive: true);
    await File('$root/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Widget acpSurface(
  Widget child, {
  double scale = 1,
  RecordingControl? service,
  double? keyboard,
  bool useSystemFont = false,
}) {
  final theme = AwikiMeTheme.forPlatform(
    defaultTargetPlatform,
    fontFamilyOverride: useSystemFont ? null : 'AwikiGoldenCjk',
  );
  return ProviderScope(
    overrides: [
      acpControlServiceProvider.overrideWithValue(
        service ?? RecordingControl(),
      ),
    ],
    child: RepaintBoundary(
      key: captureKey,
      child: CupertinoApp(
        theme: theme.cupertinoTheme,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => Theme(
          data: theme.materialTheme,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: keyboard == null
                  ? null
                  : EdgeInsets.only(bottom: keyboard),
            ),
            child: child!,
          ),
        ),
        home: CupertinoPageScaffold(child: SafeArea(child: child)),
      ),
    ),
  );
}

Map<String, Object?> richQuestion() => question({})
  ..['request'] = {
    ...acpMap(question({})['request']),
    'message': '继续之前，请确认这次调整的范围。我们会保留你的聊天记录，请选择合适的实施方式，并补充任何需要注意的要求。',
    'requestedSchema': {
      'type': 'object',
      'required': ['approach', 'platforms'],
      'properties': {
        'approach': {
          'type': 'string',
          'title': '选择实施方式',
          'oneOf': [
            {
              'const': 'staged',
              'title': '分阶段实施，先验证核心流程，再逐步扩展到所有客户端和设备。',
              'description': '保留现有聊天记录与附件，完成验证后再继续。',
            },
            {'const': 'together', 'title': '一次完成所有变更，并为每个平台分别执行完整验证。'},
          ],
        },
        'platforms': {
          'type': 'array',
          'title': '验证哪些平台？',
          'minItems': 1,
          'maxItems': 2,
          'items': {
            'anyOf': [
              {'const': 'mobile', 'title': '手机与平板 / Mobile and tablet'},
              {'const': 'desktop', 'title': '桌面端 / Desktop'},
            ],
          },
        },
        'notes': {
          'type': 'string',
          'title': '补充要求',
          'description': '可以补充时间安排、限制条件或需要保留的行为。',
        },
      },
    },
  };

void main() {
  setUpAll(loadAcpFonts);
  testWidgets(
    'all task states and context recovery fit a small phone with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = RecordingControl();
      final session = AcpSession.parse({
        ...snapshot(),
        'active': {},
        'waiting_paused': true,
      })!;
      for (final state in [
        'waiting',
        'stopping',
        'cancelled',
        'interrupted',
        'failed',
        'finished',
      ]) {
        await tester.pumpWidget(
          acpSurface(
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AcpTaskStatus(
                  session: session,
                  task: {'run_id': 'b', 'state': state},
                  viewerDid: 'did:alice',
                  alignEnd: true,
                ),
              ),
            ),
            scale: 3,
            service: service,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: state);
      }
      final lost = AcpSession.parse({
        ...snapshot(),
        'active': {},
        'waiting': {},
        'context_lost': true,
      })!;
      await tester.pumpWidget(
        acpSurface(
          SingleChildScrollView(child: AcpSessionOptions(session: lost)),
          scale: 3,
          service: service,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start again'));
      await tester.tap(find.text('Start again'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('ACP long form at ${size.width}x${size.height} text $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = RecordingControl();
        final q = richQuestion();
        final session = AcpSession.parse({
          ...snapshot(),
          'text': '',
          'questions': [q],
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
            scale: scale,
            service: service,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final option = find.byKey(const ValueKey('acp-option:approach:0'));
        await tester.ensureVisible(option);
        await tester.pumpAndSettle();
        final rect = tester.getRect(option);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.height, greaterThanOrEqualTo(44));
        await tester.tap(option);
        await tester.pump();
        if (size.height > 500 && scale <= 2) {
          // Return to the question's beginning for visual review.
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, 1800),
          );
          await tester.pumpAndSettle();
          await captureAcp(
            tester,
            'question-${size.width.toInt()}-${scale.toInt()}',
          );
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('acp-option:platforms:0')),
        );
        await tester.tap(find.byKey(const ValueKey('acp-option:platforms:0')));
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('acp-field:notes')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('acp-field:notes')),
          '请保留原有记录。',
        );
        await tester.pump();
        await tester.ensureVisible(find.text('Submit answer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Submit answer'));
        await tester.pump();
        expect(service.requests, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(1200, 800),
  ]) {
    testWidgets(
      'custom model picker supports long names search and keyboard at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = RecordingControl();
        final session = AcpSession.parse({
          ...snapshot(),
          'active': {},
          'waiting': {},
          'model_id': 'model-0',
          'models': [
            for (var i = 0; i < 12; i++)
              {
                'id': 'model-$i',
                'name': 'Model $i · 适合复杂任务与长上下文的模型名称',
                'description': '完整显示模型说明，可根据任务选择。文字较多时也不会截断或挤压选择按钮。',
              },
          ],
        })!;
        await tester.pumpWidget(
          acpSurface(
            AcpSessionOptions(session: session),
            scale: 2,
            service: service,
          ),
        );
        await tester.tap(find.byKey(const Key('acp-model-menu')));
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoActionSheet), findsNothing);
        expect(find.byKey(const Key('acp-model-picker')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureAcp(tester, 'models-${size.width.toInt()}-2');
        await tester.ensureVisible(find.byKey(const Key('acp-model-search')));
        await tester.enterText(
          find.byKey(const Key('acp-model-search')),
          'Model 11',
        );
        await tester.pumpAndSettle();
        tester.view.viewInsets = FakeViewPadding(
          bottom: size.height > 500 ? 260 : 120,
        );
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final row = find.byKey(const ValueKey('acp-model:model-11'));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(acpMap(service.requests.single['args'])['model_id'], 'model-11');
        expect(find.byKey(const Key('acp-model-picker')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('open model picker observes a task becoming busy', (
    tester,
  ) async {
    final service = RecordingControl();
    final idle = {
      ...snapshot(),
      'active': {},
      'waiting': {},
      'models': [
        {'id': 'm', 'name': 'Model'},
      ],
    };
    await tester.pumpWidget(
      acpSurface(
        AcpSessionOptions(session: AcpSession.parse(idle)!),
        service: service,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AcpSessionOptions)),
    );
    await tester.tap(find.byKey(const Key('acp-model-menu')));
    await tester.pumpAndSettle();
    container
        .read(acpSessionsProvider.notifier)
        .applyConversation(
          control({
            ...idle,
            'revision': 2,
            'active': {'run_id': 'new-task'},
          }),
          'conversation-1',
        );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model').last);
    await tester.pump();
    expect(service.requests, isEmpty);
    expect(find.textContaining('Finish the active'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
