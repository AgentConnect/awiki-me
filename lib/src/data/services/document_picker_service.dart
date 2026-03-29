import 'dart:typed_data';

abstract class DocumentPickerService {
  Future<String?> saveZipFile({
    required String fileName,
    required Uint8List bytes,
  });

  Future<Uint8List?> pickZipFile();
}
