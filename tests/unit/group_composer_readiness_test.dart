import 'dart:io';
import 'dart:ui' as ui;

import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  setUpAll(() async {
    for (final font in [
      ('AwikiGoldenCjk', 'assets/fonts/awiki_golden_cjk.ttf'),
      (
        'packages/cupertino_icons/CupertinoIcons',
        'packages/cupertino_icons/assets/CupertinoIcons.ttf',
      ),
    ]) {
      final reviewFont = Platform.environment['AWIKI_GROUP_REVIEW_FONT'];
      await (FontLoader(font.$1)..addFont(
            font.$1 == 'AwikiGoldenCjk' && reviewFont != null
                ? File(reviewFont).readAsBytes().then(ByteData.sublistView)
                : rootBundle.load(font.$2),
          ))
          .load();
    }
  });
  for (final brightness in Brightness.values) {
    for (final state in ['preparing', 'waiting', 'retry', 'ready']) {
      testWidgets('narrow $brightness group composer $state', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        tester.view.physicalSize = const Size(740, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearPlatformBrightnessTestValue();
        });
        const groupDid = 'did:example:secure-group';
        const owner = SessionIdentity(
          did: 'did:example:owner',
          credentialName: 'owner',
          displayName: 'Owner',
        );
        final group = GroupSummary(
          conversationId: 'group:$groupDid',
          groupId: groupDid,
          displayName: '项目讨论群',
          description: '',
          memberCount: 3,
          lastMessageAt: null,
          myRole: 'owner',
          membershipStatus: 'active',
          encrypted: true,
          canSendSecure: state == 'ready',
          secureState: state == 'waiting'
              ? 'waitingForMembershipUpdate'
              : state,
          secureRetryable: state == 'retry',
          secureProblem: state == 'retry' ? '加密准备未完成，请检查连接后重试' : null,
        );
        final gateway = FakeAwikiGateway()
          ..loginResult = owner
          ..groups = [group];
        final conversation = ConversationSummary(
          conversationId: group.conversationId,
          threadId: group.conversationId,
          groupId: groupDid,
          displayName: group.displayName,
          lastMessagePreview: '',
          lastMessageAt: DateTime(2026, 10, 10),
          unreadCount: 0,
          isGroup: true,
        );
        const capture = Key('group-composer-capture');
        final theme = AwikiMeTheme.forPlatform(
          TargetPlatform.macOS,
          fontFamilyOverride: 'AwikiGoldenCjk',
        );
        await tester.pumpWidget(
          buildLocalizedTestApp(
            gateway: gateway,
            session: owner,
            home: RepaintBoundary(
              key: capture,
              child: Theme(
                data: theme.materialTheme,
                child: CupertinoTheme(
                  data: theme.cupertinoTheme.copyWith(brightness: brightness),
                  child: CupertinoPageScaffold(
                    child: DefaultTextStyle(
                      style: theme.cupertinoTheme.textTheme.textStyle,
                      child: ChatView(
                        conversation: conversation,
                        embedded: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        ProviderScope.containerOf(
          tester.element(find.byType(ChatView)),
        ).read(groupProvider.notifier).upsertGroup(group);
        await tester.pumpAndSettle();
        expect(
          find.byType(CupertinoTextField),
          state == 'ready' ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('重试'),
          state == 'retry' ? findsOneWidget : findsNothing,
        );
        expect(find.text('刷新群状态'), findsNothing);
        if (state == 'preparing') {
          expect(find.text('正在准备加密聊天…'), findsOneWidget);
        }
        if (state == 'waiting') expect(find.text('等待成员完成加密准备'), findsOneWidget);
        if (state == 'ready') expect(find.text('正在准备加密聊天…'), findsNothing);
        expect(tester.takeException(), isNull);
        final output = Platform.environment['AWIKI_GROUP_UI_ARTIFACTS'];
        if (output != null) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(capture),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(output).create(recursive: true);
            await File(
              '$output/${brightness.name}-$state.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
