final class TextClipboardWriteResult {
  const TextClipboardWriteResult._({required this.succeeded, this.error});

  const TextClipboardWriteResult.success() : this._(succeeded: true);

  const TextClipboardWriteResult.failure(Object error)
    : this._(succeeded: false, error: error);

  final bool succeeded;
  final Object? error;
}

abstract interface class TextClipboardService {
  Future<TextClipboardWriteResult> writeText(String text);

  Future<String?> readText();
}
