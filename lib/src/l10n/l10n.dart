import 'package:flutter/widgets.dart';
import 'package:awiki_me/l10n/app_localizations.dart';

extension AppL10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

String localizeRelationshipLabel(AppLocalizations l10n, String relationship) {
  switch (relationship) {
    case 'friend':
      return l10n.relationshipFriend;
    case 'following':
      return l10n.relationshipFollowing;
    case 'follower':
      return l10n.relationshipFollower;
    case 'none':
      return l10n.relationshipNone;
    default:
      return relationship;
  }
}
