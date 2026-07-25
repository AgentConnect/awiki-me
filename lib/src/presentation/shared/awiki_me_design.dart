import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart'
    show ColorScheme, TextTheme, Theme, ThemeData, ThemeExtension;

class AwikiMePalette {
  // The neutral light palette is derived from the approved HTML prototypes.
  static const Color canvas = Color(0xFFFAF9F7);
  static const Color content = Color(0xFFFFFFFF);
  static const Color inkNeutral = Color(0xFF2D2B26);
  static const Color mutedNeutral = Color(0xFF6B6963);
  static const Color hairline = Color(0xFFE8E7E4);
  static const Color brandAccent = Color(0xFF0081D3);
  static const Color brandAccentPressed = Color(0xFF006EBA);
  static const Color brandAccentSoft = Color(0xFFE0F0FA);
  static const Color badgeBlue = Color(0xFF1A8FCF);
  static const Color successGreen = Color(0xFF03A14A);
  static const Color warningGold = Color(0xFFDA950B);
  static const Color dangerRed = Color(0xFFD73431);
  static const Color unreadRed = Color(0xFFFA5152);
  static const Color navigationSurface = Color(0xFFEEEDE9);
  static const Color navigationBorder = Color(0xFFDDDCD9);
  static const Color chatSurface = Color(0xFFFAFAFA);
  static const Color messageIncoming = Color(0xFFEEEEF0);
  static const Color messageOutgoing = Color(0xFFB6E4FF);
  static const Color onMessageOutgoing = Color(0xFF0F304A);
  static const Color messagePreview = Color(0xFF9F9FA6);

  // Legacy names resolve to the same semantic palette so screens still being
  // migrated cannot silently reintroduce the previous blue-gray theme.
  static const Color amber = warningGold;
  static const Color amberDeep = Color(0xFF805400);
  static const Color actionBlue = brandAccent;
  static const Color actionBlueDeep = brandAccentPressed;
  static const Color actionBlueSoft = brandAccentSoft;
  static const Color actionBlueBorder = hairline;
  static const Color actionInk = inkNeutral;
  static const Color actionMuted = mutedNeutral;
  static const Color ivory = canvas;
  static const Color white = Color(0xFFFFFFFF);
  static const Color mist = Color(0xFFF4F4F3);
  static const Color cloud = messageIncoming;
  static const Color line = hairline;
  static const Color ink = inkNeutral;
  static const Color body = inkNeutral;
  static const Color slate = mutedNeutral;
  static const Color fog = messagePreview;
  static const Color success = successGreen;
  static const Color error = dangerRed;
  static const Color alert = Color(0xFFFF7B61);
  static const Color warningContainer = Color(0xFFFFF4D6);
  static const Color errorContainer = Color(0xFFFFEBEB);
  static const Color infoBlue = Color(0xFF2563EB);
}

class AwikiMeColors {
  static const Color background = AwikiMePalette.canvas;
  static const Color surface = AwikiMePalette.content;
  static const Color subtleSurface = Color(0xFFF4F4F3);
  static const Color mutedSurface = AwikiMePalette.messageIncoming;
  static const Color border = AwikiMePalette.hairline;
  static const Color primary = AwikiMePalette.brandAccent;
  static const Color primaryDark = AwikiMePalette.brandAccentPressed;
  static const Color title = AwikiMePalette.inkNeutral;
  static const Color body = AwikiMePalette.inkNeutral;
  static const Color secondaryText = AwikiMePalette.mutedNeutral;
  static const Color tertiaryText = AwikiMePalette.messagePreview;
  static const Color online = AwikiMePalette.successGreen;
  static const Color danger = AwikiMePalette.dangerRed;
  static const Color alert = AwikiMePalette.alert;
}

class AwikiMeInsets {
  static const double xxs = 2;
  static const double xs = 4;
  static const double compact = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double display = 40;

  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: xxl);
  static const EdgeInsets card = EdgeInsets.all(lg);
  static const EdgeInsets compactPage = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets expandedPage = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets compactCard = EdgeInsets.all(md);
  static const EdgeInsets expandedCard = EdgeInsets.all(lg);
}

class AwikiMeRadii {
  static const double xs = 4;
  static const double control = 10;
  static const double sm = 12;
  static const double messageCompact = 13;
  static const double overlay = 14;
  static const double md = 16;
  static const double lg = 20;
  static const double pill = 999;
}

class AwikiMeMotion {
  static const Duration instant = Duration(milliseconds: 50);
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 150);
  static const Duration feedback = Duration(milliseconds: 180);
  static const Duration sheet = Duration(milliseconds: 300);
  static const Duration splash = Duration(milliseconds: 2800);

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve sheetCurve = Cubic(0.32, 0.72, 0.35, 1);
}

class AwikiMeShadows {
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Color(0x0C000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> overlay = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

enum AwikiMeTypographyMode { compact, expanded }

@immutable
class AwikiMeTypographyTokens {
  const AwikiMeTypographyTokens({
    required this.displayTitle,
    required this.sectionTitle,
    required this.navTitle,
    required this.cardTitle,
    required this.cardSubtitle,
    required this.meta,
    required this.listTitle,
    required this.listSubtitle,
    required this.listMeta,
    required this.body,
    required this.messageBody,
    required this.inputText,
    required this.fieldLabel,
    required this.buttonLabel,
    required this.pillLabel,
    required this.markdownBody,
  });

  final TextStyle displayTitle;
  final TextStyle sectionTitle;
  final TextStyle navTitle;
  final TextStyle cardTitle;
  final TextStyle cardSubtitle;
  final TextStyle meta;
  final TextStyle listTitle;
  final TextStyle listSubtitle;
  final TextStyle listMeta;
  final TextStyle body;
  final TextStyle messageBody;
  final TextStyle inputText;
  final TextStyle fieldLabel;
  final TextStyle buttonLabel;
  final TextStyle pillLabel;
  final TextStyle markdownBody;

  Iterable<TextStyle> get styles => <TextStyle>[
    displayTitle,
    sectionTitle,
    navTitle,
    cardTitle,
    cardSubtitle,
    meta,
    listTitle,
    listSubtitle,
    listMeta,
    body,
    messageBody,
    inputText,
    fieldLabel,
    buttonLabel,
    pillLabel,
    markdownBody,
  ];

  AwikiMeTypographyTokens copyWith({
    TextStyle? displayTitle,
    TextStyle? sectionTitle,
    TextStyle? navTitle,
    TextStyle? cardTitle,
    TextStyle? cardSubtitle,
    TextStyle? meta,
    TextStyle? listTitle,
    TextStyle? listSubtitle,
    TextStyle? listMeta,
    TextStyle? body,
    TextStyle? messageBody,
    TextStyle? inputText,
    TextStyle? fieldLabel,
    TextStyle? buttonLabel,
    TextStyle? pillLabel,
    TextStyle? markdownBody,
  }) {
    return AwikiMeTypographyTokens(
      displayTitle: displayTitle ?? this.displayTitle,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      navTitle: navTitle ?? this.navTitle,
      cardTitle: cardTitle ?? this.cardTitle,
      cardSubtitle: cardSubtitle ?? this.cardSubtitle,
      meta: meta ?? this.meta,
      listTitle: listTitle ?? this.listTitle,
      listSubtitle: listSubtitle ?? this.listSubtitle,
      listMeta: listMeta ?? this.listMeta,
      body: body ?? this.body,
      messageBody: messageBody ?? this.messageBody,
      inputText: inputText ?? this.inputText,
      fieldLabel: fieldLabel ?? this.fieldLabel,
      buttonLabel: buttonLabel ?? this.buttonLabel,
      pillLabel: pillLabel ?? this.pillLabel,
      markdownBody: markdownBody ?? this.markdownBody,
    );
  }

  AwikiMeTypographyTokens withFont({
    required String fontFamily,
    required List<String> fontFamilyFallback,
  }) {
    TextStyle apply(TextStyle style) => style.copyWith(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      letterSpacing: 0,
    );

    return AwikiMeTypographyTokens(
      displayTitle: apply(displayTitle),
      sectionTitle: apply(sectionTitle),
      navTitle: apply(navTitle),
      cardTitle: apply(cardTitle),
      cardSubtitle: apply(cardSubtitle),
      meta: apply(meta),
      listTitle: apply(listTitle),
      listSubtitle: apply(listSubtitle),
      listMeta: apply(listMeta),
      body: apply(body),
      messageBody: apply(messageBody),
      inputText: apply(inputText),
      fieldLabel: apply(fieldLabel),
      buttonLabel: apply(buttonLabel),
      pillLabel: apply(pillLabel),
      markdownBody: apply(markdownBody),
    );
  }

  static AwikiMeTypographyTokens lerp(
    AwikiMeTypographyTokens a,
    AwikiMeTypographyTokens b,
    double t,
  ) {
    TextStyle blend(TextStyle left, TextStyle right) =>
        TextStyle.lerp(left, right, t)!;

    return AwikiMeTypographyTokens(
      displayTitle: blend(a.displayTitle, b.displayTitle),
      sectionTitle: blend(a.sectionTitle, b.sectionTitle),
      navTitle: blend(a.navTitle, b.navTitle),
      cardTitle: blend(a.cardTitle, b.cardTitle),
      cardSubtitle: blend(a.cardSubtitle, b.cardSubtitle),
      meta: blend(a.meta, b.meta),
      listTitle: blend(a.listTitle, b.listTitle),
      listSubtitle: blend(a.listSubtitle, b.listSubtitle),
      listMeta: blend(a.listMeta, b.listMeta),
      body: blend(a.body, b.body),
      messageBody: blend(a.messageBody, b.messageBody),
      inputText: blend(a.inputText, b.inputText),
      fieldLabel: blend(a.fieldLabel, b.fieldLabel),
      buttonLabel: blend(a.buttonLabel, b.buttonLabel),
      pillLabel: blend(a.pillLabel, b.pillLabel),
      markdownBody: blend(a.markdownBody, b.markdownBody),
    );
  }
}

@immutable
class AwikiMeSemanticColors {
  const AwikiMeSemanticColors({
    required this.canvas,
    required this.surface,
    required this.subtleSurface,
    required this.mutedSurface,
    required this.navigationSurface,
    required this.navigationBorder,
    required this.chatSurface,
    required this.border,
    required this.primary,
    required this.primaryPressed,
    required this.primarySoft,
    required this.title,
    required this.body,
    required this.secondaryText,
    required this.tertiaryText,
    required this.success,
    required this.warning,
    required this.danger,
    required this.unread,
    required this.incomingMessage,
    required this.outgoingMessage,
    required this.onOutgoingMessage,
  });

  final Color canvas;
  final Color surface;
  final Color subtleSurface;
  final Color mutedSurface;
  final Color navigationSurface;
  final Color navigationBorder;
  final Color chatSurface;
  final Color border;
  final Color primary;
  final Color primaryPressed;
  final Color primarySoft;
  final Color title;
  final Color body;
  final Color secondaryText;
  final Color tertiaryText;
  final Color success;
  final Color warning;
  final Color danger;
  final Color unread;
  final Color incomingMessage;
  final Color outgoingMessage;
  final Color onOutgoingMessage;

  static AwikiMeSemanticColors lerp(
    AwikiMeSemanticColors a,
    AwikiMeSemanticColors b,
    double t,
  ) {
    Color blend(Color left, Color right) => Color.lerp(left, right, t)!;

    return AwikiMeSemanticColors(
      canvas: blend(a.canvas, b.canvas),
      surface: blend(a.surface, b.surface),
      subtleSurface: blend(a.subtleSurface, b.subtleSurface),
      mutedSurface: blend(a.mutedSurface, b.mutedSurface),
      navigationSurface: blend(a.navigationSurface, b.navigationSurface),
      navigationBorder: blend(a.navigationBorder, b.navigationBorder),
      chatSurface: blend(a.chatSurface, b.chatSurface),
      border: blend(a.border, b.border),
      primary: blend(a.primary, b.primary),
      primaryPressed: blend(a.primaryPressed, b.primaryPressed),
      primarySoft: blend(a.primarySoft, b.primarySoft),
      title: blend(a.title, b.title),
      body: blend(a.body, b.body),
      secondaryText: blend(a.secondaryText, b.secondaryText),
      tertiaryText: blend(a.tertiaryText, b.tertiaryText),
      success: blend(a.success, b.success),
      warning: blend(a.warning, b.warning),
      danger: blend(a.danger, b.danger),
      unread: blend(a.unread, b.unread),
      incomingMessage: blend(a.incomingMessage, b.incomingMessage),
      outgoingMessage: blend(a.outgoingMessage, b.outgoingMessage),
      onOutgoingMessage: blend(a.onOutgoingMessage, b.onOutgoingMessage),
    );
  }
}

@immutable
class AwikiMeThemeTokens extends ThemeExtension<AwikiMeThemeTokens> {
  const AwikiMeThemeTokens({
    required this.colorScheme,
    required this.semanticColors,
    required this.compactTypography,
    required this.expandedTypography,
    required this.cardShadow,
    required this.overlayShadow,
  });

  final ColorScheme colorScheme;
  final AwikiMeSemanticColors semanticColors;
  final AwikiMeTypographyTokens compactTypography;
  final AwikiMeTypographyTokens expandedTypography;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> overlayShadow;

  AwikiMeTypographyTokens typographyFor(AwikiMeTypographyMode mode) =>
      mode == AwikiMeTypographyMode.compact
      ? compactTypography
      : expandedTypography;

  // Existing callers retain the expanded type ramp until their layout picks a
  // density explicitly.
  TextStyle get sectionTitle => expandedTypography.sectionTitle;
  TextStyle get navTitle => expandedTypography.navTitle;
  TextStyle get cardTitle => expandedTypography.cardTitle;
  TextStyle get cardSubtitle => expandedTypography.cardSubtitle;
  TextStyle get meta => expandedTypography.meta;
  TextStyle get listTitle => expandedTypography.listTitle;
  TextStyle get listSubtitle => expandedTypography.listSubtitle;
  TextStyle get listMeta => expandedTypography.listMeta;
  TextStyle get messageBody => expandedTypography.messageBody;
  TextStyle get inputText => expandedTypography.inputText;
  TextStyle get fieldLabel => expandedTypography.fieldLabel;
  TextStyle get buttonLabel => expandedTypography.buttonLabel;
  TextStyle get pillLabel => expandedTypography.pillLabel;
  TextStyle get markdownBody => expandedTypography.markdownBody;

  Color get background => semanticColors.canvas;
  Color get surface => semanticColors.surface;
  Color get subtleSurface => semanticColors.subtleSurface;
  Color get mutedSurface => semanticColors.mutedSurface;
  Color get navigationSurface => semanticColors.navigationSurface;
  Color get navigationBorder => semanticColors.navigationBorder;
  Color get chatSurface => semanticColors.chatSurface;
  Color get border => semanticColors.border;
  Color get primary => semanticColors.primary;
  Color get primaryForeground => colorScheme.onPrimary;
  Color get primaryDark => semanticColors.primaryPressed;
  Color get primarySoft => semanticColors.primarySoft;
  Color get title => semanticColors.title;
  Color get body => semanticColors.body;
  Color get secondaryText => semanticColors.secondaryText;
  Color get tertiaryText => semanticColors.tertiaryText;
  Color get success => semanticColors.success;
  Color get warning => semanticColors.warning;
  Color get danger => semanticColors.danger;
  Color get unread => semanticColors.unread;
  Color get incomingMessage => semanticColors.incomingMessage;
  Color get outgoingMessage => semanticColors.outgoingMessage;
  Color get onOutgoingMessage => semanticColors.onOutgoingMessage;
  Color get alert => AwikiMePalette.alert;
  Color get warningContainer => AwikiMePalette.warningContainer;
  Color get dangerContainer => AwikiMePalette.errorContainer;
  Color get infoAccent => AwikiMePalette.infoBlue;

  @override
  AwikiMeThemeTokens copyWith({
    ColorScheme? colorScheme,
    AwikiMeSemanticColors? semanticColors,
    AwikiMeTypographyTokens? compactTypography,
    AwikiMeTypographyTokens? expandedTypography,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? overlayShadow,
  }) {
    return AwikiMeThemeTokens(
      colorScheme: colorScheme ?? this.colorScheme,
      semanticColors: semanticColors ?? this.semanticColors,
      compactTypography: compactTypography ?? this.compactTypography,
      expandedTypography: expandedTypography ?? this.expandedTypography,
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
      semanticColors: AwikiMeSemanticColors.lerp(
        semanticColors,
        other.semanticColors,
        t,
      ),
      compactTypography: AwikiMeTypographyTokens.lerp(
        compactTypography,
        other.compactTypography,
        t,
      ),
      expandedTypography: AwikiMeTypographyTokens.lerp(
        expandedTypography,
        other.expandedTypography,
        t,
      ),
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
      overlayShadow: t < 0.5 ? overlayShadow : other.overlayShadow,
    );
  }
}

@immutable
class AwikiMePlatformTheme {
  const AwikiMePlatformTheme({
    required this.materialTheme,
    required this.cupertinoTheme,
    required this.tokens,
  });

  final ThemeData materialTheme;
  final CupertinoThemeData cupertinoTheme;
  final AwikiMeThemeTokens tokens;
}

class AwikiMeTheme {
  static const String windowsFontFamily = 'Segoe UI';
  static const List<String> windowsFontFamilyFallback = <String>[
    'Microsoft YaHei UI',
    'Microsoft JhengHei UI',
    'Yu Gothic UI',
    'Malgun Gothic',
  ];
  static final Map<TargetPlatform, AwikiMePlatformTheme> _platformThemes =
      <TargetPlatform, AwikiMePlatformTheme>{};

  static const ColorScheme colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AwikiMePalette.brandAccent,
    onPrimary: AwikiMePalette.content,
    secondary: AwikiMePalette.badgeBlue,
    onSecondary: AwikiMePalette.content,
    error: AwikiMePalette.dangerRed,
    onError: AwikiMePalette.content,
    surface: AwikiMePalette.content,
    onSurface: AwikiMePalette.inkNeutral,
    surfaceContainerHighest: AwikiMePalette.messageIncoming,
    onSurfaceVariant: AwikiMePalette.mutedNeutral,
    outline: AwikiMePalette.messagePreview,
    outlineVariant: AwikiMePalette.hairline,
    primaryContainer: AwikiMePalette.brandAccentSoft,
    onPrimaryContainer: AwikiMePalette.brandAccent,
    secondaryContainer: Color(0xFFDFF1FA),
    onSecondaryContainer: AwikiMePalette.badgeBlue,
    errorContainer: AwikiMePalette.errorContainer,
    onErrorContainer: AwikiMePalette.dangerRed,
    surfaceContainerLow: Color(0xFFF4F4F3),
    surfaceContainerLowest: AwikiMePalette.canvas,
    tertiary: AwikiMePalette.successGreen,
    onTertiary: AwikiMePalette.content,
    tertiaryContainer: Color(0xFFDCF1E2),
    onTertiaryContainer: AwikiMePalette.successGreen,
    inverseSurface: AwikiMePalette.inkNeutral,
    onInverseSurface: AwikiMePalette.content,
    inversePrimary: AwikiMePalette.brandAccent,
    shadow: Color(0x1A000000),
    scrim: Color(0x52000000),
    surfaceTint: Color(0x00000000),
  );

  static const AwikiMeSemanticColors _semanticColors = AwikiMeSemanticColors(
    canvas: AwikiMePalette.canvas,
    surface: AwikiMePalette.content,
    subtleSurface: Color(0xFFF4F4F3),
    mutedSurface: AwikiMePalette.messageIncoming,
    navigationSurface: AwikiMePalette.navigationSurface,
    navigationBorder: AwikiMePalette.navigationBorder,
    chatSurface: AwikiMePalette.chatSurface,
    border: AwikiMePalette.hairline,
    primary: AwikiMePalette.brandAccent,
    primaryPressed: AwikiMePalette.brandAccentPressed,
    primarySoft: AwikiMePalette.brandAccentSoft,
    title: AwikiMePalette.inkNeutral,
    body: AwikiMePalette.inkNeutral,
    secondaryText: AwikiMePalette.mutedNeutral,
    tertiaryText: AwikiMePalette.messagePreview,
    success: AwikiMePalette.successGreen,
    warning: AwikiMePalette.warningGold,
    danger: AwikiMePalette.dangerRed,
    unread: AwikiMePalette.unreadRed,
    incomingMessage: AwikiMePalette.messageIncoming,
    outgoingMessage: AwikiMePalette.messageOutgoing,
    onOutgoingMessage: AwikiMePalette.onMessageOutgoing,
  );

  static const AwikiMeTypographyTokens _compactTypography =
      AwikiMeTypographyTokens(
        displayTitle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AwikiMePalette.inkNeutral,
          height: 1.2,
          letterSpacing: 0,
        ),
        sectionTitle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AwikiMePalette.inkNeutral,
          height: 1.25,
          letterSpacing: 0,
        ),
        navTitle: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: AwikiMePalette.inkNeutral,
          height: 1.25,
          letterSpacing: 0,
        ),
        cardTitle: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AwikiMePalette.inkNeutral,
          height: 1.3,
          letterSpacing: 0,
        ),
        cardSubtitle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.mutedNeutral,
          height: 1.4,
          letterSpacing: 0,
        ),
        meta: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.messagePreview,
          height: 1.25,
          letterSpacing: 0,
        ),
        listTitle: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: AwikiMePalette.inkNeutral,
          height: 1.3,
          letterSpacing: 0,
        ),
        listSubtitle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.messagePreview,
          height: 1.3,
          letterSpacing: 0,
        ),
        listMeta: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.mutedNeutral,
          height: 1.2,
          letterSpacing: 0,
        ),
        body: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.inkNeutral,
          height: 1.45,
          letterSpacing: 0,
        ),
        messageBody: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.inkNeutral,
          height: 1.45,
          letterSpacing: 0,
        ),
        inputText: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.inkNeutral,
          height: 1.3,
          letterSpacing: 0,
        ),
        fieldLabel: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: AwikiMePalette.mutedNeutral,
          height: 1.25,
          letterSpacing: 0,
        ),
        buttonLabel: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          height: 1.2,
          letterSpacing: 0,
        ),
        pillLabel: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.2,
          letterSpacing: 0,
        ),
        markdownBody: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.inkNeutral,
          height: 1.5,
          letterSpacing: 0,
        ),
      );

  static const AwikiMeTypographyTokens _expandedTypography =
      AwikiMeTypographyTokens(
        displayTitle: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: AwikiMePalette.inkNeutral,
          height: 1.15,
          letterSpacing: 0,
        ),
        sectionTitle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AwikiMePalette.inkNeutral,
          height: 1.2,
          letterSpacing: 0,
        ),
        navTitle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AwikiMePalette.inkNeutral,
          height: 1.25,
          letterSpacing: 0,
        ),
        cardTitle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AwikiMePalette.inkNeutral,
          height: 1.3,
          letterSpacing: 0,
        ),
        cardSubtitle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.mutedNeutral,
          height: 1.4,
          letterSpacing: 0,
        ),
        meta: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.messagePreview,
          height: 1.25,
          letterSpacing: 0,
        ),
        listTitle: TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w500,
          color: AwikiMePalette.inkNeutral,
          height: 1.3,
          letterSpacing: 0,
        ),
        listSubtitle: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.messagePreview,
          height: 1.3,
          letterSpacing: 0,
        ),
        listMeta: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.mutedNeutral,
          height: 1.2,
          letterSpacing: 0,
        ),
        body: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.inkNeutral,
          height: 1.45,
          letterSpacing: 0,
        ),
        messageBody: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.inkNeutral,
          height: 1.45,
          letterSpacing: 0,
        ),
        inputText: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.inkNeutral,
          height: 1.3,
          letterSpacing: 0,
        ),
        fieldLabel: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: AwikiMePalette.mutedNeutral,
          height: 1.25,
          letterSpacing: 0,
        ),
        buttonLabel: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.2,
          letterSpacing: 0,
        ),
        pillLabel: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.2,
          letterSpacing: 0,
        ),
        markdownBody: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AwikiMePalette.inkNeutral,
          height: 1.5,
          letterSpacing: 0,
        ),
      );

  static const AwikiMeThemeTokens _baseTokens = AwikiMeThemeTokens(
    colorScheme: colorScheme,
    semanticColors: _semanticColors,
    compactTypography: _compactTypography,
    expandedTypography: _expandedTypography,
    cardShadow: AwikiMeShadows.card,
    overlayShadow: AwikiMeShadows.overlay,
  );

  static AwikiMePlatformTheme forPlatform(TargetPlatform platform) =>
      _platformThemes.putIfAbsent(platform, () => _buildForPlatform(platform));

  static AwikiMePlatformTheme _buildForPlatform(TargetPlatform platform) {
    final isWindows = platform == TargetPlatform.windows;
    final platformTokens = isWindows ? _windowsTokens() : _baseTokens;
    final baseMaterialTheme = ThemeData(
      useMaterial3: true,
      platform: platform,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
      fontFamily: isWindows ? windowsFontFamily : null,
      fontFamilyFallback: isWindows ? windowsFontFamilyFallback : null,
      extensions: <ThemeExtension<dynamic>>[platformTokens],
    );
    return AwikiMePlatformTheme(
      materialTheme: baseMaterialTheme.copyWith(
        textTheme: _materialTextThemeFor(baseMaterialTheme.textTheme, platform),
        primaryTextTheme: _materialTextThemeFor(
          baseMaterialTheme.primaryTextTheme,
          platform,
        ),
      ),
      cupertinoTheme: CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: colorScheme.primary,
        scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
        barBackgroundColor: colorScheme.surface,
        textTheme: _cupertinoTextThemeFor(platform),
      ),
      tokens: platformTokens,
    );
  }

  static AwikiMePlatformTheme get current => forPlatform(defaultTargetPlatform);

  static ThemeData get materialTheme => current.materialTheme;

  static CupertinoThemeData get cupertinoTheme => current.cupertinoTheme;

  static AwikiMeThemeTokens get tokens => current.tokens;

  static AwikiMeThemeTokens _windowsTokens() {
    return _baseTokens.copyWith(
      compactTypography: _baseTokens.compactTypography.withFont(
        fontFamily: windowsFontFamily,
        fontFamilyFallback: windowsFontFamilyFallback,
      ),
      expandedTypography: _baseTokens.expandedTypography.withFont(
        fontFamily: windowsFontFamily,
        fontFamilyFallback: windowsFontFamilyFallback,
      ),
    );
  }

  static TextTheme _materialTextThemeFor(
    TextTheme base,
    TargetPlatform platform,
  ) {
    TextStyle? normalize(TextStyle? style) {
      if (style == null) {
        return null;
      }
      if (platform == TargetPlatform.windows) {
        return style.copyWith(
          fontFamily: windowsFontFamily,
          fontFamilyFallback: windowsFontFamilyFallback,
          letterSpacing: 0,
        );
      }
      return style.copyWith(letterSpacing: 0);
    }

    return base.copyWith(
      displayLarge: normalize(base.displayLarge),
      displayMedium: normalize(base.displayMedium),
      displaySmall: normalize(base.displaySmall),
      headlineLarge: normalize(base.headlineLarge),
      headlineMedium: normalize(base.headlineMedium),
      headlineSmall: normalize(base.headlineSmall),
      titleLarge: normalize(base.titleLarge),
      titleMedium: normalize(base.titleMedium),
      titleSmall: normalize(base.titleSmall),
      bodyLarge: normalize(base.bodyLarge),
      bodyMedium: normalize(base.bodyMedium),
      bodySmall: normalize(base.bodySmall),
      labelLarge: normalize(base.labelLarge),
      labelMedium: normalize(base.labelMedium),
      labelSmall: normalize(base.labelSmall),
    );
  }

  static CupertinoTextThemeData _cupertinoTextThemeFor(
    TargetPlatform platform,
  ) {
    const base = CupertinoTextThemeData(
      primaryColor: AwikiMePalette.brandAccent,
      textStyle: TextStyle(
        color: AwikiMePalette.inkNeutral,
        fontSize: 15,
        letterSpacing: 0,
      ),
    );
    TextStyle normalize(TextStyle style) => platform == TargetPlatform.windows
        ? style.copyWith(
            fontFamily: windowsFontFamily,
            fontFamilyFallback: windowsFontFamilyFallback,
            letterSpacing: 0,
          )
        : style.copyWith(letterSpacing: 0);

    return CupertinoTextThemeData(
      primaryColor: colorScheme.primary,
      textStyle: normalize(base.textStyle),
      actionTextStyle: normalize(base.actionTextStyle),
      actionSmallTextStyle: normalize(base.actionSmallTextStyle),
      tabLabelTextStyle: normalize(base.tabLabelTextStyle),
      navTitleTextStyle: normalize(base.navTitleTextStyle),
      navLargeTitleTextStyle: normalize(base.navLargeTitleTextStyle),
      navActionTextStyle: normalize(base.navActionTextStyle),
      pickerTextStyle: normalize(base.pickerTextStyle),
      dateTimePickerTextStyle: normalize(base.dateTimePickerTextStyle),
    );
  }
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
  static AwikiMeTypographyTokens get compact =>
      AwikiMeTheme.tokens.compactTypography;

  static AwikiMeTypographyTokens get expanded =>
      AwikiMeTheme.tokens.expandedTypography;

  static AwikiMeTypographyTokens forMode(AwikiMeTypographyMode mode) =>
      AwikiMeTheme.tokens.typographyFor(mode);

  static TextStyle get displayTitle => expanded.displayTitle;

  static TextStyle get sectionTitle => AwikiMeTheme.tokens.sectionTitle;

  static TextStyle get navTitle => AwikiMeTheme.tokens.navTitle;

  static TextStyle get cardTitle => AwikiMeTheme.tokens.cardTitle;

  static TextStyle get cardSubtitle => AwikiMeTheme.tokens.cardSubtitle;

  static TextStyle get meta => AwikiMeTheme.tokens.meta;

  static TextStyle get listTitle => AwikiMeTheme.tokens.listTitle;

  static TextStyle get listSubtitle => AwikiMeTheme.tokens.listSubtitle;

  static TextStyle get listMeta => AwikiMeTheme.tokens.listMeta;

  static TextStyle get body => expanded.body;

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
