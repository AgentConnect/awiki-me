import 'package:flutter_test/flutter_test.dart';
import '../../../tool/validate_test_catalog.dart' show catalogDocumentsMatch;

void main() {
  test('generated catalog accepts only platform newline differences', () {
    expect(catalogDocumentsMatch('A\r\nB\r\n', 'A\nB\n'), isTrue);
    expect(catalogDocumentsMatch('A\nB\n', 'A\r\nB\r\n'), isTrue);
  });
  test('catalog semantic and missing-line changes remain stale', () {
    expect(catalogDocumentsMatch('A\r\nchanged\r\n', 'A\nB\n'), isFalse);
    expect(catalogDocumentsMatch('A\n', 'A\nB\n'), isFalse);
  });
}
