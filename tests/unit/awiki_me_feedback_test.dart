import 'package:awiki_me/src/presentation/shared/awiki_me_feedback.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('danger toast exposes selectable text without copy button', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Builder(
          builder: (context) {
            return CupertinoButton(
              onPressed: () {
                AwikiMeToast.show(
                  context,
                  'gateway_error: failed',
                  danger: true,
                );
              },
              child: const Text('show'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('gateway_error: failed'), findsOneWidget);
    expect(find.text('复制'), findsNothing);

    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets('danger toast can reveal and copy long error details', (
    tester,
  ) async {
    String? clipboardText;
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'Clipboard.setData') {
            final data = methodCall.arguments as Map<Object?, Object?>;
            clipboardText = data['text'] as String?;
          }
          return null;
        });

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Builder(
          builder: (context) {
            return CupertinoButton(
              onPressed: () {
                AwikiMeToast.show(
                  context,
                  '附件无法打开',
                  danger: true,
                  detail:
                      'android.os.FileUriExposedException: file:///tmp/a.md\n'
                      '#0 stack frame',
                );
              },
              child: const Text('show'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();

    expect(find.text('附件无法打开'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);

    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();

    expect(find.text('错误详情'), findsOneWidget);
    expect(find.textContaining('FileUriExposedException'), findsOneWidget);
    expect(find.text('复制详情'), findsOneWidget);

    await tester.tap(find.text('复制详情'));
    await tester.pumpAndSettle();
    expect(clipboardText, contains('FileUriExposedException'));
    expect(find.text('已复制'), findsOneWidget);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets('error detail dialog closes with Escape', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Builder(
          builder: (context) {
            return CupertinoButton(
              onPressed: () {
                showAwikiMeErrorDetailDialog(
                  context,
                  message: '请求失败',
                  detail: 'transport unavailable',
                );
              },
              child: const Text('show'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.text('错误详情'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('错误详情'), findsNothing);
  });

  testWidgets('error detail dialog closes when tapping the dimmed backdrop', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Builder(
          builder: (context) {
            return CupertinoButton(
              onPressed: () {
                showAwikiMeErrorDetailDialog(
                  context,
                  message: '请求失败',
                  detail: 'transport unavailable',
                );
              },
              child: const Text('show'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.text('错误详情'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('错误详情'), findsNothing);
  });

  testWidgets('info toast stays passive and non-selectable', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Builder(
          builder: (context) {
            return CupertinoButton(
              onPressed: () {
                AwikiMeToast.show(context, '已复制');
              },
              child: const Text('show'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();

    expect(find.byType(SelectionArea), findsNothing);
    expect(find.text('已复制'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('danger persistent toast exposes selectable text', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const Stack(
          children: <Widget>[
            AwikiMePersistentToast(
              message: 'realtime failed',
              danger: true,
              bottom: 24,
            ),
          ],
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('realtime failed'), findsOneWidget);
  });

  testWidgets('error notice renders selectable message and optional action', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AwikiMeErrorNotice(
          message: '智能体信息暂时无法加载',
          trailing: Text('重试'),
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('智能体信息暂时无法加载'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
