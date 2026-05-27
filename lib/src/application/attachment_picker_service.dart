import 'dart:typed_data';

import 'models/attachment_models.dart';

abstract interface class AttachmentPickerService {
  Future<AttachmentDraft?> pickAttachment();

  Future<String?> saveAttachment({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  });
}
