import 'dart:io';
import 'dart:ui' as ui;

import 'package:awiki_me/src/domain/entities/agent/agent_message_v1.dart';
import 'package:awiki_me/src/presentation/chat/parts/agent_message_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _captureKey = Key('agent-notification-visual-boundary');
const _visualFontFamily = 'AwikiNotificationVisualCjk';
const _outputDirectory =
    'docs/prd/agent-notification-experience-v2-screenshots';
const _compactSize = Size(390, 844);

const _urgentMessage = AgentMessageV1(
  eventId: 'INC-2026-0811-0916',
  taskName: 'AWiki Me 生产发布',
  kind: AgentMessageKind.alert,
  level: AgentMessageLevel.urgent,
  summary: '生产服务连续 3 分钟不可用',
  detail: '请尽快查看当前对话并处理',
  action: AgentMessageAction.openConversation,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final cjkBytes = await File(
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    ).readAsBytes();
    await (FontLoader(
      _visualFontFamily,
    )..addFont(Future<ByteData>.value(ByteData.sublistView(cjkBytes)))).load();
    final iconBytes = await rootBundle.load(
      'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    );
    await (FontLoader(
      'CupertinoIcons',
    )..addFont(Future<ByteData>.value(iconBytes))).load();
    await (FontLoader(
      'packages/cupertino_icons/CupertinoIcons',
    )..addFont(Future<ByteData>.value(iconBytes))).load();
  });

  testWidgets('urgent callout matches the approved compact visual state', (
    tester,
  ) async {
    try {
      await _setSurface(tester, _compactSize);
      await tester.pumpWidget(
        _testApp(
          const Stack(
            children: <Widget>[
              AgentUrgentCalloutOverlay(
                message: _urgentMessage,
                senderLabel: 'Skill Agent',
                copy: AgentUrgentCalloutCopy(
                  urgentCall: '紧急呼叫',
                  back: '返回',
                  trustedAgent: '可信 Agent',
                  notAVoipNotice: '紧急通知，不会建立语音通话',
                  cueStops: '铃声和振动将在 30 秒后停止',
                  ignore: '忽略',
                  act: '立即处理',
                ),
                metaLabel: '刚刚 · 8月11日 09:16',
                onIgnore: _noop,
                onAct: _noop,
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('agent-urgent-callout-overlay')), findsOne);
      expect(find.byKey(const Key('agent-urgent-task-name')), findsOne);
      expect(find.text('AWiki Me 生产发布'), findsOne);
      expect(find.byKey(const Key('agent-urgent-ignore')), findsOne);
      expect(find.byKey(const Key('agent-urgent-act')), findsOne);
      expect(tester.takeException(), isNull);
      await _capture(tester, '04-urgent-fullscreen');
    } finally {
      await _resetSurface(tester);
    }
  });

  testWidgets('urgent timeline card has no ordinary bubble wrapper', (
    tester,
  ) async {
    try {
      await _setSurface(tester, _compactSize);
      await tester.pumpWidget(
        _testApp(
          const Center(
            child: SizedBox(
              width: 310,
              child: AgentMessageCard(
                message: _urgentMessage,
                timeLabel: '09:16',
                copy: AgentMessageCardCopy(
                  message: '消息',
                  taskResult: '任务结果',
                  alert: '告警',
                  urgent: '紧急',
                  urgentCall: '紧急呼叫',
                ),
                onOpenConversation: null,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('agent-message-card:INC-2026-0811-0916')),
        findsOne,
      );
      expect(find.byKey(const Key('agent-message-task-name')), findsOne);
      expect(find.text('AWiki Me 生产发布'), findsOne);
      expect(find.textContaining('事件编号'), findsNothing);
      expect(tester.takeException(), isNull);
      await _capture(tester, '03-urgent-timeline-card');
    } finally {
      await _resetSurface(tester);
    }
  });
}

Widget _testApp(Widget child) => CupertinoApp(
  debugShowCheckedModeBanner: false,
  theme: const CupertinoThemeData(
    textTheme: CupertinoTextThemeData(
      textStyle: TextStyle(fontFamily: _visualFontFamily),
      actionTextStyle: TextStyle(fontFamily: _visualFontFamily),
      actionSmallTextStyle: TextStyle(fontFamily: _visualFontFamily),
      navTitleTextStyle: TextStyle(fontFamily: _visualFontFamily),
      navLargeTitleTextStyle: TextStyle(fontFamily: _visualFontFamily),
      navActionTextStyle: TextStyle(fontFamily: _visualFontFamily),
    ),
  ),
  home: RepaintBoundary(
    key: _captureKey,
    child: DefaultTextStyle(
      style: const TextStyle(fontFamily: _visualFontFamily),
      child: SizedBox.expand(child: child),
    ),
  ),
);

Future<void> _setSurface(WidgetTester tester, Size size) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
}

Future<void> _resetSurface(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = null;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = byteData!.buffer.asUint8List();
  final outputRoot =
      Platform.environment['AWIKI_NOTIFICATION_VISUAL_OUTPUT_DIR'] ??
      _outputDirectory;
  final golden = File('$outputRoot/$name.png');
  if (autoUpdateGoldenFiles) {
    await golden.parent.create(recursive: true);
    await golden.writeAsBytes(bytes, flush: true);
  } else {
    expect(
      golden.existsSync(),
      isTrue,
      reason: 'Missing notification visual baseline.',
    );
    expect(
      bytes,
      orderedEquals(await golden.readAsBytes()),
      reason: '$name changed and requires visual review.',
    );
  }
  image.dispose();
}

void _noop() {}
