import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show ColorScheme, Theme, ThemeData, ThemeExtension;

class AwikiMePalette {
  static const Color amber = Color(0xFFFFAA00);
  static const Color amberDeep = Color(0xFF825500);
  static const Color actionBlue = Color(0xFF0B65F8);
  static const Color actionBlueDeep = Color(0xFF0752F0);
  static const Color actionBlueSoft = Color(0xFFEAF2FF);
  static const Color actionBlueBorder = Color(0xFFDDE5F0);
  static const Color actionInk = Color(0xFF17213A);
  static const Color actionMuted = Color(0xFF66728A);
  static const Color ivory = Color(0xFFFAF9FE);
  static const Color white = Color(0xFFFFFFFF);
  static const Color mist = Color(0xFFF4F3F8);
  static const Color cloud = Color(0xFFEEEDF3);
  static const Color line = Color(0xFFF0EDF5);
  static const Color ink = Color(0xFF1A1C1C);
  static const Color body = Color(0xFF111827);
  static const Color slate = Color(0xFF6B7280);
  static const Color fog = Color(0xFFA9A9A9);
  static const Color success = Color(0xFF31CE96);
  static const Color error = Color(0xFFEF4444);
  static const Color alert = Color(0xFFFF7B61);
  static const Color warningContainer = Color(0xFFFFF4D6);
  static const Color errorContainer = Color(0xFFFFEBEB);
  static const Color infoBlue = Color(0xFF2563EB);
}

class AwikiMeColors {
  static const Color background = AwikiMePalette.ivory;
  static const Color surface = AwikiMePalette.white;
  static const Color subtleSurface = AwikiMePalette.mist;
  static const Color mutedSurface = AwikiMePalette.cloud;
  static const Color border = AwikiMePalette.line;
  static const Color primary = AwikiMePalette.actionBlue;
  static const Color primaryDark = AwikiMePalette.actionBlue;
  static const Color title = AwikiMePalette.ink;
  static const Color body = AwikiMePalette.body;
  static const Color secondaryText = AwikiMePalette.slate;
  static const Color tertiaryText = AwikiMePalette.fog;
  static const Color online = AwikiMePalette.success;
  static const Color danger = AwikiMePalette.error;
  static const Color alert = AwikiMePalette.alert;
}

class AwikiMeInsets {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;

  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: xxl);
  static const EdgeInsets card = EdgeInsets.all(lg);
}

class AwikiMeRadii {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double pill = 999;
}

class AwikiMeShadows {
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Color(0x0C000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> overlay = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

@immutable
class AwikiMeThemeTokens extends ThemeExtension<AwikiMeThemeTokens> {
  const AwikiMeThemeTokens({
    required this.colorScheme,
    required this.sectionTitle,
    required this.navTitle,
    required this.cardTitle,
    required this.cardSubtitle,
    required this.meta,
    required this.listTitle,
    required this.listSubtitle,
    required this.listMeta,
    required this.messageBody,
    required this.inputText,
    required this.fieldLabel,
    required this.buttonLabel,
    required this.pillLabel,
    required this.markdownBody,
    required this.cardShadow,
    required this.overlayShadow,
  });

  final ColorScheme colorScheme;
  final TextStyle sectionTitle;
  final TextStyle navTitle;
  final TextStyle cardTitle;
  final TextStyle cardSubtitle;
  final TextStyle meta;
  final TextStyle listTitle;
  final TextStyle listSubtitle;
  final TextStyle listMeta;
  final TextStyle messageBody;
  final TextStyle inputText;
  final TextStyle fieldLabel;
  final TextStyle buttonLabel;
  final TextStyle pillLabel;
  final TextStyle markdownBody;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> overlayShadow;

  Color get background => colorScheme.surfaceContainerLowest;
  Color get surface => colorScheme.surface;
  Color get subtleSurface => colorScheme.surfaceContainerLow;
  Color get mutedSurface => colorScheme.surfaceContainerHighest;
  Color get border => colorScheme.outlineVariant;
  Color get primary => colorScheme.primary;
  Color get primaryForeground => colorScheme.onPrimary;
  Color get primaryDark => colorScheme.primaryContainer;
  Color get title => colorScheme.onSurface;
  Color get body => colorScheme.onSurface;
  Color get secondaryText => colorScheme.onSurfaceVariant;
  Color get tertiaryText => colorScheme.outline;
  Color get success => AwikiMePalette.success;
  Color get danger => colorScheme.error;
  Color get alert => AwikiMePalette.alert;
  Color get warningContainer => AwikiMePalette.warningContainer;
  Color get dangerContainer => AwikiMePalette.errorContainer;
  Color get infoAccent => AwikiMePalette.infoBlue;

  @override
  AwikiMeThemeTokens copyWith({
    ColorScheme? colorScheme,
    TextStyle? sectionTitle,
    TextStyle? navTitle,
    TextStyle? cardTitle,
    TextStyle? cardSubtitle,
    TextStyle? meta,
    TextStyle? listTitle,
    TextStyle? listSubtitle,
    TextStyle? listMeta,
    TextStyle? messageBody,
    TextStyle? inputText,
    TextStyle? fieldLabel,
    TextStyle? buttonLabel,
    TextStyle? pillLabel,
    TextStyle? markdownBody,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? overlayShadow,
  }) {
    return AwikiMeThemeTokens(
      colorScheme: colorScheme ?? this.colorScheme,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      navTitle: navTitle ?? this.navTitle,
      cardTitle: cardTitle ?? this.cardTitle,
      cardSubtitle: cardSubtitle ?? this.cardSubtitle,
      meta: meta ?? this.meta,
      listTitle: listTitle ?? this.listTitle,
      listSubtitle: listSubtitle ?? this.listSubtitle,
      listMeta: listMeta ?? this.listMeta,
      messageBody: messageBody ?? this.messageBody,
      inputText: inputText ?? this.inputText,
      fieldLabel: fieldLabel ?? this.fieldLabel,
      buttonLabel: buttonLabel ?? this.buttonLabel,
      pillLabel: pillLabel ?? this.pillLabel,
      markdownBody: markdownBody ?? this.markdownBody,
      cardShadow: cardShadow ?? this.cardShadow,
      overlayShadow: overlayShadow ?? this.overlayShadow,
    );
  }

  @override
  AwikiMeThemeTokens lerp(
    covariant ThemeExtension<AwikiMeThemeTokens>? other,
    double t,
  ) {
    if (other is! AwikiMeThemeTokens) {
      return this;
    }
    return AwikiMeThemeTokens(
      colorScheme: ColorScheme.lerp(colorScheme, other.colorScheme, t),
      sectionTitle: TextStyle.lerp(sectionTitle, other.sectionTitle, t)!,
      navTitle: TextStyle.lerp(navTitle, other.navTitle, t)!,
      cardTitle: TextStyle.lerp(cardTitle, other.cardTitle, t)!,
      cardSubtitle: TextStyle.lerp(cardSubtitle, other.cardSubtitle, t)!,
      meta: TextStyle.lerp(meta, other.meta, t)!,
      listTitle: TextStyle.lerp(listTitle, other.listTitle, t)!,
      listSubtitle: TextStyle.lerp(listSubtitle, other.listSubtitle, t)!,
      listMeta: TextStyle.lerp(listMeta, other.listMeta, t)!,
      messageBody: TextStyle.lerp(messageBody, other.messageBody, t)!,
      inputText: TextStyle.lerp(inputText, other.inputText, t)!,
      fieldLabel: TextStyle.lerp(fieldLabel, other.fieldLabel, t)!,
      buttonLabel: TextStyle.lerp(buttonLabel, other.buttonLabel, t)!,
      pillLabel: TextStyle.lerp(pillLabel, other.pillLabel, t)!,
      markdownBody: TextStyle.lerp(markdownBody, other.markdownBody, t)!,
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
      overlayShadow: t < 0.5 ? overlayShadow : other.overlayShadow,
    );
  }
}

class AwikiMeTheme {
  static const ColorScheme colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AwikiMePalette.actionBlue,
    onPrimary: AwikiMePalette.white,
    secondary: AwikiMePalette.infoBlue,
    onSecondary: AwikiMePalette.white,
    error: AwikiMePalette.error,
    onError: AwikiMePalette.white,
    surface: AwikiMePalette.white,
    onSurface: AwikiMePalette.ink,
    surfaceContainerHighest: AwikiMePalette.cloud,
    onSurfaceVariant: AwikiMePalette.slate,
    outline: AwikiMePalette.fog,
    outlineVariant: AwikiMePalette.line,
    primaryContainer: AwikiMePalette.actionBlue,
    onPrimaryContainer: AwikiMePalette.white,
    secondaryContainer: Color(0xFFDCEBFF),
    onSecondaryContainer: AwikiMePalette.infoBlue,
    errorContainer: AwikiMePalette.errorContainer,
    onErrorContainer: AwikiMePalette.error,
    surfaceContainerLow: AwikiMePalette.mist,
    surfaceContainerLowest: AwikiMePalette.ivory,
    tertiary: AwikiMePalette.success,
    onTertiary: AwikiMePalette.white,
    tertiaryContainer: Color(0xFFD8F8E8),
    onTertiaryContainer: Color(0xFF059669),
    inverseSurface: AwikiMePalette.ink,
    onInverseSurface: AwikiMePalette.white,
    inversePrimary: AwikiMePalette.actionBlue,
    shadow: Color(0x1A000000),
    scrim: Color(0x52000000),
    surfaceTint: AwikiMePalette.actionBlue,
  );

  static const AwikiMeThemeTokens tokens = AwikiMeThemeTokens(
    colorScheme: colorScheme,
    sectionTitle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w500,
      color: AwikiMePalette.ink,
      letterSpacing: 0,
    ),
    navTitle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w500,
      color: AwikiMePalette.ink,
      letterSpacing: 0,
    ),
    cardTitle: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: AwikiMePalette.body,
      letterSpacing: 0,
    ),
    cardSubtitle: TextStyle(
      fontSize: 14,
      color: AwikiMePalette.slate,
      height: 1.35,
      letterSpacing: 0,
    ),
    meta: TextStyle(fontSize: 12, color: AwikiMePalette.fog, letterSpacing: 0),
    listTitle: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: AwikiMePalette.ink,
      height: 1.25,
      letterSpacing: 0,
    ),
    listSubtitle: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: AwikiMePalette.slate,
      height: 1.3,
      letterSpacing: 0,
    ),
    listMeta: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: AwikiMePalette.slate,
      height: 1.2,
      letterSpacing: 0,
    ),
    messageBody: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: AwikiMePalette.ink,
      height: 1.45,
      letterSpacing: 0,
    ),
    inputText: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: AwikiMePalette.ink,
      height: 1.25,
      letterSpacing: 0,
    ),
    fieldLabel: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: AwikiMePalette.slate,
      letterSpacing: 0,
    ),
    buttonLabel: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    pillLabel: TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
    markdownBody: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      color: AwikiMePalette.body,
      height: 1.5,
      letterSpacing: 0,
    ),
    cardShadow: AwikiMeShadows.card,
    overlayShadow: AwikiMeShadows.overlay,
  );

  static final ThemeData materialTheme = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
    extensions: const <ThemeExtension<dynamic>>[tokens],
  );

  static final CupertinoThemeData cupertinoTheme = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: colorScheme.primary,
    scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
    barBackgroundColor: colorScheme.surface,
    textTheme: CupertinoTextThemeData(
      primaryColor: colorScheme.primary,
      textStyle: TextStyle(color: colorScheme.onSurface, fontSize: 15),
    ),
  );
}

extension AwikiMeThemeX on BuildContext {
  AwikiMeThemeTokens get awikiTheme =>
      Theme.of(this).extension<AwikiMeThemeTokens>() ?? AwikiMeTheme.tokens;
}

class AwikiMeDecorations {
  static BoxDecoration card({
    BuildContext? context,
    Color? color,
    double radius = AwikiMeRadii.md,
    Border? border,
  }) {
    final theme = context?.awikiTheme ?? AwikiMeTheme.tokens;
    return BoxDecoration(
      color: color ?? theme.surface,
      borderRadius: BorderRadius.circular(radius),
      border: border,
      boxShadow: theme.cardShadow,
    );
  }
}

class AwikiMeTextStyles {
  static TextStyle get sectionTitle => AwikiMeTheme.tokens.sectionTitle;

  static TextStyle get navTitle => AwikiMeTheme.tokens.navTitle;

  static TextStyle get cardTitle => AwikiMeTheme.tokens.cardTitle;

  static TextStyle get cardSubtitle => AwikiMeTheme.tokens.cardSubtitle;

  static TextStyle get meta => AwikiMeTheme.tokens.meta;

  static TextStyle get listTitle => AwikiMeTheme.tokens.listTitle;

  static TextStyle get listSubtitle => AwikiMeTheme.tokens.listSubtitle;

  static TextStyle get listMeta => AwikiMeTheme.tokens.listMeta;

  static TextStyle get messageBody => AwikiMeTheme.tokens.messageBody;

  static TextStyle get inputText => AwikiMeTheme.tokens.inputText;

  static TextStyle get fieldLabel => AwikiMeTheme.tokens.fieldLabel;

  static TextStyle get buttonLabel => AwikiMeTheme.tokens.buttonLabel;

  static TextStyle get pillLabel => AwikiMeTheme.tokens.pillLabel;

  static TextStyle get markdownBody => AwikiMeTheme.tokens.markdownBody;
}

class AwikiMeWidgets {
  static Widget pageBackground({required Widget child}) {
    return Builder(
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(color: context.awikiTheme.background),
        child: child,
      ),
    );
  }

  static Widget frostedBottomBar({required Widget child}) {
    return Builder(
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AwikiMeRadii.lg),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.awikiTheme.surface.withValues(alpha: 0.8),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AwikiMeRadii.lg),
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x14825500),
                  blurRadius: 40,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class AwikiMeIcons {
  static const IconData messages = CupertinoIcons.chat_bubble_2;
  static const IconData contacts = CupertinoIcons.person_2;
  static const IconData profile = CupertinoIcons.person;
}
