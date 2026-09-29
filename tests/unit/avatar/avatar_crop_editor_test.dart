import 'package:awiki_me/src/presentation/profile/avatar_crop_editor.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import '../test_support.dart';

void main() {
  testWidgets(
    'fixed image, square pointer/keyboard crop, resize and export agree',
    (tester) async {
      final source = img.Image(width: 800, height: 600);
      for (final pixel in source) {
        pixel.setRgb(pixel.x ~/ 4, pixel.y ~/ 3, 80);
      }
      final bytes = Uint8List.fromList(img.encodePng(source));
      final controller = CropController();
      CropResult? result;
      var ready = false;
      Widget tree(double width) => buildLocalizedTestApp(
        home: Center(
          child: SizedBox(
            width: width,
            child: AvatarCropEditor(
              bytes: bytes,
              controller: controller,
              onCropped: (value) => result = value,
              onReady: (value) => ready = value,
              currentAvatar: const SizedBox(width: 72, height: 72),
            ),
          ),
        ),
      );
      Future<void> decoded() async {
        for (
          var n = 0;
          n < 60 &&
              (!ready ||
                  find
                      .byKey(const Key('avatar-new-preview'))
                      .evaluate()
                      .isEmpty);
          n++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(ready, isTrue);
      }

      Rect area() =>
          (tester
                      .widget<CustomPaint>(
                        find.byKey(const Key('avatar-new-preview')),
                      )
                      .painter!
                  as AvatarCropPreviewPainter)
              .area;
      await tester.pumpWidget(tree(400));
      await decoded();
      expect(area().width, closeTo(600, 1));
      final imageRect = tester.getRect(find.byType(Image));
      final crop = tester.getRect(find.byType(Crop));
      // Pull the lower-right corner in, then move the resulting square.
      await tester.dragFrom(
        crop.center + const Offset(139, 139),
        const Offset(-56, -56),
      );
      await tester.pump();
      final resized = area();
      expect(resized.width, lessThan(550));
      expect(resized.width, closeTo(resized.height, .01));
      await tester.dragFrom(
        crop.topLeft +
            Offset(
              resized.center.dx * (280 / 600) + (400 - 800 * (280 / 600)) / 2,
              resized.center.dy * (280 / 600),
            ),
        const Offset(20, 20),
      );
      await tester.pump();
      expect(area().left, greaterThan(resized.left));
      expect(tester.getRect(find.byType(Image)), imageRect);
      final moved = area();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(area().left, lessThan(moved.left));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(area().width, lessThan(moved.width));
      // The package has a separate wheel listener; it must not zoom the image.
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: imageRect.topLeft + const Offset(2, 2),
          scrollDelta: const Offset(0, -100),
        ),
      );
      await tester.pump();
      expect(tester.getRect(find.byType(Image)), imageRect);
      final selected = area();
      await tester.pumpWidget(tree(320));
      ready = false;
      await decoded();
      expect(area().left, closeTo(selected.left, 1));
      expect(area().width, closeTo(selected.width, 1));
      controller.crop();
      for (var n = 0; n < 100 && result == null; n++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(result, isA<CropSuccess>());
      final output = img.decodeImage((result! as CropSuccess).croppedImage)!;
      expect(output.width, closeTo(selected.width, 2));
      expect(output.height, closeTo(selected.height, 2));
      final pixel = output.getPixel(0, 0);
      expect(pixel.r, closeTo(selected.left / 4, 2));
      expect(pixel.g, closeTo(selected.top / 3, 2));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
