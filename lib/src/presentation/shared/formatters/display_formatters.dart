import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../domain/entities/conversation_summary.dart';
import '../../../domain/entities/user_profile.dart';

class DidDisplayFormatter {
  static final RegExp _didUserPattern = RegExp(r':(?:user:)?([^:]+):k1_');
  static final RegExp _didTailPattern = RegExp(r':([^:]+)$');

  static String compactDid(String source) {
    final didMatch = _didUserPattern.firstMatch(source);
    if (didMatch != null) {
      return didMatch.group(1)!;
    }
    final tailMatch = _didTailPattern.firstMatch(source);
    if (tailMatch != null) {
      return tailMatch.group(1)!;
    }
    return source;
  }

  static String compactDisplayName({
    required String displayName,
    required String fallbackDid,
  }) {
    final normalized = displayName.trim();
    if (normalized.isNotEmpty && !normalized.startsWith('did:')) {
      return normalized;
    }
    return compactDid(fallbackDid);
  }

  static String conversationTitle(
    ConversationSummary conversation,
    AppLocalizations l10n,
  ) {
    final source = conversation.isGroup
        ? conversation.displayName
        : (conversation.targetDid?.trim().isNotEmpty == true
            ? conversation.targetDid!.trim()
            : conversation.displayName);
    final compact = compactDisplayName(
      displayName: conversation.displayName,
      fallbackDid: source,
    );
    return compact.isEmpty ? l10n.chatConversationUntitled : compact;
  }

  static String profileName(UserProfile profile) {
    if (profile.nickName.trim().isNotEmpty) {
      return profile.nickName.trim();
    }
    if (profile.handle?.trim().isNotEmpty == true) {
      return profile.handle!.trim();
    }
    return compactDid(profile.did);
  }

  static String homepageUrl(UserProfile profile) {
    final handle = profile.handle?.trim();
    final username =
        handle != null && handle.isNotEmpty ? handle : profileName(profile);
    return 'https://$username.awiki.ai';
  }
}
