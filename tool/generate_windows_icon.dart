import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

const String windowsIconSourcePath =
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png';
const String windowsIconOutputPath = 'windows/runner/resources/app_icon.ico';
const List<int> windowsIconSizes = <int>[16, 20, 24, 32, 40, 48, 64, 128, 256];

final class WindowsIconEntry {
  const WindowsIconEntry({
    required this.width,
    required this.height,
    required this.bitsPerPixel,
    required this.dataLength,
    required this.dataOffset,
  });

  final int width;
  final int height;
  final int bitsPerPixel;
  final int dataLength;
  final int dataOffset;
}

Uint8List buildWindowsIcon(Uint8List sourceBytes) {
  final source = image.decodePng(sourceBytes);
  if (source == null) {
    throw const FormatException('Windows icon source must be a valid PNG');
  }
  if (source.width != 1024 || source.height != 1024) {
    throw FormatException(
      'Windows icon source must be 1024x1024, got '
      '${source.width}x${source.height}',
    );
  }

  final frames = <image.Image>[
    for (final size in windowsIconSizes)
      image.copyResize(
        source,
        width: size,
        height: size,
        interpolation: image.Interpolation.average,
      ),
  ];
  final encoded = image.IcoEncoder().encodeImages(frames);
  final entries = readWindowsIconEntries(encoded);
  final generatedSizes = entries.map((entry) => entry.width).toList();
  if (!_listEquals(generatedSizes, windowsIconSizes) ||
      entries.any(
        (entry) => entry.width != entry.height || entry.bitsPerPixel != 32,
      )) {
    throw const FormatException(
      'Generated ICO does not contain the required 32-bit square frames',
    );
  }
  return encoded;
}

List<WindowsIconEntry> readWindowsIconEntries(Uint8List bytes) {
  if (bytes.length < 6) {
    throw const FormatException('ICO header is truncated');
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint16(0, Endian.little) != 0 ||
      data.getUint16(2, Endian.little) != 1) {
    throw const FormatException('ICO header has an invalid type');
  }
  final count = data.getUint16(4, Endian.little);
  if (count == 0 || bytes.length < 6 + count * 16) {
    throw const FormatException('ICO directory is empty or truncated');
  }

  return <WindowsIconEntry>[
    for (var index = 0; index < count; index++)
      _readWindowsIconEntry(bytes, data, 6 + index * 16),
  ];
}

WindowsIconEntry _readWindowsIconEntry(
  Uint8List bytes,
  ByteData data,
  int offset,
) {
  final width = bytes[offset] == 0 ? 256 : bytes[offset];
  final height = bytes[offset + 1] == 0 ? 256 : bytes[offset + 1];
  final bitsPerPixel = data.getUint16(offset + 6, Endian.little);
  final dataLength = data.getUint32(offset + 8, Endian.little);
  final dataOffset = data.getUint32(offset + 12, Endian.little);
  if (dataLength == 0 ||
      dataOffset < 6 ||
      dataOffset > bytes.length - dataLength) {
    throw const FormatException('ICO image payload is outside the file');
  }
  const pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (dataLength < pngSignature.length ||
      !_listEquals(
        bytes.sublist(dataOffset, dataOffset + pngSignature.length),
        pngSignature,
      )) {
    throw const FormatException('ICO frame must use a PNG payload');
  }
  return WindowsIconEntry(
    width: width,
    height: height,
    bitsPerPixel: bitsPerPixel,
    dataLength: dataLength,
    dataOffset: dataOffset,
  );
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

Directory _findRepositoryRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    if (File('${current.path}/$windowsIconSourcePath').existsSync() &&
        File('${current.path}/pubspec.yaml').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'Could not find the awiki-me repository from ${start.path}',
      );
    }
    current = parent;
  }
}

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--check')) {
    stderr.writeln('Usage: dart run tool/generate_windows_icon.dart [--check]');
    exitCode = 64;
    return;
  }

  try {
    final root = _findRepositoryRoot(Directory.current);
    final source = File('${root.path}/$windowsIconSourcePath');
    final output = File('${root.path}/$windowsIconOutputPath');
    final generated = buildWindowsIcon(await source.readAsBytes());
    if (arguments.isNotEmpty) {
      if (!await output.exists() ||
          !_listEquals(await output.readAsBytes(), generated)) {
        throw StateError(
          '$windowsIconOutputPath is stale; run '
          '`dart run tool/generate_windows_icon.dart`',
        );
      }
      stdout.writeln('$windowsIconOutputPath is current.');
      return;
    }

    await output.writeAsBytes(generated, flush: true);
    stdout.writeln(
      'Generated $windowsIconOutputPath with sizes '
      '${windowsIconSizes.join(', ')}.',
    );
  } on Object catch (error) {
    stderr.writeln('Windows icon generation failed: $error');
    exitCode = 1;
  }
}
