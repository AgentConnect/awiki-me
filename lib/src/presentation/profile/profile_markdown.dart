class ProfileArticle {
  const ProfileArticle({required this.body});

  final String body;

  static ProfileArticle? fromMarkdown(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final blocks = trimmed
        .split(RegExp(r'\n\s*\n'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (blocks.isEmpty) {
      return null;
    }
    final first = blocks.first;
    if (!first.startsWith('# ')) {
      return null;
    }
    final bodyBlocks = blocks.skip(1).toList();
    if (bodyBlocks.isNotEmpty && bodyBlocks.first.startsWith('#')) {
      bodyBlocks.removeAt(0);
    }
    final body = bodyBlocks.join('\n\n');
    return ProfileArticle(body: body);
  }
}

bool looksLikeHtmlDocument(String raw) {
  final normalized = raw.trimLeft().toLowerCase();
  return normalized.startsWith('<!doctype html') ||
      normalized.startsWith('<html') ||
      (normalized.contains('<head') && normalized.contains('</head>')) ||
      (normalized.contains('<body') && normalized.contains('</body>'));
}
