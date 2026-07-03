import 'package:markdown/markdown.dart' as md;

String markdownPlainTextPreview(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) {
    return '';
  }

  try {
    final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    final buffer = _MarkdownPreviewTextBuffer();
    for (final node in document.parse(normalized)) {
      buffer.writeNode(node);
      buffer.writeBlockBreak();
    }
    final parsed = _collapsePreviewWhitespace(buffer.text);
    return parsed.isEmpty ? normalized : parsed;
  } catch (_) {
    return normalized;
  }
}

String _collapsePreviewWhitespace(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

class _MarkdownPreviewTextBuffer {
  final StringBuffer _buffer = StringBuffer();

  String get text => _buffer.toString();

  void writeNode(md.Node node) {
    if (node is md.Text) {
      writeText(node.textContent);
      return;
    }
    if (node is md.Element) {
      writeElement(node);
      return;
    }
    writeText(node.textContent);
  }

  void writeElement(md.Element element) {
    switch (element.tag) {
      case 'br':
        writeSoftBreak();
        return;
      case 'hr':
        writeBlockBreak();
        return;
      case 'img':
        writeText(element.attributes['alt'] ?? '');
        return;
      case 'input':
        return;
      case 'li':
      case 'tr':
        writeChildren(element);
        writeSoftBreak();
        return;
      case 'th':
      case 'td':
        writeChildren(element);
        writeText(' ');
        return;
      case 'pre':
      case 'blockquote':
      case 'p':
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
      case 'ul':
      case 'ol':
      case 'table':
      case 'thead':
      case 'tbody':
        writeChildren(element);
        writeBlockBreak();
        return;
      default:
        writeChildren(element);
        return;
    }
  }

  void writeChildren(md.Element element) {
    final children = element.children;
    if (children == null) {
      return;
    }
    for (final child in children) {
      writeNode(child);
    }
  }

  void writeText(String value) {
    if (value.isEmpty) {
      return;
    }
    final text = value.replaceAll(RegExp(r'\s+'), ' ');
    if (text.trim().isEmpty) {
      writeSoftBreak();
      return;
    }
    if (text.startsWith(' ') &&
        _buffer.isNotEmpty &&
        !_endsWithWhitespace(_buffer.toString())) {
      _buffer.write(' ');
    }
    _buffer.write(text.trim());
    if (text.endsWith(' ')) {
      writeSoftBreak();
    }
  }

  void writeSoftBreak() {
    if (_buffer.isNotEmpty && !_endsWithWhitespace(_buffer.toString())) {
      _buffer.write(' ');
    }
  }

  void writeBlockBreak() => writeSoftBreak();
}

bool _endsWithWhitespace(String value) {
  if (value.isEmpty) {
    return false;
  }
  return RegExp(r'\s$').hasMatch(value);
}
