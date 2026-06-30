import 'package:flutter/services.dart';

import 'document_picker_service.dart';

class MethodChannelDocumentPickerService implements DocumentPickerService {
  MethodChannelDocumentPickerService({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('ai.awiki.awikime/document_picker');

  final MethodChannel _channel;

  @override
  Future<Uint8List?> pickZipFile() async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('pickZipFile');
      return result;
    } on PlatformException catch (error) {
      throw StateError(_friendlyMessage(error));
    }
  }

  @override
  Future<String?> saveZipFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'saveZipFile',
        <String, Object?>{'file_name': fileName, 'bytes': bytes},
      );
      return result;
    } on PlatformException catch (error) {
      throw StateError(_friendlyMessage(error));
    }
  }

  String _friendlyMessage(PlatformException error) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return 'document_picker_failed';
  }
}
