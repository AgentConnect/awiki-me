import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import '../../../tool/ensure_windows_im_core.dart';

void main() {
  test('Windows native artifacts must have a real PE x64 machine header', () {
    final image = Uint8List(256);
    final data = ByteData.sublistView(image);
    image[0] = 0x4d;
    image[1] = 0x5a;
    data.setUint32(0x3c, 128, Endian.little);
    data.setUint32(128, 0x4550, Endian.little);
    data.setUint16(132, 0x8664, Endian.little);
    expect(windowsPeMachine(image), 0x8664);
    data.setUint16(132, 0xaa64, Endian.little);
    expect(windowsPeMachine(image), isNot(0x8664));
    data.setUint32(0x3c, 0xffffffff, Endian.little);
    expect(() => windowsPeMachine(image), throwsFormatException);
    expect(() => windowsPeMachine([1, 2, 3]), throwsFormatException);
  });
}
