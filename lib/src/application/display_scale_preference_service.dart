abstract interface class DisplayScalePreferenceService {
  Future<double> loadScale();

  Future<void> saveScale(double scale);
}

final class NoopDisplayScalePreferenceService
    implements DisplayScalePreferenceService {
  const NoopDisplayScalePreferenceService();

  @override
  Future<double> loadScale() async => AwikiDisplayScale.normal;

  @override
  Future<void> saveScale(double scale) async {}
}

class AwikiDisplayScale {
  const AwikiDisplayScale._();

  // The former user-facing 90% size is the new product 100% baseline.
  static const double layoutBaseline = 0.954;
  static const List<double> levels = <double>[0.8, 0.9, 1, 1.1, 1.2, 1.3];
  static const double min = 0.8;
  static const double max = 1.3;
  static const double normal = 1.0;

  static double normalize(double value) {
    if (!value.isFinite) return normal;
    return value.clamp(min, max).toDouble();
  }

  static double nearestLevel(double value) {
    final normalized = normalize(value);
    return levels.reduce(
      (closest, candidate) =>
          (candidate - normalized).abs() < (closest - normalized).abs()
          ? candidate
          : closest,
    );
  }

  static double effective(double userScale) {
    return normalize(userScale) * layoutBaseline;
  }

  static int levelIndex(double value) => levels.indexOf(nearestLevel(value));

  static double increase(double value) {
    final index = levelIndex(value);
    return levels[index < levels.length - 1 ? index + 1 : index];
  }

  static double decrease(double value) {
    final index = levelIndex(value);
    return levels[index > 0 ? index - 1 : index];
  }
}
