import 'package:flutter/cupertino.dart';

import '../../domain/entities/group_identity.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/responsive_layout.dart';

class GroupIdentitySelector extends StatelessWidget {
  const GroupIdentitySelector({
    super.key,
    required this.handle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String? handle;
  final GroupIdentityMode value;
  final bool enabled;
  final ValueChanged<GroupIdentityMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final normalizedHandle = handle?.trim();
    final hasHandle = normalizedHandle != null && normalizedHandle.isNotEmpty;
    final children = <GroupIdentityMode, Widget>{
      if (hasHandle)
        GroupIdentityMode.handle: Padding(
          padding: EdgeInsets.symmetric(horizontal: responsive.spacing(10)),
          child: Text(context.l10n.groupIdentityHandle),
        ),
      GroupIdentityMode.didOnly: Padding(
        padding: EdgeInsets.symmetric(horizontal: responsive.spacing(10)),
        child: Text(context.l10n.groupIdentityDidOnly),
      ),
    };
    final selected = hasHandle ? value : GroupIdentityMode.didOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.l10n.groupIdentityModeLabel,
          style: TextStyle(
            color: theme.secondaryText,
            fontSize: responsive.metaSm,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: responsive.spacing(8)),
        SizedBox(
          key: const Key('group-identity-mode-control'),
          height: responsive.controlHeight,
          child: hasHandle
              ? IgnorePointer(
                  ignoring: !enabled,
                  child: Opacity(
                    opacity: enabled ? 1 : 0.55,
                    child: CupertinoSlidingSegmentedControl<GroupIdentityMode>(
                      groupValue: selected,
                      children: children,
                      onValueChanged: (next) {
                        if (next != null) {
                          onChanged(next);
                        }
                      },
                    ),
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.subtleSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDDE5F0)),
                  ),
                  child: Center(
                    child: Text(
                      context.l10n.groupIdentityDidOnly,
                      style: TextStyle(
                        color: theme.secondaryText,
                        fontSize: responsive.bodyMd,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
        ),
        if (hasHandle) ...<Widget>[
          SizedBox(height: responsive.spacing(6)),
          Text(
            context.l10n.groupIdentityCurrentHandle(normalizedHandle),
            key: const Key('group-identity-handle-value'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.secondaryText,
              fontSize: responsive.metaSm,
            ),
          ),
        ],
      ],
    );
  }
}
