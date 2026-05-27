import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'awiki_me_feedback.dart';

class CopyableDidLine extends StatelessWidget {
  const CopyableDidLine({
    super.key,
    required this.value,
    required this.copySemanticLabel,
    required this.copiedMessage,
    this.textKey,
    this.buttonKey,
    this.textStyle,
    this.icon = CupertinoIcons.doc_on_doc,
    this.gap = 8,
    this.buttonSize = 32,
    this.iconSize = 16,
  });

  final String value;
  final String copySemanticLabel;
  final String copiedMessage;
  final Key? textKey;
  final Key? buttonKey;
  final TextStyle? textStyle;
  final IconData icon;
  final double gap;
  final double buttonSize;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            key: textKey,
            value,
            softWrap: true,
            style:
                textStyle ??
                const TextStyle(
                  color: Color(0xFF17213A),
                  fontSize: 12,
                  height: 1.35,
                ),
          ),
        ),
        SizedBox(width: gap),
        Semantics(
          button: true,
          label: copySemanticLabel,
          child: GestureDetector(
            key: buttonKey,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!context.mounted) {
                return;
              }
              AwikiMeToast.show(context, copiedMessage);
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: buttonSize,
              width: buttonSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFDDE5F0)),
              ),
              child: Icon(icon, color: const Color(0xFF34415C), size: iconSize),
            ),
          ),
        ),
      ],
    );
  }
}
