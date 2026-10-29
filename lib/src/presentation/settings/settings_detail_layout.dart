import 'package:flutter/cupertino.dart';

import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/widgets/awiki_glass.dart';

/// Shared geometry for the network and server feature settings details.
class SettingsDetailLayout extends StatelessWidget {
  const SettingsDetailLayout({
    super.key,
    required this.title,
    required this.embedded,
    required this.children,
    this.maxWidth,
    this.trailing,
  });
  final String title;
  final bool embedded;
  final List<Widget> children;
  final double? maxWidth;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: context.awikiTheme.background,
    child: AwikiPageCanvas(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: AwikiMeTopBar(
                title: title,
                padding: const EdgeInsets.symmetric(vertical: 6),
                titleFontSize: embedded
                    ? 14
                    : awikiMeCompactTopBarTitleFontSize,
                titleFontWeight: awikiMeCompactTopBarTitleFontWeight,
                titleHeight: awikiMeCompactTopBarTitleHeight,
                leading: embedded
                    ? const SizedBox.shrink()
                    : AwikiBackButton(
                        onTap: () => Navigator.of(context).maybePop(),
                        semanticsLabel: context.l10n.commonBack,
                      ),
                trailing: trailing,
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxWidth ?? (embedded ? 460 : 560),
                  ),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      embedded ? 14 : 24,
                      16,
                      24,
                    ),
                    children: children,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
