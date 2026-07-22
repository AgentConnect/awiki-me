import 'package:awiki_me/src/application/attachment_resource_reference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttachmentResourceReference Windows paths', () {
    for (final path in <String>[
      r'C:\Users\00sea\AppData\Local\AWiki\report.png',
      'c:/Users/00sea/My Files/报告.png',
      r'\\server\shared folder\报告 100%.png',
      r'\\?\C:\Users\00sea\long path\报告 100%.png',
      r'\\?\UNC\server\share\long path\报告.png',
    ]) {
      test('keeps $path as a local file before URI parsing', () {
        final reference = AttachmentResourceReference.parse(
          path,
          windows: true,
        );

        expect(reference.isLocalFile, isTrue);
        expect(reference.localPath, path);
        expect(reference.uri, Uri.file(path, windows: true));
      });
    }
  });

  test('Windows file URI round-trips Unicode, spaces, and literal percent', () {
    const path = r'C:\Users\00sea\AWiki Me\截图 100%.png';
    final uri = Uri.file(path, windows: true);

    final reference = AttachmentResourceReference.parse(
      uri.toString(),
      windows: true,
    );

    expect(reference.isLocalFile, isTrue);
    expect(reference.localPath, path);
    expect(reference.uri, uri);
  });

  test('HTTPS attachment remains a remote URI', () {
    final reference = AttachmentResourceReference.parse(
      'https://cdn.example.test/files/report%20final.png',
      windows: true,
    );

    expect(reference.isLocalFile, isFalse);
    expect(reference.localPath, isNull);
    expect(
      reference.uri,
      Uri.parse('https://cdn.example.test/files/report%20final.png'),
    );
  });
}
