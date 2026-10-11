import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:awiki_me/src/data/avatar/agent_avatar_upload.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'GIF cover extraction leaves the original animation unchanged',
    () async {
      final source = File(
        'tests/unit/avatar/fixtures/agent.gif',
      ).readAsBytesSync();
      final before = List<int>.from(source);
      final decoder = img.GifDecoder()..startDecode(source);
      expect(decoder.numFrames(), greaterThan(1));
      final cover = await agentAnimationCover(source);
      expect(img.decodePng(cover)?.width, lessThanOrEqualTo(256));
      expect(img.decodePng(cover)?.height, lessThanOrEqualTo(256));
      expect(source, before);
      expect(img.GifDecoder().startDecode(source), isNotNull);
    },
  );

  test('animation header validation rejects invalid and oversized uploads', () {
    expect(
      () =>
          validateAgentAnimation(img.encodePng(img.Image(width: 8, height: 8))),
      throwsFormatException,
    );
    final source = File(
      'tests/unit/avatar/fixtures/agent.gif',
    ).readAsBytesSync();
    source[6] = 255;
    source[7] = 255;
    expect(() => validateAgentAnimation(source), throwsFormatException);
  });
}
