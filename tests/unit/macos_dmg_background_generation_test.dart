import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../../tool/generate_macos_dmg_background.dart';

void main() {
  late Uint8List generated;
  late image.Image decoded;

  setUpAll(() async {
    generated = buildMacosDmgBackground();
    decoded = image.decodePng(generated)!;
  });

  test(
    'macOS DMG background is deterministic and committed output is fresh',
    () async {
      expect(buildMacosDmgBackground(), orderedEquals(generated));
      expect(
        await File(macosDmgBackgroundOutputPath).readAsBytes(),
        orderedEquals(generated),
      );
    },
  );

  test('macOS DMG background matches the Finder window and arrow layout', () {
    expect(decoded.width, macosDmgBackgroundWidth);
    expect(decoded.height, macosDmgBackgroundHeight);
    expect(_rgba(decoded.getPixel(0, 0)), <int>[246, 247, 249, 255]);
    expect(_rgba(decoded.getPixel(300, 180)), <int>[111, 117, 126, 255]);
    expect(_rgba(decoded.getPixel(220, 180)), <int>[246, 247, 249, 255]);
    expect(_rgba(decoded.getPixel(380, 180)), <int>[246, 247, 249, 255]);
  });
}

List<int> _rgba(image.Pixel pixel) => <int>[
  pixel.r.toInt(),
  pixel.g.toInt(),
  pixel.b.toInt(),
  pixel.a.toInt(),
];
