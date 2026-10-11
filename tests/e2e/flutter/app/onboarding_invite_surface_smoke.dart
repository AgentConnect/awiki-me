import 'dart:io';
import 'dart:ui' as ui;

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/onboarding_support_service.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

import '../../../unit/test_support.dart' as support;
import '../../case_attestation.dart';

class _InvitationSupport extends support.FakeOnboardingSupportService {
  const _InvitationSupport(super.gateway);

  @override
  Future<RegistrationCheck> checkRegistration({
    required String handle,
    required String domain,
    String? inviteCode,
    String? phone,
    String? email,
    bool checkInvite = false,
  }) async => RegistrationCheck(
    fullHandle: '$handle.$domain',
    decision: 'register',
    inviteRequired: true,
    inviteStatus: 'required',
  );
}

/// Uses the native Flutter renderer with owning fake account/OTP services.
/// This verifies the rendered auth surface, not remote registration acceptance.
void registerInvitationSurfaceSmoke() {
  for (final size in [const Size(390, 900), const Size(1100, 900)]) {
    for (final brightness in Brightness.values) {
      testWidgets('native invite surface $size ${brightness.name}', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final gateway = support.FakeAwikiGateway();
        final theme = AwikiMeTheme.forPlatform(
          TargetPlatform.macOS,
          brightness: brightness,
        );
        await tester.pumpWidget(
          support.buildLocalizedTestApp(
            gateway: gateway,
            providerOverrides: [
              onboardingSupportServiceProvider.overrideWithValue(
                _InvitationSupport(gateway),
              ),
            ],
            home: Theme(
              data: theme.materialTheme,
              child: MediaQuery(
                data: MediaQueryData(size: size),
                child: const RepaintBoundary(
                  key: Key('native-invite-surface'),
                  child: OnboardingPage(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Finder field(String id) => find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.identifier == id,
          ),
          matching: find.byType(CupertinoTextField),
        );
        Container surface(Finder input) => tester
            .widgetList<Container>(
              find.ancestor(of: input, matching: find.byType(Container)),
            )
            .firstWhere(
              (w) =>
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).border != null,
            );
        Future<void> focus(Finder input) async {
          await tester.ensureVisible(input);
          await tester.tap(input);
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 150));
          expect(
            tester.widget<CupertinoTextField>(input).focusNode!.hasFocus,
            isTrue,
          );
        }

        await tester.enterText(field('e2e-phone-input'), '13800138000');
        await tester.enterText(field('e2e-handle-input'), 'abcd');
        await tester.ensureVisible(find.text('发送验证码'));
        await tester.tap(find.text('发送验证码'));
        await tester.pumpAndSettle();
        final invite = field('e2e-invite-input');
        final handle = field('e2e-handle-input');
        await tester.ensureVisible(invite);
        await tester.pumpAndSettle();
        final idle = surface(invite);
        expect(idle.decoration, surface(handle).decoration);
        expect(idle.constraints, surface(handle).constraints);
        expect(idle.padding, surface(handle).padding);
        final before = tester.getRect(invite);
        await tester.enterText(invite, 'ABC123');
        await tester.pumpAndSettle();
        expect(tester.getRect(invite), before);
        final focused = surface(invite);
        expect(
          (focused.decoration! as BoxDecoration).color,
          (idle.decoration! as BoxDecoration).color,
        );
        final input = tester.widget<CupertinoTextField>(invite);
        expect(input.style!.fontSize, size.width < 600 ? 16 : 14);
        expect(focused.constraints!.minHeight, size.width < 600 ? 50 : 38);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('native-invite-surface')),
        );
        final rect = tester.getRect(invite);
        final point = boundary.globalToLocal(
          Offset(rect.right - 8, rect.center.dy),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final offset =
              (point.dy.floor() * image.width + point.dx.floor()) * 4;
          final fill = Color.fromARGB(
            pixels.getUint8(offset + 3),
            pixels.getUint8(offset),
            pixels.getUint8(offset + 1),
            pixels.getUint8(offset + 2),
          );
          final luminance = [
            fill.computeLuminance(),
            input.style!.color!.computeLuminance(),
          ]..sort();
          final contrast = (luminance.last + .05) / (luminance.first + .05);
          expect(contrast, greaterThanOrEqualTo(4.5));
          final attestation = e2eInvocationValue(
            e2eCaseAttestationPathDefine,
            compiledValue: const String.fromEnvironment(
              e2eCaseAttestationPathDefine,
            ),
          );
          if (attestation.isNotEmpty) {
            final png = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File(
              '${File(attestation).parent.path}/invite-${size.width.toInt()}-${brightness.name}.png',
            ).writeAsBytes(png.buffer.asUint8List());
          }
          debugPrint(
            'invite_surface width=${size.width.toInt()} theme=${brightness.name} contrast=${contrast.toStringAsFixed(2)} stable_bounds=true',
          );
        } finally {
          image.dispose();
        }
        await focus(handle);
        expect(focused.decoration, surface(handle).decoration);
        expect(input.style, tester.widget<CupertinoTextField>(handle).style);
        await focus(invite);
        expect(
          tester.widget<CupertinoTextField>(invite).controller!.text,
          'ABC123',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
