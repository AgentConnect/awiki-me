abstract interface class FontSizePreferenceService {
  Future<double> loadFontSize();

  Future<void> saveFontSize(double fontSize);
}

final class NoopFontSizePreferenceService implements FontSizePreferenceService {
  const NoopFontSizePreferenceService();

  @override
  Future<double> loadFontSize() async => AwikiFontSize.standard;

  @override
  Future<void> saveFontSize(double fontSize) async {}
}

class AwikiFontSize {
  const AwikiFontSize._();

  static const double min = 12;
  static const double max = 22;
  static const double standard = 14;
  static const int divisions = 10;

  static double normalize(double value) {
    if (!value.isFinite) return standard;
    return value.roundToDouble().clamp(min, max).toDouble();
  }

  static double scaleFactor(double value) => normalize(value) / standard;
}
