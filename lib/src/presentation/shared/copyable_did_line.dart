import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'awiki_me_feedback.dart';
import 'widgets/app_widgets.dart';

class CopyableDidLine extends StatelessWidget {
  const CopyableDidLine({
    super.key,
    required this.value,
    required this.copySemanticLabel,
    required this.copiedMessage,
    this.displayValue,
    this.maxLines,
    this.textKey,
    this.buttonKey,
    this.textStyle,
    this.icon = CupertinoIcons.doc_on_doc,
    this.gap = 8,
    this.buttonSize = 32,
    this.iconSize = 16,
  });

  final String value;
  final String? displayValue;
  final int? maxLines;
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
            displayValue ?? value,
            softWrap: true,
            maxLines: maxLines,
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
        AppIconButton(
          key: buttonKey,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (!context.mounted) {
              return;
            }
            AwikiMeToast.show(context, copiedMessage);
          },
          semanticLabel: copySemanticLabel,
          tooltip: copySemanticLabel,
          size: buttonSize,
          backgroundColor: CupertinoColors.white,
          borderColor: const Color(0xFFDDE5F0),
          borderRadius: BorderRadius.circular(8),
          child: Icon(icon, color: const Color(0xFF34415C), size: iconSize),
        ),
      ],
    );
  }
}
