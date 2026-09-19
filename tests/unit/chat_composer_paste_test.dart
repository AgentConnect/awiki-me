import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/attachment_picker_service.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/shared/widgets/keyboard_dismiss_scope.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

const owner = SessionIdentity(
  did: 'did:test:owner',
  handle: 'owner',
  displayName: 'Owner',
  credentialName: 'default',
);

Widget chat(AttachmentPickerService picker) => buildLocalizedTestApp(
  session: owner,
  home: KeyboardDismissScope(
    child: CupertinoPageScaffold(
      child: ChatView(
        conversation: ConversationSummary(
          conversationId: 'dm:did:test:paste',
          threadId: 'dm:did:test:paste',
          displayName: 'Paste',
          lastMessagePreview: '',
          lastMessageAt: DateTime(2026, 9, 17),
          unreadCount: 0,
          isGroup: false,
          targetDid: 'did:test:paste',
        ),
        embedded: false,
      ),
    ),
  ),
  providerOverrides: [
    attachmentPickerServiceProvider.overrideWithValue(picker),
  ],
);

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(CupertinoTextField));
  await tester.pump();
  await tester.tapAt(
    tester.getCenter(find.byType(EditableText)),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
  expect(find.text('粘贴'), findsOneWidget);
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.hasStrings') return {'value': true};
          if (call.method == 'Clipboard.getData') {
            return {'text': 'pasted text'};
          }
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
    testWidgets('$platform 菜单指针按下保持焦点并粘贴文本', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final picker = FakeAttachmentPickerService();
      await tester.pumpWidget(chat(picker));
      await openMenu(tester);
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('粘贴')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(editor.focusNode.hasFocus, isTrue, reason: '菜单按下不能提前取消焦点或移除菜单');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(editor.controller.text, 'pasted text');
      expect(picker.clipboardReadCalls, 1);
      await tester.tapAt(const Offset(15, 120));
      await tester.pump();
      expect(editor.focusNode.hasFocus, isFalse, reason: '真正空白处仍应收起键盘');
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('图片剪贴板没有字符串时右键仍可暂存附件', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final picker = FakeAttachmentPickerService()
      ..nextClipboardAttachment = AttachmentDraft(
        filename: 'menu-image.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
        sizeBytes: 3,
      );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.hasStrings') return {'value': false};
          return null;
        });
    await tester.pumpWidget(chat(picker));
    await openMenu(tester);
    await tester.tap(find.text('粘贴'));
    await tester.pumpAndSettle();
    expect(find.text('menu-image.png'), findsOneWidget);
    expect(picker.clipboardReadCalls, 1);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('编辑动作粘贴替换选区且可撤销', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(chat(FakeAttachmentPickerService()));
    await tester.enterText(find.byType(CupertinoTextField), 'hello original');
    await tester.pump(const Duration(milliseconds: 600));
    final editor = tester.widget<EditableText>(find.byType(EditableText));
    editor.controller.selection = const TextSelection(
      baseOffset: 6,
      extentOffset: 14,
    );
    Actions.invoke(
      tester.element(find.byType(EditableText)),
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pumpAndSettle();
    expect(editor.controller.text, 'hello pasted text');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(editor.controller.text, 'hello original');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('异步纯文本粘贴不能越过身份切换', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final data = Completer<Object?>();
    final started = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.hasStrings') return {'value': true};
          if (call.method == 'Clipboard.getData') {
            if (!started.isCompleted) started.complete();
            return data.future;
          }
          return null;
        });
    await tester.pumpWidget(chat(FakeAttachmentPickerService()));
    await openMenu(tester);
    await tester.tap(find.text('粘贴'));
    await tester.pump();
    expect(started.isCompleted, isTrue);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    container
        .read(sessionProvider.notifier)
        .activateSession(
          const SessionIdentity(
            did: 'did:test:other',
            handle: 'other',
            displayName: 'Other',
            credentialName: 'other',
          ),
        );
    data.complete({'text': 'previous identity private text'});
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
