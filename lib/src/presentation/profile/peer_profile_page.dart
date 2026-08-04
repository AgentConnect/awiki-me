import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../chat/chat_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../conversation_list/conversation_provider.dart';
import '../friends/friends_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/avatar_badge.dart';
import '../shared/copyable_did_line.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/identity_flow.dart';
import '../shared/identity_profile_surface.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'peer_display_profile_provider.dart';
import 'peer_profile_provider.dart';

class PeerProfilePage extends ConsumerWidget {
  const PeerProfilePage({
    super.key,
    required this.did,
    this.embedded = false,
    this.onBack,
    this.keepConversationInCurrentNavigator = false,
  });

  final String did;
  final bool embedded;
  final VoidCallback? onBack;
  final bool keepConversationInCurrentNavigator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(peerProfileProvider(did));
    final theme = context.awikiTheme;
    final profile = state.profile;
    final displayName = profile == null
        ? ''
        : ref.watch(
            peerDisplayNameProvider(
              PeerDisplayNameRequest(
                did: profile.did,
                nickname: profile.displayName,
                fullHandle: profile.fullHandle ?? profile.handle,
                unknownLabel: context.l10n.chatUnknownUser,
              ),
            ),
          );
    final homepageUrl = profile == null
        ? ''
        : ref.watch(profileHomepageResolverProvider).homepageUrl(profile);
    final responsive = context.awikiResponsive;
    final listedAsFollowing = ref.watch(
      friendsProvider.select((friends) => friends.isFollowing(did)),
    );
    final relationship = _mergePeerRelationship(
      state.relationship,
      listedAsFollowing: listedAsFollowing,
    );
    final isFollowing = relationship == 'following' || relationship == 'friend';

    Future<void> toggleRelationship() async {
      final controller = ref.read(peerProfileProvider(did).notifier);
      if (isFollowing) {
        await controller.unfollow();
      } else {
        await controller.follow();
      }
    }

    Future<void> sendMessage() async {
      await openDirectConversationForProfile(
        context,
        ref,
        profile!,
        pushWithinCurrentNavigator: keepConversationInCurrentNavigator,
      );
      if (!embedded && !keepConversationInCurrentNavigator && context.mounted) {
        Navigator.of(context).pop();
      }
    }

    Future<void> deleteLocalThread() async {
      try {
        final conversationId = await resolveCanonicalConversationIdForProfile(
          ref,
          profile!,
        );
        final conversations = ref
            .read(conversationListProvider)
            .conversations
            .where((item) => item.conversationId == conversationId)
            .toList(growable: false);
        if (conversations.length > 1) {
          throw StateError('canonical_conversation_not_unique');
        }
        if (conversations.length == 1) {
          await ref
              .read(chatThreadsProvider.notifier)
              .deleteConversation(conversations.single);
        }
        ref
            .read(uiFeedbackProvider.notifier)
            .showInfo(AppMessage.peerProfileThreadDeleted());
      } catch (error) {
        if (isSessionEpochChangedError(error)) {
          return;
        }
        ref
            .read(uiFeedbackProvider.notifier)
            .showError(AppMessage.fromError(error));
      }
    }

    return Stack(
      children: <Widget>[
        CupertinoPageScaffold(
          backgroundColor: theme.background,
          child: AwikiAdaptiveScaffold(
            maxWidth: 900,
            includeBottomSafeArea: true,
            child: state.isLoading
                ? const Center(child: CupertinoActivityIndicator())
                : profile == null
                ? Center(
                    child: AwikiMeErrorText(
                      message: context.l10n.peerProfileLoadFailed,
                      textAlign: TextAlign.center,
                    ),
                  )
                : CustomScrollView(
                    key: const Key('peer-profile-scroll'),
                    slivers: <Widget>[
                      SliverPadding(
                        padding: EdgeInsets.only(top: responsive.spacing(14)),
                        sliver: SliverToBoxAdapter(
                          child: AwikiMeTopBar(
                            title: context.l10n.chatPeerInfoUserTitle,
                            padding: EdgeInsets.zero,
                            leading: embedded && onBack == null
                                ? const SizedBox.shrink()
                                : TopBarActionButton(
                                    key: const Key('peer-profile-back-button'),
                                    onTap:
                                        onBack ??
                                        () => Navigator.of(context).pop(),
                                    semanticsLabel: context.l10n.commonBack,
                                    child: AwikiAssetIcon(
                                      assetName: 'assets/icons/icon_left.svg',
                                      color: theme.primaryDark,
                                      size: 22,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: _PeerProfileHero(
                              displayName: displayName,
                              bio: profile.bio,
                              tags: profile.tags,
                              avatarUri: profile.avatarUri,
                              following: isFollowing,
                              onSendMessage: sendMessage,
                              onToggleRelationship: toggleRelationship,
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: _PeerProfileDetails(
                              did: profile.did,
                              homepageUrl: homepageUrl,
                              onOpenHomepage: homepageUrl.isEmpty
                                  ? null
                                  : () async {
                                      final url = Uri.parse(homepageUrl);
                                      try {
                                        await launchUrl(
                                          url,
                                          mode: LaunchMode.externalApplication,
                                        );
                                      } catch (error) {
                                        ref
                                            .read(
                                              peerProfileProvider(did).notifier,
                                            )
                                            .showLinkOpenError(error);
                                      }
                                    },
                            ),
                          ),
                        ),
                      ),
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              responsive.spacing(16),
                              responsive.spacing(28),
                              responsive.spacing(16),
                              responsive.spacing(24),
                            ),
                            child: _PeerProfileDeleteButton(
                              onPressed: deleteLocalThread,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (state.isActionBusy)
          AwikiMeLoadingMask(label: context.l10n.commonPleaseWait),
      ],
    );
  }
}

class _PeerProfileHero extends StatelessWidget {
  const _PeerProfileHero({
    required this.displayName,
    required this.bio,
    required this.tags,
    required this.following,
    required this.onSendMessage,
    required this.onToggleRelationship,
    this.avatarUri,
  });

  final String displayName;
  final String bio;
  final List<String> tags;
  final bool following;
  final String? avatarUri;
  final Future<void> Function() onSendMessage;
  final Future<void> Function() onToggleRelationship;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final visibleTags = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(3)
        .toList(growable: false);
    return Padding(
      key: const Key('peer-profile-identity-hero'),
      padding: EdgeInsets.fromLTRB(
        IdentityProfileLayout.contentInset(context),
        responsive.spacing(16),
        IdentityProfileLayout.contentInset(context),
        responsive.spacing(18),
      ),
      child: Container(
        padding: EdgeInsets.all(
          responsive.isCompact ? 16 : responsive.spacing(18),
        ),
        decoration: BoxDecoration(
          color: theme.subtleSurface,
          borderRadius: BorderRadius.circular(responsive.radius(20)),
        ),
        child: Column(
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AvatarBadge(
                  key: const Key('peer-profile-avatar'),
                  seed: displayName,
                  avatarUri: avatarUri,
                  size: responsive.isCompact
                      ? 72
                      : responsive.displayScaled(64),
                ),
                SizedBox(width: responsive.spacing(16)),
                Expanded(
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          displayName,
                          key: const Key('peer-profile-display-name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.title,
                            fontSize: responsive.isCompact
                                ? 20
                                : responsive.titleXl,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        if (bio.trim().isNotEmpty) ...<Widget>[
                          SizedBox(height: responsive.spacing(6)),
                          Text(
                            bio.trim(),
                            key: const Key('peer-profile-bio'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.secondaryText,
                              fontSize: responsive.isCompact
                                  ? 14
                                  : responsive.bodyMd,
                              height: 1.45,
                            ),
                          ),
                        ],
                        if (visibleTags.isNotEmpty) ...<Widget>[
                          SizedBox(height: responsive.spacing(10)),
                          Wrap(
                            key: const Key('peer-profile-tags'),
                            spacing: responsive.spacing(8),
                            runSpacing: responsive.spacing(8),
                            children: visibleTags
                                .map(
                                  (tag) => IdentityProfileBadge(
                                    label: tag,
                                    tone: IdentityProfileBadgeTone.outlined,
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: responsive.spacing(16)),
            Row(
              key: const Key('peer-profile-action-row'),
              children: <Widget>[
                Expanded(
                  child: _PeerProfileCompactActionButton(
                    key: const Key('peer-profile-send-message'),
                    visualKey: const Key('peer-profile-send-message-visual'),
                    label: context.l10n.peerProfileSendMessage,
                    emphasized: true,
                    onPressed: onSendMessage,
                    expand: true,
                  ),
                ),
                SizedBox(width: responsive.spacing(12)),
                _PeerProfileCompactActionButton(
                  key: following
                      ? const Key('peer-profile-unfollow')
                      : const Key('peer-profile-follow'),
                  visualKey: const Key('peer-profile-relationship-visual'),
                  label: following
                      ? context.l10n.peerProfileUnfollow
                      : context.l10n.friendsFollow,
                  onPressed: onToggleRelationship,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerProfileCompactActionButton extends StatelessWidget {
  const _PeerProfileCompactActionButton({
    super.key,
    required this.visualKey,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
    this.expand = false,
  });

  final Key visualKey;
  final String label;
  final VoidCallback onPressed;
  final bool emphasized;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final baseWidth = emphasized
        ? 84.0
        : (label.runes.length > 2 ? 104.0 : 80.0);
    final width = expand
        ? double.infinity
        : responsive.isCompact
        ? baseWidth
        : responsive.displayScaled(baseWidth);
    final tapHeight = responsive.isCompact
        ? 48.0
        : responsive.displayScaled(48);
    final visualHeight = responsive.isCompact
        ? 40.0
        : responsive.displayScaled(40);
    final radius = BorderRadius.circular(responsive.radius(9));
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      tooltip: label,
      borderRadius: radius,
      scaleOnPress: true,
      pressedScale: 0.97,
      builder: (context, state, child) => AnimatedOpacity(
        opacity: state.pressed
            ? 0.84
            : state.hovered || state.focused
            ? 0.93
            : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: child,
      ),
      child: SizedBox(
        width: width,
        height: tapHeight,
        child: Center(
          child: Container(
            key: visualKey,
            width: width,
            height: visualHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: emphasized ? theme.primary : theme.surface,
              borderRadius: radius,
              border: Border.all(color: theme.primary),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: emphasized ? theme.primaryForeground : theme.primary,
                fontSize: responsive.isCompact ? 16 : responsive.bodyMd,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PeerProfileDetails extends StatelessWidget {
  const _PeerProfileDetails({
    required this.did,
    required this.homepageUrl,
    required this.onOpenHomepage,
  });

  final String did;
  final String homepageUrl;
  final VoidCallback? onOpenHomepage;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Container(
      key: const Key('peer-profile-details'),
      padding: EdgeInsets.symmetric(
        horizontal: IdentityProfileLayout.contentInset(context),
      ),
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: theme.border)),
      ),
      child: SelectionArea(
        child: Column(
          children: <Widget>[
            _PeerProfileDetailRow(
              label: 'DID',
              showDivider: homepageUrl.isNotEmpty,
              child: CopyableDidLine(
                value: did,
                displayValue: DidDisplayFormatter.compactDidPath(did),
                maxLines: 2,
                copySemanticLabel: context.l10n.chatPeerInfoCopyDid,
                copiedMessage: context.l10n.chatPeerInfoDidCopied,
                textKey: const Key('peer-profile-did-value'),
                buttonKey: const Key('peer-profile-copy-did-button'),
                textStyle: TextStyle(
                  color: theme.body,
                  fontSize: responsive.bodyMd,
                  height: 1.35,
                ),
                buttonSize: responsive.displayScaled(32),
                iconSize: responsive.displayScaled(15),
                showButtonChrome: false,
              ),
            ),
            if (homepageUrl.isNotEmpty)
              _PeerProfileDetailRow(
                label: context.l10n.profileHomepageLabel,
                showDivider: false,
                child: IdentityProfileLinkValue(
                  value: _compactHomepageLabel(homepageUrl),
                  actionLabel: context.l10n.profileOpenHomepage,
                  onTap: onOpenHomepage!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PeerProfileDetailRow extends StatelessWidget {
  const _PeerProfileDetailRow({
    required this.label,
    required this.child,
    this.showDivider = true,
  });

  final String label;
  final Widget child;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Container(
      constraints: BoxConstraints(
        minHeight: responsive.isCompact ? 68 : responsive.displayScaled(60),
      ),
      padding: EdgeInsets.symmetric(vertical: responsive.spacing(14)),
      decoration: showDivider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.border)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: responsive.displayScaled(responsive.isCompact ? 64 : 88),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: responsive.isCompact ? 16 : responsive.bodyMd,
                height: 1.3,
              ),
            ),
          ),
          SizedBox(width: responsive.spacing(8)),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _PeerProfileDeleteButton extends StatelessWidget {
  const _PeerProfileDeleteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final radius = BorderRadius.circular(responsive.radius(8));
    final tapHeight = responsive.isCompact
        ? 48.0
        : responsive.displayScaled(48);
    final visualHeight = responsive.isCompact
        ? 40.0
        : responsive.displayScaled(40);
    return AppPressable(
      key: const Key('peer-profile-delete-thread'),
      onTap: onPressed,
      semanticLabel: context.l10n.peerProfileDeleteThread,
      tooltip: context.l10n.peerProfileDeleteThread,
      borderRadius: radius,
      scaleOnPress: true,
      pressedScale: 0.97,
      builder: (context, state, child) => AnimatedOpacity(
        opacity: state.pressed
            ? 0.78
            : state.hovered || state.focused
            ? 0.88
            : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: child,
      ),
      child: SizedBox(
        height: tapHeight,
        child: Center(
          child: Container(
            key: const Key('peer-profile-delete-thread-visual'),
            height: visualHeight,
            padding: EdgeInsets.symmetric(horizontal: responsive.spacing(14)),
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: radius),
            child: Text(
              context.l10n.peerProfileDeleteThread,
              style: TextStyle(
                color: theme.danger,
                fontSize: responsive.isCompact ? 16 : responsive.bodyMd,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _compactHomepageLabel(String homepageUrl) {
  final uri = Uri.tryParse(homepageUrl);
  if (uri == null || uri.host.isEmpty) {
    return homepageUrl;
  }
  final path = uri.path == '/' ? '' : uri.path;
  return '${uri.host}$path';
}

String _mergePeerRelationship(
  String relationship, {
  required bool listedAsFollowing,
}) {
  if (!listedAsFollowing) {
    return relationship;
  }
  return switch (relationship) {
    'none' => 'following',
    'follower' => 'friend',
    _ => relationship,
  };
}
