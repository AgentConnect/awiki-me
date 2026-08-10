import '../../application/font_size_preference_service.dart';
import 'app_key_value_store.dart';

final class KeyValueFontSizePreferenceService
    implements FontSizePreferenceService {
  KeyValueFontSizePreferenceService({required AppKeyValueStore storage})
    : _storage = storage;

  static const String _fontSizeKey = 'awiki_me_font_size_v1';

  final AppKeyValueStore _storage;

  @override
  Future<double> loadFontSize() async {
    try {
      final raw = await _storage.read(key: _fontSizeKey);
      final parsed = raw == null ? null : double.tryParse(raw);
      return AwikiFontSize.normalize(parsed ?? AwikiFontSize.standard);
    } on Object {
      return AwikiFontSize.standard;
    }
  }

  @override
  Future<void> saveFontSize(double fontSize) async {
    final normalized = AwikiFontSize.normalize(fontSize);
    if (normalized == AwikiFontSize.standard) {
      await _storage.delete(key: _fontSizeKey);
      return;
    }
    await _storage.write(
      key: _fontSizeKey,
      value: normalized.toStringAsFixed(0),
    );
  }
}
