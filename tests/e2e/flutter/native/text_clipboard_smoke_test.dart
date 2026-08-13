import 'dart:io';

import 'package:awiki_me/src/data/services/flutter_text_clipboard_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS text clipboard writes through the real platform channel', (
    tester,
  ) async {
    if (!Platform.isMacOS) {
      return;
    }

    const clipboard = FlutterTextClipboardService();
    final originalText = await clipboard.readText();
    final expected =
        'awiki-me-clipboard-smoke-${DateTime.now().microsecondsSinceEpoch}';

    try {
      final result = await clipboard.writeText(expected);
      expect(result.succeeded, isTrue, reason: '${result.error}');
      expect(await clipboard.readText(), expected);
    } finally {
      final restoreResult = await clipboard.writeText(originalText ?? '');
      expect(
        restoreResult.succeeded,
        isTrue,
        reason:
            'Failed to restore the original clipboard: '
            '${restoreResult.error}',
      );
    }
  });
}
