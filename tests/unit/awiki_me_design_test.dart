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
      ..._tokenStyles(theme.tokens),
    ]) {
      _expectWindowsFont(style);
    }
  });

  test('non-Windows theme keeps the existing platform typography', () {
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

List<TextStyle> _tokenStyles(AwikiMeThemeTokens tokens) => <TextStyle>[
  tokens.sectionTitle,
  tokens.navTitle,
  tokens.cardTitle,
  tokens.cardSubtitle,
  tokens.meta,
  tokens.listTitle,
  tokens.listSubtitle,
  tokens.listMeta,
  tokens.messageBody,
  tokens.inputText,
  tokens.fieldLabel,
  tokens.buttonLabel,
  tokens.pillLabel,
  tokens.markdownBody,
];

void _expectWindowsFont(TextStyle style) {
  expect(style.fontFamily, AwikiMeTheme.windowsFontFamily);
  expect(style.fontFamilyFallback, AwikiMeTheme.windowsFontFamilyFallback);
}
