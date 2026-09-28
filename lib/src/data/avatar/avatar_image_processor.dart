import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const avatarSourceByteLimit = 20 * 1024 * 1024;

/// Parses headers before allowing any full image allocation.
void validateAvatarSource(Uint8List bytes, {bool allowNativeHeic = false}) {
  if (bytes.isEmpty || bytes.length > avatarSourceByteLimit) {
    throw const FormatException('avatar.source_size');
  }
  // Static HEIC is handed to the mobile platform decoder. Sequence brands are
  // deliberately excluded; dimensions are checked on ImageDescriptor below.
  if (allowNativeHeic &&
      bytes.length >= 16 &&
      String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp' &&
      {'heic', 'heix'}.contains(String.fromCharCodes(bytes.sublist(8, 12)))) {
    return;
  }
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null ||
      !{
        img.ImageFormat.jpg,
        img.ImageFormat.png,
        img.ImageFormat.webp,
      }.contains(decoder.format)) {
    throw const FormatException('avatar.source_format');
  }
  final info = decoder.startDecode(bytes);
  if (info == null ||
      info.width < 1 ||
      info.height < 1 ||
      info.width > 16384 ||
      info.height > 16384 ||
      info.width * info.height > 50000000) {
    throw const FormatException('avatar.source_dimensions');
  }
  if (decoder.numFrames() != 1) {
    throw const FormatException('avatar.source_animation');
  }
}

/// The platform decoder applies orientation/color conversion. Render an opaque
/// preview to detach all source metadata before the crop UI receives pixels.
Future<Uint8List> prepareAvatarPreview(Uint8List bytes) async {
  final nativeHeic =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  await compute(_validatePreviewSource, (bytes, nativeHeic));
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? decoded;
  ui.Image? normalized;
  ui.Picture? picture;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width < 1 ||
        descriptor.height < 1 ||
        descriptor.width > 16384 ||
        descriptor.height > 16384 ||
        descriptor.width * descriptor.height > 50000000) {
      throw const FormatException('avatar.source_dimensions');
    }
    final scale =
        2048 /
        (descriptor.width > descriptor.height
            ? descriptor.width
            : descriptor.height);
    codec = await descriptor.instantiateCodec(
      targetWidth: scale < 1
          ? (descriptor.width * scale).round()
          : descriptor.width,
      targetHeight: scale < 1
          ? (descriptor.height * scale).round()
          : descriptor.height,
    );
    if (codec.frameCount != 1) {
      throw const FormatException('avatar.source_animation');
    }
    decoded = (await codec.getNextFrame()).image;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
    canvas.drawImage(decoded, ui.Offset.zero, ui.Paint());
    picture = recorder.endRecording();
    normalized = await picture.toImage(decoded.width, decoded.height);
    final result = await normalized.toByteData(format: ui.ImageByteFormat.png);
    if (result == null) throw const FormatException('avatar.decode');
    return result.buffer.asUint8List();
  } finally {
    normalized?.dispose();
    picture?.dispose();
    decoded?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

void _validatePreviewSource((Uint8List, bool) input) =>
    validateAvatarSource(input.$1, allowNativeHeic: input.$2);

Uint8List encodeAvatarJpeg(Uint8List squarePng) {
  final source = img.decodePng(squarePng);
  if (source == null || source.width != source.height || source.width > 2048) {
    throw const FormatException('avatar.crop');
  }
  final resized = img.copyResize(
    source,
    width: 512,
    height: 512,
    interpolation: img.Interpolation.average,
  );
  final clean = img.Image(width: 512, height: 512, numChannels: 3);
  img.fill(clean, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(clean, resized);
  for (final quality in [90, 85, 80]) {
    final bytes = img.encodeJpg(clean, quality: quality);
    if (bytes.length <= 512 * 1024) return bytes;
  }
  throw const FormatException('avatar.output_size');
}
