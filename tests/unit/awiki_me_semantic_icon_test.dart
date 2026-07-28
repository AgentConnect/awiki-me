import 'package:awiki_me/src/presentation/shared/awiki_me_semantic_icon.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry covers every semantic role', () {
    for (final role in AwikiMeIconRole.values) {
      expect(
        AwikiMeIconRegistry.definition(role).fallback,
        isA<IconData>(),
        reason: '$role must always have a platform-safe fallback',
      );
    }
  });

  test('selected navigation roles keep the same stable glyph assets', () {
    expect(
      AwikiMeIconRegistry.definition(
        AwikiMeIconRole.messages,
      ).assetFor(selected: true),
      'assets/icons/message_Inactive.svg',
    );
    expect(
      AwikiMeIconRegistry.definition(
        AwikiMeIconRole.contacts,
      ).assetFor(selected: true),
      'assets/icons/friend_Inactive.svg',
    );
    expect(
      AwikiMeIconRegistry.definition(
        AwikiMeIconRole.profile,
      ).assetFor(selected: true),
      'assets/icons/me_Inactive.svg',
    );
  });

  test('navigation optical calibration is centralized in the registry', () {
    expect(
      AwikiMeIconRegistry.definition(AwikiMeIconRole.messages).opticalScale,
      greaterThan(1),
    );
    expect(
      AwikiMeIconRegistry.definition(AwikiMeIconRole.contacts).opticalScale,
      greaterThan(1),
    );
    expect(
      AwikiMeIconRegistry.definition(AwikiMeIconRole.profile).opticalScale,
      greaterThan(1),
    );
    expect(
      AwikiMeIconRegistry.definition(AwikiMeIconRole.agents).opticalScale,
      lessThan(1),
    );
  });

  testWidgets('asset-backed icon has stable dimensions and tint', (
    tester,
  ) async {
    const tint = Color(0xFF0081D3);
    await tester.pumpWidget(
      const CupertinoApp(
        home: Center(
          child: AwikiMeSemanticIcon(
            role: AwikiMeIconRole.messages,
            selected: true,
            size: 23,
            color: tint,
            semanticLabel: 'Messages',
          ),
        ),
      ),
    );

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(
      tester.getSize(find.byType(AwikiMeSemanticIcon)),
      const Size(23, 23),
    );
    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(picture.colorFilter, const ColorFilter.mode(tint, BlendMode.srcIn));
    expect(picture.semanticsLabel, 'Messages');
  });

  testWidgets('roles without assets use the registered system fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: Center(
          child: AwikiMeSemanticIcon(role: AwikiMeIconRole.agents, size: 18),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, CupertinoIcons.square_stack_3d_up);
    expect(icon.size, 18);
    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(AwikiMeSemanticIcon),
        matching: find.byType(Transform),
      ),
    );
    expect(transform.transform.storage[0], closeTo(0.86, 0.001));
    expect(transform.transform.storage[5], closeTo(0.86, 0.001));
    expect(
      tester.getSize(find.byType(AwikiMeSemanticIcon)),
      const Size.square(18),
    );
  });
}
