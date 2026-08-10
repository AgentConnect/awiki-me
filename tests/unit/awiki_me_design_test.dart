import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show TextTheme;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows theme applies the UI font policy to every text surface', () {
    final theme = AwikiMeTheme.forPlatform(TargetPlatform.windows);

    for (final style in <TextStyle>[
      ..._materialStyles(theme.materialTheme.textTheme),
      ..._materialStyles(theme.materialTheme.primaryTextTheme),
      ..._cupertinoStyles(theme.cupertinoTheme.textTheme),
      ...theme.tokens.compactTypography.styles,
      ...theme.tokens.expandedTypography.styles,
    ]) {
      _expectWindowsFont(style);
      _expectNoTracking(style);
    }
  });

  test(
    'Apple theme keeps the platform font while removing custom tracking',
    () {
      final theme = AwikiMeTheme.forPlatform(TargetPlatform.macOS);

      expect(theme.materialTheme.platform, TargetPlatform.macOS);
      expect(theme.tokens.messageBody.fontFamily, isNull);
      expect(theme.tokens.messageBody.fontFamilyFallback, isNull);
      expect(theme.cupertinoTheme.textTheme.textStyle.fontFamily, isNull);
      expect(
        theme.cupertinoTheme.textTheme.actionTextStyle.fontFamily,
        'CupertinoSystemText',
      );
      expect(
        theme.materialTheme.textTheme.bodyMedium?.fontFamily,
        isNot(AwikiMeTheme.windowsFontFamily),
      );
      expect(theme.materialTheme.colorScheme, AwikiMeTheme.colorScheme);
      for (final style in <TextStyle>[
        ..._materialStyles(theme.materialTheme.textTheme),
        ..._cupertinoStyles(theme.cupertinoTheme.textTheme),
        ...theme.tokens.compactTypography.styles,
        ...theme.tokens.expandedTypography.styles,
      ]) {
        _expectNoTracking(style);
      }
    },
  );

  test('Android theme leaves the system font unforced', () {
    final theme = AwikiMeTheme.forPlatform(TargetPlatform.android);

    expect(theme.materialTheme.platform, TargetPlatform.android);
    expect(theme.tokens.messageBody.fontFamily, isNull);
    expect(theme.tokens.messageBody.fontFamilyFallback, isNull);
    expect(
      theme.materialTheme.textTheme.bodyMedium?.fontFamily,
      isNot(AwikiMeTheme.windowsFontFamily),
    );
  });

  test('all platform themes and typography tokens use regular weight', () {
    for (final platform in TargetPlatform.values) {
      final theme = AwikiMeTheme.forPlatform(platform);
      for (final style in <TextStyle>[
        ..._materialStyles(theme.materialTheme.textTheme),
        ..._materialStyles(theme.materialTheme.primaryTextTheme),
        ..._cupertinoStyles(theme.cupertinoTheme.textTheme),
        ...theme.tokens.compactTypography.styles,
        ...theme.tokens.expandedTypography.styles,
      ]) {
        expect(style.fontWeight, FontWeight.w400);
      }
    }
  });

  test('visual tests can opt into the deterministic repository CJK font', () {
    final theme = AwikiMeTheme.forPlatform(
      TargetPlatform.iOS,
      fontFamilyOverride: 'AwikiGoldenCjk',
    );

    expect(theme.tokens.compactTypography.body.fontFamily, 'AwikiGoldenCjk');
    expect(theme.tokens.expandedTypography.body.fontFamily, 'AwikiGoldenCjk');
    expect(
      theme.materialTheme.textTheme.bodyMedium?.fontFamily,
      'AwikiGoldenCjk',
    );
    expect(
      theme.cupertinoTheme.textTheme.textStyle.fontFamily,
      'AwikiGoldenCjk',
    );
  });

  test('semantic light colors match the approved desktop and mobile roles', () {
    final colors = AwikiMeTheme.forPlatform(
      TargetPlatform.macOS,
    ).tokens.semanticColors;

    expect(colors.canvas, const Color(0xFFFAF9F7));
    expect(colors.surface, const Color(0xFFFFFFFF));
    expect(colors.title, const Color(0xFF2D2B26));
    expect(colors.secondaryText, const Color(0xFF6B6963));
    expect(colors.border, const Color(0xFFE8E7E4));
    expect(colors.primary, const Color(0xFF0081D3));
    expect(colors.success, const Color(0xFF03A14A));
    expect(colors.warning, const Color(0xFFDA950B));
    expect(colors.danger, const Color(0xFFD73431));
    expect(colors.unread, const Color(0xFFFA5152));
    expect(colors.navigationSurface, const Color(0xFFEEEDE9));
    expect(colors.navigationBorder, const Color(0xFFDDDCD9));
    expect(colors.chatSurface, const Color(0xFFFAFAFA));
    expect(colors.incomingMessage, const Color(0xFFEEEEF0));
    expect(colors.outgoingMessage, const Color(0xFFB6E4FF));
    expect(colors.onOutgoingMessage, const Color(0xFF0F304A));
  });

  test('compact and expanded typography expose intentional type ramps', () {
    final tokens = AwikiMeTheme.forPlatform(TargetPlatform.macOS).tokens;
    final compact = tokens.typographyFor(AwikiMeTypographyMode.compact);
    final expanded = tokens.typographyFor(AwikiMeTypographyMode.expanded);

    expect(compact.displayTitle.fontSize, 20);
    expect(expanded.displayTitle.fontSize, 30);
    expect(compact.listTitle.fontSize, 13.5);
    expect(expanded.listTitle.fontSize, 15.5);
    expect(compact.messageBody.fontSize, 14);
    expect(expanded.messageBody.fontSize, 15);
    expect(compact.buttonLabel.fontSize, 13.5);
    expect(expanded.buttonLabel.fontSize, 15);
    expect(tokens.messageBody, expanded.messageBody);

    for (final style in <TextStyle>[...compact.styles, ...expanded.styles]) {
      _expectNoTracking(style);
    }
  });

  test('layout and motion tokens preserve the prototype density scale', () {
    expect(AwikiMeInsets.xxs, 2);
    expect(AwikiMeInsets.compact, 6);
    expect(AwikiMeInsets.xxxl, 32);
    expect(AwikiMeRadii.control, 10);
    expect(AwikiMeRadii.overlay, 14);
    expect(AwikiMeRadii.md, 16);
    expect(AwikiMeMotion.fast, const Duration(milliseconds: 120));
    expect(AwikiMeMotion.standard, const Duration(milliseconds: 150));
    expect(AwikiMeMotion.sheet, const Duration(milliseconds: 300));
  });
}

Iterable<TextStyle> _materialStyles(TextTheme theme) sync* {
  for (final style in <TextStyle?>[
    theme.displayLarge,
    theme.displayMedium,
    theme.displaySmall,
    theme.headlineLarge,
    theme.headlineMedium,
    theme.headlineSmall,
    theme.titleLarge,
    theme.titleMedium,
    theme.titleSmall,
    theme.bodyLarge,
    theme.bodyMedium,
    theme.bodySmall,
    theme.labelLarge,
    theme.labelMedium,
    theme.labelSmall,
  ]) {
    if (style != null) {
      yield style;
    }
  }
}

List<TextStyle> _cupertinoStyles(CupertinoTextThemeData theme) => <TextStyle>[
  theme.textStyle,
  theme.actionTextStyle,
  theme.actionSmallTextStyle,
  theme.tabLabelTextStyle,
  theme.navTitleTextStyle,
  theme.navLargeTitleTextStyle,
  theme.navActionTextStyle,
  theme.pickerTextStyle,
  theme.dateTimePickerTextStyle,
];

void _expectWindowsFont(TextStyle style) {
  expect(style.fontFamily, AwikiMeTheme.windowsFontFamily);
  expect(style.fontFamilyFallback, AwikiMeTheme.windowsFontFamilyFallback);
}

void _expectNoTracking(TextStyle style) {
  expect(style.letterSpacing, 0, reason: '$style must use letterSpacing=0');
}
