import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

class AwikiMeColors {
  static const Color background = Color(0xFFFAF9FE);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color subtleSurface = Color(0xFFF4F3F8);
  static const Color mutedSurface = Color(0xFFEEEDF3);
  static const Color border = Color(0xFFF0EDF5);
  static const Color primary = Color(0xFFFFAA00);
  static const Color primaryDark = Color(0xFF825500);
  static const Color title = Color(0xFF1A1C1C);
  static const Color body = Color(0xFF111827);
  static const Color secondaryText = Color(0xFF6B7280);
  static const Color tertiaryText = Color(0xFFA9A9A9);
  static const Color online = Color(0xFF31CE96);
  static const Color danger = Color(0xFFEF4444);
}

class AwikiMeInsets {
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: 24);
  static const EdgeInsets card = EdgeInsets.all(16);
}

class AwikiMeDecorations {
  static BoxDecoration card({
    Color color = AwikiMeColors.surface,
    double radius = 16,
    Border? border,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: border,
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x0C000000),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    );
  }
}

class AwikiMeTextStyles {
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AwikiMeColors.title,
  );

  static const TextStyle navTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AwikiMeColors.title,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AwikiMeColors.body,
  );

  static const TextStyle cardSubtitle = TextStyle(
    fontSize: 14,
    color: AwikiMeColors.secondaryText,
    height: 1.35,
  );

  static const TextStyle meta = TextStyle(
    fontSize: 11,
    color: AwikiMeColors.tertiaryText,
    letterSpacing: 0.4,
  );
}

class AwikiMeWidgets {
  static Widget pageBackground({required Widget child}) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AwikiMeColors.background),
      child: child,
    );
  }

  static Widget frostedBottomBar({required Widget child}) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xCCFFFFFF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: <BoxShadow>[
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
    );
  }
}

class AwikiMeIcons {
  static const IconData messages = Icons.chat_bubble;
  static const IconData contacts = Icons.groups_2_outlined;
  static const IconData profile = Icons.person_outline;
}
