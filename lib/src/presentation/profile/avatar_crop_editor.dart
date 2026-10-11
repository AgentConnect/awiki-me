import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../l10n/l10n.dart';

/// Coordinates always refer to the normalized preview pixels, never the viewport.
class AvatarCropEditor extends StatefulWidget {
  const AvatarCropEditor({
    super.key,
    required this.bytes,
    required this.controller,
    required this.onCropped,
    required this.onReady,
    required this.currentAvatar,
    this.enabled = true,
    this.isAgent = false,
  });
  final Uint8List bytes;
  final CropController controller;
  final ValueChanged<CropResult> onCropped;
  final ValueChanged<bool> onReady;
  final Widget currentAvatar;
  final bool enabled;
  final bool isAgent;
  @override
  State<AvatarCropEditor> createState() => _AvatarCropEditorState();
}

class _AvatarCropEditorState extends State<AvatarCropEditor> {
  ui.Image? _image;
  Rect? _area;
  double _viewportScale = 1;
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    try {
      final image = (await codec.getNextFrame()).image;
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } finally {
      codec.dispose();
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _image?.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final image = _image;
    final area = _area;
    if (!widget.enabled ||
        image == null ||
        area == null ||
        event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (![
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ].contains(key)) {
      return KeyEventResult.ignored;
    }
    final dx = key == LogicalKeyboardKey.arrowLeft
        ? -1
        : key == LogicalKeyboardKey.arrowRight
        ? 1
        : 0;
    final dy = key == LogicalKeyboardKey.arrowUp
        ? -1
        : key == LogicalKeyboardKey.arrowDown
        ? 1
        : 0;
    final step = 2 / _viewportScale;
    var side = area.width;
    var left = area.left, top = area.top;
    if (HardwareKeyboard.instance.isShiftPressed) {
      side = (side + (dx + dy) * step).clamp(
        math.min(
          40 / _viewportScale,
          math.min(image.width, image.height).toDouble(),
        ),
        math.min(image.width - left, image.height - top),
      );
    } else {
      left = (left + dx * step).clamp(0.0, image.width - side);
      top = (top + dy * step).clamp(0.0, image.height - side);
    }
    widget.controller.area = Rect.fromLTWH(left, top, side, side);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 280,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (image != null) {
                _viewportScale = math.min(
                  constraints.maxWidth / image.width,
                  constraints.maxHeight / image.height,
                );
              }
              return Focus(
                focusNode: _focus,
                onKeyEvent: _key,
                child: Listener(
                  onPointerDown: (_) => _focus.requestFocus(),
                  child: Semantics(
                    label: context.l10n.avatarCropHint,
                    child: IgnorePointer(
                      ignoring: !widget.enabled,
                      child: Crop(
                        key: ValueKey(constraints.biggest),
                        image: widget.bytes,
                        controller: widget.controller,
                        aspectRatio: 1,
                        withCircleUi: false,
                        interactive: false,
                        // The package's wheel listener also runs in fixed-image mode.
                        willUpdateScale: (_) => false,
                        fixCropRect: false,
                        initialRectBuilder: _area == null
                            ? InitialRectBuilder.withSizeAndRatio(
                                size: 1,
                                aspectRatio: 1,
                              )
                            : InitialRectBuilder.withArea(_area!),
                        onMoved: (_, area) {
                          if (mounted) setState(() => _area = area);
                        },
                        onStatusChanged: (status) =>
                            widget.onReady(status == CropStatus.ready),
                        onCropped: widget.onCropped,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Column(
              children: [
                widget.currentAvatar,
                const SizedBox(height: 6),
                Text(context.l10n.avatarCurrent),
              ],
            ),
            const SizedBox(width: 32),
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(
                    widget.isAgent ? 72 * .24 : 36,
                  ),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: image == null || _area == null
                        ? const CupertinoActivityIndicator()
                        : CustomPaint(
                            key: const Key('avatar-new-preview'),
                            painter: AvatarCropPreviewPainter(image, _area!),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(context.l10n.avatarNewPreview),
              ],
            ),
          ],
        ),
        SizedBox(
          height: 48,
          child: _area != null && _area!.width < 512
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.l10n.avatarSmallSelection,
                    textAlign: TextAlign.center,
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

class AvatarCropPreviewPainter extends CustomPainter {
  AvatarCropPreviewPainter(this.image, this.area);
  final ui.Image image;
  final Rect area;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
    image,
    area,
    Offset.zero & size,
    Paint()..filterQuality = FilterQuality.medium,
  );
  @override
  bool shouldRepaint(AvatarCropPreviewPainter oldDelegate) =>
      image != oldDelegate.image || area != oldDelegate.area;
}
