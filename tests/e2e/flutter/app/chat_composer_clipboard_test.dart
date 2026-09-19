// Native desktop input/clipboard smoke. Messaging is fake; clipboard and the
// attachment adapter are real. Preserve all macOS pasteboard item types.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:awiki_me/src/data/services/method_channel_attachment_picker_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pasteboard/pasteboard.dart';
import '../../../unit/chat_composer_paste_test.dart' show chat, openMenu;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native composer menu pastes text, image and file with focus intact',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'awiki-clipboard-smoke-',
      );
      final helper = File('${directory.path}/pasteboard.swift');
      await helper.writeAsString(_pasteboardHelper);
      final backup = '${directory.path}/pasteboard.plist';
      Future<void> pasteboard(String command, String path) async {
        final result = await Process.run('/usr/bin/swift', [
          helper.path,
          command,
          path,
        ]);
        expect(
          result.exitCode,
          0,
          reason: 'Native pasteboard fixture must succeed',
        );
      }

      if (Platform.isMacOS) await pasteboard('backup', backup);
      final previousText = Platform.isMacOS
          ? null
          : await Clipboard.getData(Clipboard.kTextPlain);
      Process? linuxClipboardOwner;
      try {
        final picker = MethodChannelAttachmentPickerService();
        await Clipboard.setData(
          const ClipboardData(text: 'native pasted text'),
        );
        await tester.pumpWidget(chat(picker));
        await tester.enterText(
          find.byType(CupertinoTextField),
          'before original',
        );
        await tester.pump(const Duration(milliseconds: 600));
        await openMenu(tester);
        final editor = tester.widget<EditableText>(find.byType(EditableText));
        editor.controller.selection = const TextSelection(
          baseOffset: 7,
          extentOffset: 15,
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('粘贴')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        expect(editor.focusNode.hasFocus, isTrue);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(editor.controller.text, 'before native pasted text');
        await tester.pump(const Duration(milliseconds: 600));
        final modifier = Platform.isMacOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
        expect(editor.controller.text, 'before original');

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawColor(const ui.Color(0xff007fff), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(48, 48);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (Platform.isLinux) {
          // pasteboard 0.5.0 reads Linux images, but its writeImage is a no-op.
          // Seed the X11 clipboard independently so this tests real pasting.
          final fixture = File('${directory.path}/image.png');
          await fixture.writeAsBytes(bytes!.buffer.asUint8List());
          linuxClipboardOwner = await Process.start('xclip', [
            '-selection',
            'clipboard',
            '-t',
            'image/png',
            '-i',
            '-quiet',
            fixture.path,
          ]);
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while ((await Pasteboard.image)?.isNotEmpty != true) {
            if (DateTime.now().isAfter(deadline)) {
              fail('The native X11 image clipboard fixture was not ready.');
            }
            await tester.pump(const Duration(milliseconds: 50));
          }
        } else {
          await picker.copyImage(bytes!.buffer.asUint8List());
        }
        image.dispose();
        picture.dispose();
        await tester.pumpWidget(chat(picker));
        await openMenu(tester);
        await tester.tap(find.text('粘贴'));
        await tester.pumpAndSettle();
        expect(find.textContaining('.png'), findsWidgets);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          isEmpty,
        );

        if (Platform.isMacOS) {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          final file = File('${directory.path}/剪贴板文件.txt');
          await file.writeAsString('native file clipboard proof');
          await pasteboard('file', file.path);
          await tester.pumpWidget(chat(picker));
          await openMenu(tester);
          await tester.tap(find.text('粘贴'));
          await tester.pumpAndSettle();
          expect(find.text('剪贴板文件.txt'), findsOneWidget);
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .controller
                .text,
            isEmpty,
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        linuxClipboardOwner?.kill();
        if (linuxClipboardOwner != null) {
          await linuxClipboardOwner.exitCode;
        }
        await tester.pumpWidget(const SizedBox());
        if (Platform.isMacOS) {
          await pasteboard('restore', backup);
        } else {
          await Clipboard.setData(
            previousText ?? const ClipboardData(text: ''),
          );
        }
        await directory.delete(recursive: true);
      }
    },
  );
}

const _pasteboardHelper = r'''
import AppKit
let args = CommandLine.arguments
let pasteboard = NSPasteboard.general
let path = URL(fileURLWithPath: args[2])
switch args[1] {
case "backup":
    let items = (pasteboard.pasteboardItems ?? []).map { item in
        Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
            item.data(forType: type).map { (type.rawValue, $0) }
        })
    }
    let data = try PropertyListSerialization.data(fromPropertyList: items, format: .binary, options: 0)
    try data.write(to: path, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
case "restore":
    let data = try Data(contentsOf: path)
    let items = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [[String: Data]]
    pasteboard.clearContents()
    let restored = items.map { fields in
        let item = NSPasteboardItem()
        for (type, data) in fields { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
        return item
    }
    if !restored.isEmpty { precondition(pasteboard.writeObjects(restored)) }
case "file":
    pasteboard.clearContents()
    precondition(pasteboard.writeObjects([path as NSURL]))
default: fatalError("unsupported fixture command")
}
''';
