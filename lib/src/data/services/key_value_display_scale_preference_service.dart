import '../../application/display_scale_preference_service.dart';
import 'app_key_value_store.dart';

final class KeyValueDisplayScalePreferenceService
    implements DisplayScalePreferenceService {
  KeyValueDisplayScalePreferenceService({required AppKeyValueStore storage})
    : _storage = storage;

  static const String _displayScaleKey = 'awiki_me_display_scale_v1';

  final AppKeyValueStore _storage;

  @override
  Future<double> loadScale() async {
    try {
      final raw = await _storage.read(key: _displayScaleKey);
      final parsed = raw == null ? null : double.tryParse(raw);
      return AwikiDisplayScale.nearestLevel(parsed ?? AwikiDisplayScale.normal);
    } on Object {
      return AwikiDisplayScale.normal;
    }
  }

  @override
  Future<void> saveScale(double scale) async {
    final normalized = AwikiDisplayScale.nearestLevel(scale);
    if (normalized == AwikiDisplayScale.normal) {
      await _storage.delete(key: _displayScaleKey);
      return;
    }
    await _storage.write(
      key: _displayScaleKey,
      value: normalized.toStringAsFixed(1),
    );
  }
}
