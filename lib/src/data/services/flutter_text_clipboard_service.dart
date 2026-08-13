import 'package:flutter/services.dart';

import '../../application/text_clipboard_service.dart';

final class FlutterTextClipboardService implements TextClipboardService {
  const FlutterTextClipboardService();

  @override
  Future<TextClipboardWriteResult> writeText(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return const TextClipboardWriteResult.success();
    } on Object catch (error) {
      return TextClipboardWriteResult.failure(error);
    }
  }

  @override
  Future<String?> readText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }
}
