import 'dart:convert';

import 'package:flutter/cupertino.dart';

/// The generated fallback content for an identity without a custom avatar.
class DefaultAvatar {
  const DefaultAvatar({
    required this.text,
    required this.backgroundColor,
    required this.backgroundTopColor,
    required this.backgroundBottomColor,
  });

  final String text;
  final Color backgroundColor;
  final Color backgroundTopColor;
  final Color backgroundBottomColor;
}

DefaultAvatar generateDefaultAvatar({required String name, String? userId}) {
  final colorIdentity = userId?.trim().isNotEmpty == true ? userId! : name;
  final backgroundColor = defaultAvatarColor(colorIdentity);
  final gradient = defaultAvatarGradientColors(backgroundColor);
  return DefaultAvatar(
    text: extractDefaultAvatarText(name),
    backgroundColor: backgroundColor,
    backgroundTopColor: gradient.top,
    backgroundBottomColor: gradient.bottom,
  );
}

String extractDefaultAvatarText(String rawInput) {
  final normalized = _normalizeAvatarInput(rawInput);
  if (normalized.isEmpty) {
    return '?';
  }

  final runes = normalized.runes.toList(growable: false);
  final hasHan = runes.any(_isHan);
  final hasLatin = runes.any(_isAsciiLetter);

  if (hasHan && hasLatin) {
    return _mixedLanguageInitials(runes);
  }
  if (hasHan) {
    final han = runes.where(_isHan).toList(growable: false);
    return String.fromCharCodes(han.skip(han.length > 3 ? han.length - 3 : 0));
  }
  if (!hasLatin && runes.any(_isAsciiDigit)) {
    return '#';
  }

  final words = _splitLatinWords(normalized);
  if (words.isEmpty) {
    return '?';
  }
  if (words.length == 1) {
    return words.first.substring(0, 1).toUpperCase();
  }
  return '${words[0][0]}${words[1][0]}'.toUpperCase();
}

Color defaultAvatarColor(String identity) {
  final normalizedIdentity = _normalizeAvatarInput(identity).toLowerCase();
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(normalizedIdentity)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  final hue = (hash % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.6, 0.5).toColor();
}

({Color top, Color bottom}) defaultAvatarGradientColors(Color baseColor) {
  final hsl = HSLColor.fromColor(baseColor);
  return (
    top: hsl.withLightness(0.38).toColor(),
    bottom: hsl.withLightness(0.58).toColor(),
  );
}

String _normalizeAvatarInput(String rawInput) {
  var value = rawInput.trim();
  if (value.isEmpty) {
    return '';
  }

  final emailSeparator = value.indexOf('@');
  if (emailSeparator > 0) {
    value = value.substring(0, emailSeparator);
  }

  final runes = value.runes.toList(growable: false);
  var firstContentIndex = 0;
  while (firstContentIndex < runes.length &&
      !_isHan(runes[firstContentIndex]) &&
      !_isAsciiLetter(runes[firstContentIndex]) &&
      !_isAsciiDigit(runes[firstContentIndex])) {
    firstContentIndex++;
  }
  value = String.fromCharCodes(runes.skip(firstContentIndex));
  return value
      .replaceAll(RegExp(r'[\s_.-]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

List<String> _splitLatinWords(String normalized) {
  final camelSeparated = normalized.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])|([A-Z])([A-Z])(?=[a-z])'),
    (match) {
      if (match.group(1) != null) {
        return '${match.group(1)} ${match.group(2)}';
      }
      return '${match.group(3)} ${match.group(4)}';
    },
  );
  return camelSeparated
      .split(RegExp(r'\s+'))
      .where((word) => word.runes.any(_isAsciiLetter))
      .toList(growable: false);
}

String _mixedLanguageInitials(List<int> runes) {
  final initials = <int>[];
  for (var index = 0; index < runes.length && initials.length < 2; index++) {
    final rune = runes[index];
    if (_isHan(rune)) {
      initials.add(rune);
      continue;
    }
    if (!_isAsciiLetter(rune)) {
      continue;
    }
    final previous = index == 0 ? null : runes[index - 1];
    final startsLatinWord = previous == null || !_isAsciiLetter(previous);
    final startsCamelWord =
        previous != null &&
        _isAsciiLowercase(previous) &&
        _isAsciiUppercase(rune);
    if (startsLatinWord || startsCamelWord) {
      initials.add(_asciiUppercase(rune));
    }
  }
  return String.fromCharCodes(initials);
}

bool _isHan(int rune) =>
    (rune >= 0x3400 && rune <= 0x4dbf) ||
    (rune >= 0x4e00 && rune <= 0x9fff) ||
    (rune >= 0x20000 && rune <= 0x2fa1f);

bool _isAsciiLetter(int rune) =>
    _isAsciiUppercase(rune) || _isAsciiLowercase(rune);

bool _isAsciiUppercase(int rune) => rune >= 0x41 && rune <= 0x5a;

bool _isAsciiLowercase(int rune) => rune >= 0x61 && rune <= 0x7a;

bool _isAsciiDigit(int rune) => rune >= 0x30 && rune <= 0x39;

int _asciiUppercase(int rune) => _isAsciiLowercase(rune) ? rune - 0x20 : rune;
