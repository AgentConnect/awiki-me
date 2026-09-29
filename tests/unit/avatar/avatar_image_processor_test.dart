import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:awiki_me/src/data/avatar/avatar_image_processor.dart';
import 'package:awiki_me/src/data/avatar/avatar_image_cache.dart';

void main() {
  test('static HEIC reaches only the opted-in native header decoder', () {
    Uint8List header(String brand) => Uint8List.fromList([
      0,
      0,
      0,
      24,
      ...'ftyp'.codeUnits,
      ...brand.codeUnits,
      0,
      0,
      0,
      0,
    ]);
    expect(() => validateAvatarSource(header('heic')), throwsFormatException);
    expect(
      () => validateAvatarSource(header('heic'), allowNativeHeic: true),
      returnsNormally,
    );
    for (final brand in ['hevc', 'hevx', 'avif', 'xxxx']) {
      expect(
        () => validateAvatarSource(header(brand), allowNativeHeic: true),
        throwsFormatException,
      );
    }
  });

  test(
    'avatar inputs are bounded before decode and animated formats are rejected',
    () {
      expect(
        () => validateAvatarSource(Uint8List(avatarSourceByteLimit + 1)),
        throwsFormatException,
      );
      expect(
        () => validateAvatarSource(Uint8List.fromList('<svg/>'.codeUnits)),
        throwsFormatException,
      );
      final oversized = img.Image(width: 16385, height: 1);
      expect(
        () => validateAvatarSource(img.encodePng(oversized)),
        throwsFormatException,
      );
      final gif = img.encodeGif(img.Image(width: 4, height: 4));
      expect(() => validateAvatarSource(gif), throwsFormatException);
      expect(
        () => validateAvatarSource(
          img.encodePng(img.Image(width: 24, height: 12)),
        ),
        returnsNormally,
      );
    },
  );

  test(
    'encoding strips metadata, flattens transparency and fixes dimensions/size',
    () {
      final source = img.Image(width: 100, height: 100, numChannels: 4);
      source.textData = {'private': 'must not survive'};
      img.fill(source, color: img.ColorRgba8(200, 0, 0, 0));
      final bytes = encodeAvatarJpeg(img.encodePng(source));
      expect(bytes.length, lessThanOrEqualTo(512 * 1024));
      final result = img.decodeJpg(bytes)!;
      expect([result.width, result.height], [512, 512]);
      final pixel = result.getPixel(250, 250);
      expect(pixel.r, greaterThanOrEqualTo(250));
      expect(pixel.g, greaterThanOrEqualTo(250));
      expect(pixel.b, greaterThanOrEqualTo(250));
      expect(result.textData, isNull);
      expect(
        () => encodeAvatarJpeg(img.encodePng(img.Image(width: 10, height: 20))),
        throwsFormatException,
      );
    },
  );

  test('public avatar URLs reject credentials and unsafe schemes', () {
    for (final uri in [
      'http://example.com/a.jpg',
      'file:///a.jpg',
      'data:image/png;base64,AA',
      'https://user:password@example.com/a.jpg',
      'https://example.com/a.svg',
      'https://example.com/a.jpg#fragment',
    ]) {
      expect(safeAvatarUri(uri), isNull);
    }
    expect(safeAvatarUri('https://example.com/a.jpg'), isNotNull);
  });
}
