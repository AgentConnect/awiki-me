import 'package:flutter/cupertino.dart';

import 'awiki_me_design.dart';

class AwikiMeTopBar extends StatelessWidget {
  const AwikiMeTopBar({
    super.key,
    required this.title,
    required this.leading,
    this.trailing,
    this.leadingWidth = 30,
    this.trailingWidth = 30,
    this.padding = const EdgeInsets.only(bottom: 18),
  });

  final String title;
  final Widget leading;
  final Widget? trailing;
  final double leadingWidth;
  final double trailingWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: leadingWidth,
            height: 30,
            child: Center(child: leading),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AwikiMeTextStyles.navTitle,
            ),
          ),
          SizedBox(
            width: trailingWidth,
            height: 30,
            child: Center(child: trailing ?? const SizedBox.shrink()),
          ),
        ],
      ),
    );
  }
}
