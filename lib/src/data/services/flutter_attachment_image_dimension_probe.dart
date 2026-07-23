import 'dart:ui' as ui;

import '../../application/attachment_image_dimensions.dart';

final class FlutterAttachmentImageDimensionProbe
    implements AttachmentImageDimensionProbe {
  const FlutterAttachmentImageDimensionProbe();

  @override
  Future<AttachmentImageDimensions?> probe(String localPath) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(localPath);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return AttachmentImageDimensions(
        pixelWidth: descriptor.width,
        pixelHeight: descriptor.height,
      );
    } on Object {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
