import 'dart:ui' as ui;

import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/shared/app_dialog.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_me/src/presentation/shared/identity_flow.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_shell_ready.dart';
import 'test_support.dart';

void main() {
  for (final brightness in Brightness.values) {
    final theme = AwikiMeTheme.forPlatform(
      TargetPlatform.macOS,
      brightness: brightness,
    );
    testWidgets('start chat has a visible panel and border in $brightness', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final capture = GlobalKey();
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: Theme(
            data: theme.materialTheme,
            child: RepaintBoundary(
              key: capture,
              child: ColoredBox(
                color: Color.alphaBlend(
                  const Color(0x33161616),
                  theme.tokens.background,
                ),
                child: const IdentityLookupDialog(
                  mode: IdentityFlowMode.startConversation,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final panel = find
          .descendant(
            of: find.byType(AppDialogScaffold),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).boxShadow != null,
            ),
          )
          .first;
      final rect = tester.getRect(panel);
      final pixels = await _capture(tester, capture);
      // Sample the actual painted panel away from text and curved corners.
      final fill = pixels(rect.topLeft + const Offset(10, 10));
      final border = pixels(Offset(rect.center.dx, rect.top));
      final outside = pixels(const Offset(20, 20));
      expect(fill, theme.tokens.dialogSurface);
      expect(border, theme.tokens.dialogBorder);
      expect(_contrast(fill, outside), greaterThan(1.2));
      expect(_contrast(border, fill), greaterThan(1.2));
      expect(find.text('发起聊天'), findsOneWidget);
      expect(find.byKey(const Key('identity-start-chat-button')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rail connection dot paints a complete circle in $brightness', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.binding.setSurfaceSize(null);
      });
      final realtime = FakeRealtimeGateway()
        ..setStatus(RealtimeConnectionStatus.connected);
      final capture = GlobalKey();
      await tester.pumpWidget(
        buildLocalizedTestApp(
          session: const SessionIdentity(
            did: 'did:test:me',
            credentialName: 'me',
            displayName: 'Me',
            handle: 'me',
          ),
          realtimeGateway: realtime,
          home: Theme(
            data: theme.materialTheme,
            child: RepaintBoundary(key: capture, child: const AppShell()),
          ),
        ),
      );
      await pumpUntilAppShellReady(tester, loggedIn: true);
      await tester.pumpAndSettle();
      final dot = find.byKey(const Key('mac-me-rail-online-dot'));
      expect(dot, findsOneWidget);
      final rect = tester.getRect(dot);
      final pixels = await _capture(tester, capture);
      // The original ancestor clip kept only a crescent. Check every quadrant
      // of the inner green disc, not merely the badge widget's existence.
      for (final dx in [-1.5, 1.5]) {
        for (final dy in [-1.5, 1.5]) {
          expect(pixels(rect.center + Offset(dx, dy)), theme.tokens.success);
        }
      }
      realtime.setStatus(RealtimeConnectionStatus.disconnected);
      await tester.pump();
      await tester.pump();
      expect(dot, findsNothing);
      realtime.setStatus(RealtimeConnectionStatus.connected);
      await tester.pump();
      await tester.pump();
      expect(dot, findsOneWidget);
      await tester.tap(find.byKey(const Key('mac-me-rail-avatar')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppDialogScaffold), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}

double _contrast(Color a, Color b) {
  final luminances = [a.computeLuminance(), b.computeLuminance()]..sort();
  return (luminances.last + 0.05) / (luminances.first + 0.05);
}

Future<Color Function(Offset)> _capture(
  WidgetTester tester,
  GlobalKey key,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 2)))!;
  final bytes = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final width = image.width;
  final origin = boundary.localToGlobal(Offset.zero);
  image.dispose();
  return (point) {
    final local = point - origin;
    final index = ((local.dy * 2).floor() * width + (local.dx * 2).floor()) * 4;
    return Color.fromARGB(
      bytes.getUint8(index + 3),
      bytes.getUint8(index),
      bytes.getUint8(index + 1),
      bytes.getUint8(index + 2),
    );
  };
}
