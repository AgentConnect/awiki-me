import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Validate headers before decoding a preview; the original GIF is the upload.
void validateAgentAnimation(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
    throw const FormatException('agent_avatar.upload_too_large');
  }
  final decoder = img.GifDecoder();
  final info = decoder.startDecode(bytes);
  if (info == null ||
      info.width < 1 ||
      info.height < 1 ||
      info.width > 4096 ||
      info.height > 4096 ||
      decoder.numFrames() > 120 ||
      info.width * info.height * decoder.numFrames() > 24000000) {
    throw const FormatException('agent_avatar.animation_too_large');
  }
}

Future<Uint8List> agentAnimationCover(Uint8List bytes) async {
  await compute(validateAgentAnimation, bytes);
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? frame;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    codec = await descriptor.instantiateCodec(
      targetWidth: 256,
      targetHeight: 256,
    );
    frame = (await codec.getNextFrame()).image;
    final cover = await frame.toByteData(format: ui.ImageByteFormat.png);
    if (cover == null) {
      throw const FormatException('agent_avatar.invalid_image');
    }
    return cover.buffer.asUint8List();
  } finally {
    frame?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
