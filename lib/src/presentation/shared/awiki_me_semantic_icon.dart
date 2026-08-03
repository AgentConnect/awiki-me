import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'awiki_me_design.dart';

enum AwikiMeIconRole {
  messages,
  agents,
  contacts,
  tasks,
  workbench,
  profile,
  settings,
  search,
  add,
  newConversation,
  more,
  moreHorizontal,
  edit,
  refresh,
  notifications,
  back,
  forward,
  send,
  attachment,
  emoji,
  screenshot,
  voice,
  success,
  warning,
  addMember,
  delete,
  language,
  logout,
  exportCredential,
  phone,
  email,
  credential,
}

@immutable
class AwikiMeIconDefinition {
  const AwikiMeIconDefinition({
    required this.fallback,
    this.assetName,
    this.selectedAssetName,
    this.matchTextDirection = false,
    this.opticalScale = 1,
  });

  final IconData fallback;
  final String? assetName;
  final String? selectedAssetName;
  final bool matchTextDirection;
  final double opticalScale;

  String? assetFor({required bool selected}) =>
      selected ? selectedAssetName ?? assetName : assetName;
}

class AwikiMeIconRegistry {
  static const Map<AwikiMeIconRole, AwikiMeIconDefinition> _definitions =
      <AwikiMeIconRole, AwikiMeIconDefinition>{
        AwikiMeIconRole.messages: AwikiMeIconDefinition(
          fallback: CupertinoIcons.chat_bubble_2,
          assetName: 'assets/icons/message_Inactive.svg',
          opticalScale: 2.05,
        ),
        AwikiMeIconRole.agents: AwikiMeIconDefinition(
          fallback: CupertinoIcons.square_stack_3d_up_fill,
          opticalScale: 0.92,
        ),
        AwikiMeIconRole.contacts: AwikiMeIconDefinition(
          fallback: CupertinoIcons.person_2,
          assetName: 'assets/icons/friend_Inactive.svg',
          opticalScale: 1.9,
        ),
        AwikiMeIconRole.tasks: AwikiMeIconDefinition(
          fallback: CupertinoIcons.checkmark_square,
        ),
        AwikiMeIconRole.workbench: AwikiMeIconDefinition(
          fallback: CupertinoIcons.square_grid_2x2,
        ),
        AwikiMeIconRole.profile: AwikiMeIconDefinition(
          fallback: CupertinoIcons.person,
          assetName: 'assets/icons/me_Inactive.svg',
          opticalScale: 2.6,
        ),
        AwikiMeIconRole.settings: AwikiMeIconDefinition(
          fallback: CupertinoIcons.gear,
          assetName: 'assets/icons/icon_settings.svg',
        ),
        AwikiMeIconRole.search: AwikiMeIconDefinition(
          fallback: CupertinoIcons.search,
        ),
        AwikiMeIconRole.add: AwikiMeIconDefinition(
          fallback: CupertinoIcons.add,
          assetName: 'assets/icons/icon_plus.svg',
        ),
        AwikiMeIconRole.newConversation: AwikiMeIconDefinition(
          fallback: CupertinoIcons.chat_bubble_2,
          assetName: 'assets/icons/icon_add.svg',
        ),
        AwikiMeIconRole.more: AwikiMeIconDefinition(
          fallback: CupertinoIcons.ellipsis,
          assetName: 'assets/icons/dot_vertical.svg',
        ),
        AwikiMeIconRole.moreHorizontal: AwikiMeIconDefinition(
          fallback: CupertinoIcons.ellipsis,
        ),
        AwikiMeIconRole.edit: AwikiMeIconDefinition(
          fallback: CupertinoIcons.pencil,
        ),
        AwikiMeIconRole.refresh: AwikiMeIconDefinition(
          fallback: CupertinoIcons.refresh,
          assetName: 'assets/icons/icon_reload.svg',
        ),
        AwikiMeIconRole.notifications: AwikiMeIconDefinition(
          fallback: CupertinoIcons.bell,
          assetName: 'assets/icons/icon_bell.svg',
        ),
        AwikiMeIconRole.back: AwikiMeIconDefinition(
          fallback: CupertinoIcons.chevron_left,
          assetName: 'assets/icons/icon_left.svg',
          matchTextDirection: true,
        ),
        AwikiMeIconRole.forward: AwikiMeIconDefinition(
          fallback: CupertinoIcons.chevron_right,
          assetName: 'assets/icons/icon_right.svg',
          matchTextDirection: true,
        ),
        AwikiMeIconRole.send: AwikiMeIconDefinition(
          fallback: CupertinoIcons.paperplane,
          assetName: 'assets/icons/icon_send.svg',
        ),
        AwikiMeIconRole.attachment: AwikiMeIconDefinition(
          fallback: CupertinoIcons.paperclip,
        ),
        AwikiMeIconRole.emoji: AwikiMeIconDefinition(
          fallback: CupertinoIcons.smiley,
        ),
        AwikiMeIconRole.screenshot: AwikiMeIconDefinition(
          fallback: CupertinoIcons.scissors,
        ),
        AwikiMeIconRole.voice: AwikiMeIconDefinition(
          fallback: CupertinoIcons.mic,
        ),
        AwikiMeIconRole.success: AwikiMeIconDefinition(
          fallback: CupertinoIcons.check_mark_circled,
        ),
        AwikiMeIconRole.warning: AwikiMeIconDefinition(
          fallback: CupertinoIcons.exclamationmark_triangle,
        ),
        AwikiMeIconRole.addMember: AwikiMeIconDefinition(
          fallback: CupertinoIcons.person_add,
        ),
        AwikiMeIconRole.delete: AwikiMeIconDefinition(
          fallback: CupertinoIcons.delete,
        ),
        AwikiMeIconRole.language: AwikiMeIconDefinition(
          fallback: CupertinoIcons.globe,
          assetName: 'assets/icons/icon_Language.svg',
        ),
        AwikiMeIconRole.logout: AwikiMeIconDefinition(
          fallback: CupertinoIcons.square_arrow_right,
          assetName: 'assets/icons/icon_Logout.svg',
        ),
        AwikiMeIconRole.exportCredential: AwikiMeIconDefinition(
          fallback: CupertinoIcons.arrow_down_doc,
          assetName: 'assets/icons/icon_export.svg',
        ),
        AwikiMeIconRole.phone: AwikiMeIconDefinition(
          fallback: CupertinoIcons.phone,
          assetName: 'assets/icons/icon_mobile.svg',
        ),
        AwikiMeIconRole.email: AwikiMeIconDefinition(
          fallback: CupertinoIcons.mail,
          assetName: 'assets/icons/icon_mail.svg',
        ),
        AwikiMeIconRole.credential: AwikiMeIconDefinition(
          fallback: CupertinoIcons.lock_shield,
          assetName: 'assets/icons/icon_key.svg',
        ),
      };

  static AwikiMeIconDefinition definition(AwikiMeIconRole role) =>
      _definitions[role]!;

  static Set<String> get assetNames => <String>{
    for (final definition in _definitions.values)
      if (definition.assetName case final asset?) asset,
    for (final definition in _definitions.values)
      if (definition.selectedAssetName case final asset?) asset,
  };
}

class AwikiMeSemanticIcon extends StatelessWidget {
  const AwikiMeSemanticIcon({
    super.key,
    required this.role,
    this.selected = false,
    this.size = 18,
    this.color,
    this.semanticLabel,
  });

  final AwikiMeIconRole role;
  final bool selected;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final definition = AwikiMeIconRegistry.definition(role);
    final resolvedColor =
        color ??
        IconTheme.of(context).color ??
        context.awikiTheme.secondaryText;
    final assetName = definition.assetFor(selected: selected);
    final graphic = assetName == null
        ? Icon(
            definition.fallback,
            size: size,
            color: resolvedColor,
            semanticLabel: semanticLabel,
          )
        : SvgPicture.asset(
            assetName,
            width: size,
            height: size,
            fit: BoxFit.contain,
            colorFilter: ColorFilter.mode(resolvedColor, BlendMode.srcIn),
            matchTextDirection: definition.matchTextDirection,
            semanticsLabel: semanticLabel,
            excludeFromSemantics: semanticLabel == null,
          );

    return SizedBox.square(
      dimension: size,
      child: ClipRect(
        child: Transform.scale(
          scale: definition.opticalScale,
          alignment: Alignment.center,
          child: graphic,
        ),
      ),
    );
  }
}
