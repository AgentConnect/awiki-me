import 'package:awiki_me/l10n/app_localizations.dart';

import '../../../domain/entities/conversation_summary.dart';
import '../../../domain/entities/relationship_summary.dart';
import '../../../domain/entities/user_profile.dart';
import '../../../domain/services/peer_display_name_resolver.dart';

class DidDisplayFormatter {
  static final RegExp _fingerprintPattern = RegExp(r'^(.*:e1_)(.+)$');
  static final RegExp _handleMetadataLine = RegExp(
    r'^\s*(?:[-*]\s*)?(?:我的短号\s*[（(]\s*handle\s*[）)]|handle)\s*[:：]\s*@?\S+\s*$',
    caseSensitive: false,
  );
  static final RegExp _didMetadataLine = RegExp(
    r'^\s*(?:[-*]\s*)?did\s*[:：]\s*did:\S+\s*$',
    caseSensitive: false,
  );

  static String compactDid(String source) =>
      PeerDisplayNameResolver.compactDid(source);

  /// Keeps the complete DID path and the fingerprint tail visible while
  /// removing the visually noisy middle of a long fingerprint.
  static String compactDidPath(
    String source, {
    int fingerprintTailLength = 12,
  }) {
    final did = source.trim();
    if (did.isEmpty) {
      return '';
    }
    final fingerprintMatch = _fingerprintPattern.firstMatch(did);
    if (fingerprintMatch != null) {
      final path = fingerprintMatch.group(1)!;
      final fingerprint = fingerprintMatch.group(2)!;
      if (fingerprint.length <= fingerprintTailLength + 4) {
        return did;
      }
      return '$path…${fingerprint.substring(fingerprint.length - fingerprintTailLength)}';
    }
    const headLength = 24;
    if (did.length <= headLength + fingerprintTailLength + 4) {
      return did;
    }
    return '${did.substring(0, headLength)}…${did.substring(did.length - fingerprintTailLength)}';
  }

  static String profileHandle(UserProfile profile) {
    final fullHandle = _cleanHandle(profile.fullHandle);
    if (fullHandle.isNotEmpty) {
      return fullHandle;
    }
    return _cleanHandle(profile.handle);
  }

  static String profileHandleLabel(UserProfile profile) {
    final handle = profileHandle(profile);
    return handle.isEmpty ? profileName(profile) : '@$handle';
  }

  static String secondaryProfileName(UserProfile profile) {
    final name = profileName(profile);
    final primary = profileHandleLabel(profile);
    if (name.isEmpty ||
        _cleanHandle(name).toLowerCase() ==
            _cleanHandle(primary).toLowerCase()) {
      return '';
    }
    return name;
  }

  /// Removes only exact machine-generated identity metadata lines. Free-form
  /// profile prose remains untouched.
  static String withoutRedundantIdentityMetadata(String source) {
    final lines = source.split('\n').where((line) {
      return !_handleMetadataLine.hasMatch(line) &&
          !_didMetadataLine.hasMatch(line);
    });
    return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
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

  /// Relationship rows prefer the hydrated nickname and only fall back to
  /// the protocol Handle when the profile has no nickname.
  static String relationshipTitle(RelationshipSummary relationship) {
    return const PeerDisplayNameResolver().resolve(
      nickname: relationship.displayName,
      fullHandle: relationship.handle,
      did: relationship.did,
    );
  }

  static String conversationTitle(
    ConversationSummary conversation,
    AppLocalizations l10n, {
    String? peerDisplayName,
  }) {
    if (!conversation.isGroup) {
      return const PeerDisplayNameResolver().resolve(
        nickname: peerDisplayName,
        fullHandle: conversation.targetPeer,
        senderNameSnapshot: conversation.displayName,
        did: conversation.targetDid,
        unknownLabel: l10n.chatUnknownUser,
      );
    }
    final source = conversation.displayName;
    final compact = compactDisplayName(
      displayName: conversation.displayName,
      fallbackDid: source,
    );
    return compact.isEmpty ? l10n.chatConversationUntitled : compact;
  }

  static String profileName(UserProfile profile) {
    return const PeerDisplayNameResolver().resolve(
      nickname: profile.displayName,
      fullHandle: profile.fullHandle ?? profile.handle,
      did: profile.did,
    );
  }

  static String homepageUrl(UserProfile profile) {
    final profileUri = profile.profileUri?.trim();
    if (profileUri != null && profileUri.isNotEmpty) {
      return profileUri.startsWith('https://') ? profileUri : '';
    }
    final handle = profile.handle?.trim();
    if (handle == null || handle.isEmpty) {
      return '';
    }
    if (handle.startsWith('http://')) {
      return '';
    }
    return handle.startsWith('https://') ? handle : 'https://$handle';
  }

  static String _cleanHandle(String? source) {
    var value = source?.trim() ?? '';
    while (value.startsWith('@')) {
      value = value.substring(1).trimLeft();
    }
    return value;
  }
}
