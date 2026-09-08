import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/screenshot_failure.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/chat/screenshot_permission_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class _PermissionPicker extends FakeAttachmentPickerService {
  final pending = Completer<void>();
  @override
  Future<AttachmentDraft?> captureScreenshot({bool hideApp = false}) async {
    screenshotCalls++;
    await pending.future;
    throw ScreenshotFailure(ScreenshotFailureKind.permissionRequired);
  }
}

void main() {
  testWidgets(
    'chat coalesces capture clicks and offers a single permission recovery dialog',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.binding.setSurfaceSize(const Size(1100, 760));
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        return tester.binding.setSurfaceSize(null);
      });
      final picker = _PermissionPicker();
      final conversation = ConversationSummary(
        threadId: 'dm:screenshot-recovery',
        conversationId: 'dm:screenshot-recovery',
        displayName: 'Tester',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 9, 8),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:test:peer',
      );
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: CupertinoPageScaffold(
            child: ChatView(
              conversation: conversation,
              embedded: true,
              macStyle: true,
            ),
          ),
          session: const SessionIdentity(
            did: 'did:test:me',
            handle: 'me',
            displayName: 'Me',
            credentialName: 'default',
          ),
          providerOverrides: [
            attachmentPickerServiceProvider.overrideWithValue(picker),
          ],
        ),
      );
      final button = find.byKey(const Key('chat-screenshot-button'));
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      expect(picker.screenshotCalls, 1);
      picker.pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ScreenshotPermissionDialog), findsOneWidget);
      expect(
        find.byKey(const Key('chat-pending-attachment-preview')),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(picker.screenshotCalls, 2);
      expect(find.byType(ScreenshotPermissionDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    },
  );
}
