import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

const String macosDmgBackgroundOutputPath =
    'installer/macos/dmg-background.png';
const int macosDmgBackgroundWidth = 600;
const int macosDmgBackgroundHeight = 380;

final image.Color _backgroundColor = image.ColorRgba8(246, 247, 249, 255);
final image.Color _arrowColor = image.ColorRgba8(111, 117, 126, 255);

Uint8List buildMacosDmgBackground() {
  final canvas = image.Image(
    width: macosDmgBackgroundWidth,
    height: macosDmgBackgroundHeight,
    numChannels: 4,
  );
  image.fill(canvas, color: _backgroundColor);

  _drawRoundedLine(canvas, x1: 260, y1: 180, x2: 340, y2: 180);
  _drawRoundedLine(canvas, x1: 316, y1: 156, x2: 340, y2: 180);
  _drawRoundedLine(canvas, x1: 340, y1: 180, x2: 316, y2: 204);

  return image.encodePng(canvas, level: 9);
}

void _drawRoundedLine(
  image.Image canvas, {
  required int x1,
  required int y1,
  required int x2,
  required int y2,
}) {
  const thickness = 6;
  image.drawLine(
    canvas,
    x1: x1,
    y1: y1,
    x2: x2,
    y2: y2,
    color: _arrowColor,
    antialias: true,
    thickness: thickness,
  );
  for (final point in <({int x, int y})>[(x: x1, y: y1), (x: x2, y: y2)]) {
    image.fillCircle(
      canvas,
      x: point.x,
      y: point.y,
      radius: thickness ~/ 2,
      color: _arrowColor,
    );
  }
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

Directory _findRepositoryRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    if (File('${current.path}/pubspec.yaml').existsSync() &&
        File(
          '${current.path}/tool/generate_macos_dmg_background.dart',
        ).existsSync()) {
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
    stderr.writeln(
      'Usage: dart run tool/generate_macos_dmg_background.dart [--check]',
    );
    exitCode = 64;
    return;
  }

  try {
    final root = _findRepositoryRoot(Directory.current);
    final output = File('${root.path}/$macosDmgBackgroundOutputPath');
    final generated = buildMacosDmgBackground();
    if (arguments.isNotEmpty) {
      if (!await output.exists() ||
          !_listEquals(await output.readAsBytes(), generated)) {
        throw StateError(
          '$macosDmgBackgroundOutputPath is stale; run '
          '`dart run tool/generate_macos_dmg_background.dart`',
        );
      }
      stdout.writeln('$macosDmgBackgroundOutputPath is current.');
      return;
    }

    await output.parent.create(recursive: true);
    await output.writeAsBytes(generated, flush: true);
    stdout.writeln(
      'Generated $macosDmgBackgroundOutputPath at '
      '${macosDmgBackgroundWidth}x$macosDmgBackgroundHeight.',
    );
  } on Object catch (error) {
    stderr.writeln('macOS DMG background generation failed: $error');
    exitCode = 1;
  }
}
