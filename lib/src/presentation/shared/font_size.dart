import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/font_size_preference_service.dart';

export '../../application/font_size_preference_service.dart' show AwikiFontSize;

class FontSizeController extends StateNotifier<double> {
  FontSizeController({
    double initialFontSize = AwikiFontSize.standard,
    FontSizePreferenceService preferenceService =
        const NoopFontSizePreferenceService(),
  }) : _preferenceService = preferenceService,
       super(AwikiFontSize.normalize(initialFontSize));

  final FontSizePreferenceService _preferenceService;
  Future<void> _pendingSave = Future<void>.value();

  double get fontSize => state;

  void setFontSize(double fontSize) {
    final normalized = AwikiFontSize.normalize(fontSize);
    if (state == normalized) return;
    state = normalized;
    _pendingSave = _pendingSave
        .then((_) => _preferenceService.saveFontSize(normalized))
        .catchError((Object _, StackTrace __) {});
  }

  void reset() => setFontSize(AwikiFontSize.standard);
}

final initialFontSizeProvider = Provider<double>(
  (ref) => AwikiFontSize.standard,
);

final fontSizePreferenceServiceProvider = Provider<FontSizePreferenceService>(
  (ref) => const NoopFontSizePreferenceService(),
);

final fontSizeProvider = StateNotifierProvider<FontSizeController, double>(
  (ref) => FontSizeController(
    initialFontSize: ref.watch(initialFontSizeProvider),
    preferenceService: ref.watch(fontSizePreferenceServiceProvider),
  ),
);

class AwikiFontSizeScope extends StatelessWidget {
  const AwikiFontSizeScope({
    super.key,
    required this.fontSize,
    required this.child,
  });

  final double fontSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final normalized = AwikiFontSize.normalize(fontSize);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(AwikiFontSize.scaleFactor(normalized)),
      ),
      child: child,
    );
  }
}
