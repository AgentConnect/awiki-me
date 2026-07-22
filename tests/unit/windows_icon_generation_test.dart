import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/generate_windows_icon.dart';

void main() {
  late Uint8List sourceBytes;
  late Uint8List generatedIcon;

  setUpAll(() async {
    sourceBytes = await File(windowsIconSourcePath).readAsBytes();
    generatedIcon = buildWindowsIcon(sourceBytes);
  });

  test(
    'Windows icon generation is deterministic and committed output is fresh',
    () async {
      expect(buildWindowsIcon(sourceBytes), orderedEquals(generatedIcon));
      expect(
        await File(windowsIconOutputPath).readAsBytes(),
        orderedEquals(generatedIcon),
      );
    },
  );

  test('Windows icon contains the required ordered 32-bit PNG frames', () {
    final entries = readWindowsIconEntries(generatedIcon);

    expect(
      entries.map((entry) => entry.width),
      orderedEquals(windowsIconSizes),
    );
    expect(
      entries.map((entry) => entry.height),
      orderedEquals(windowsIconSizes),
    );
    expect(entries.every((entry) => entry.bitsPerPixel == 32), isTrue);
    expect(entries.every((entry) => entry.dataLength > 8), isTrue);
  });
}
