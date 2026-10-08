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

  test('navigation roles use the reference line glyphs in both states', () {
    const expected = <AwikiMeIconRole, String>{
      AwikiMeIconRole.messages: 'assets/icons/nav_chat.svg',
      AwikiMeIconRole.agents: 'assets/icons/nav_agents.svg',
      AwikiMeIconRole.contacts: 'assets/icons/nav_contacts.svg',
      AwikiMeIconRole.tasks: 'assets/icons/nav_tasks.svg',
      AwikiMeIconRole.profile: 'assets/icons/nav_me.svg',
      AwikiMeIconRole.settings: 'assets/icons/nav_settings.svg',
    };
    for (final entry in expected.entries) {
      final definition = AwikiMeIconRegistry.definition(entry.key);
      expect(definition.assetFor(selected: false), entry.value);
      expect(definition.assetFor(selected: true), entry.value);
      // Drawn on the reference's 24-unit grid, so no optical correction.
      expect(definition.opticalScale, 1);
    }
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
          child: AwikiMeSemanticIcon(role: AwikiMeIconRole.workbench, size: 18),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, CupertinoIcons.square_grid_2x2);
    expect(icon.size, 18);
    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(AwikiMeSemanticIcon),
        matching: find.byType(Transform),
      ),
    );
    expect(transform.transform.storage[0], closeTo(1, 0.001));
    expect(transform.transform.storage[5], closeTo(1, 0.001));
    expect(
      tester.getSize(find.byType(AwikiMeSemanticIcon)),
      const Size.square(18),
    );
  });
}
