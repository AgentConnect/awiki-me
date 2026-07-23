import 'dart:io';

import 'package:awiki_me/src/application/attachment_image_dimensions.dart';
import 'package:awiki_me/src/data/services/flutter_attachment_image_dimension_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test(
    'reads encoded image dimensions without decoding a display frame',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-image-probe-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final file = File('${root.path}/portrait.png');
      await file.writeAsBytes(
        image.encodePng(image.Image(width: 7, height: 11)),
      );

      final dimensions = await const FlutterAttachmentImageDimensionProbe()
          .probe(file.path);

      expect(
        dimensions,
        AttachmentImageDimensions(pixelWidth: 7, pixelHeight: 11),
      );
    },
  );

  test('returns no dimensions for corrupt or missing files', () async {
    final root = await Directory.systemTemp.createTemp('awiki-image-probe-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final corrupt = File('${root.path}/corrupt.png');
    await corrupt.writeAsBytes(<int>[1, 2, 3]);
    const probe = FlutterAttachmentImageDimensionProbe();

    expect(await probe.probe(corrupt.path), isNull);
    expect(await probe.probe('${root.path}/missing.png'), isNull);
  });
}
