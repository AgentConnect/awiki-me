import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../chat/chat_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../conversation_list/conversation_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/avatar_badge.dart';
import '../shared/copyable_did_line.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/identity_flow.dart';
import '../shared/identity_profile_surface.dart';
import '../shared/responsive_layout.dart';
import '../shared/semantic_pill.dart';
import '../shared/widgets/app_widgets.dart';
import 'peer_display_profile_provider.dart';
import 'profile_markdown.dart';
import 'peer_profile_provider.dart';

class PeerProfilePage extends ConsumerWidget {
  const PeerProfilePage({
    super.key,
    required this.did,
    this.embedded = false,
    this.onBack,
  });

  final String did;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(peerProfileProvider(did));
    final theme = context.awikiTheme;
    final profile = state.profile;
    final rawProfileContent = profile == null
        ? ''
        : (profile.profileMarkdown.trim().isNotEmpty
              ? profile.profileMarkdown.trim()
              : profile.bio.trim());
    final profileContent = profileArticleBody(
      DidDisplayFormatter.withoutRedundantIdentityMetadata(rawProfileContent),
    );
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
    final handleLabel = profile == null
        ? ''
        : DidDisplayFormatter.profileHandleLabel(profile);
    final homepageUrl = profile == null
        ? ''
        : ref.watch(profileHomepageResolverProvider).homepageUrl(profile);
    final responsive = context.awikiResponsive;
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
                : ListView(
                    padding: EdgeInsets.fromLTRB(
                      0,
                      responsive.spacing(14),
                      0,
                      responsive.spacing(24),
                    ),
                    children: <Widget>[
                      AwikiMeTopBar(
                        title: context.l10n.peerProfileTitle,
                        padding: EdgeInsets.zero,
                        leading: embedded && onBack == null
                            ? const SizedBox.shrink()
                            : TopBarActionButton(
                                onTap:
                                    onBack ?? () => Navigator.of(context).pop(),
                                child: AwikiAssetIcon(
                                  assetName: 'assets/icons/icon_left.svg',
                                  color: theme.primaryDark,
                                  size: 22,
                                ),
                              ),
                      ),
                      SizedBox(height: responsive.spacing(16)),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: responsive.spacing(16),
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                SelectionArea(
                                  child: IdentityProfileCard(
                                    key: const Key(
                                      'peer-profile-identity-card',
                                    ),
                                    header: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        AvatarBadge(
                                          seed: displayName,
                                          size: responsive.isPhone ? 58 : 56,
                                          avatarUri: profile.avatarUri,
                                        ),
                                        SizedBox(width: responsive.spacing(14)),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Text(
                                                displayName,
                                                key: const Key(
                                                  'peer-profile-display-name',
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: responsive.isPhone
                                                      ? 20
                                                      : 18,
                                                  fontWeight: FontWeight.w700,
                                                  color: theme.title,
                                                ),
                                              ),
                                              if (handleLabel
                                                  .isNotEmpty) ...<Widget>[
                                                SizedBox(
                                                  height: responsive.spacing(3),
                                                ),
                                                Text(
                                                  handleLabel,
                                                  key: const Key(
                                                    'peer-profile-handle-value',
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: theme.secondaryText,
                                                    fontSize: responsive.bodySm,
                                                  ),
                                                ),
                                              ],
                                              SizedBox(
                                                height: responsive.spacing(8),
                                              ),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: <Widget>[
                                                  SemanticPill(
                                                    label: context
                                                        .l10n
                                                        .identityTypeUser,
                                                    tone: SemanticPillTone
                                                        .identity,
                                                  ),
                                                  SemanticPill(
                                                    label:
                                                        localizeRelationshipLabel(
                                                          context.l10n,
                                                          state.relationship,
                                                        ),
                                                    tone: SemanticPillTone
                                                        .relationship,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(width: responsive.spacing(8)),
                                        _PeerProfileRelationshipButton(
                                          following:
                                              state.relationship ==
                                                  'following' ||
                                              state.relationship == 'friend',
                                          onTap: () =>
                                              state.relationship ==
                                                      'following' ||
                                                  state.relationship == 'friend'
                                              ? ref
                                                    .read(
                                                      peerProfileProvider(
                                                        did,
                                                      ).notifier,
                                                    )
                                                    .unfollow()
                                              : ref
                                                    .read(
                                                      peerProfileProvider(
                                                        did,
                                                      ).notifier,
                                                    )
                                                    .follow(),
                                        ),
                                      ],
                                    ),
                                    metadata: <Widget>[
                                      IdentityProfileMetadataRow(
                                        label: 'DID',
                                        child: CopyableDidLine(
                                          value: profile.did,
                                          displayValue:
                                              DidDisplayFormatter.compactDidPath(
                                                profile.did,
                                              ),
                                          maxLines: 2,
                                          copySemanticLabel:
                                              context.l10n.chatPeerInfoCopyDid,
                                          copiedMessage: context
                                              .l10n
                                              .chatPeerInfoDidCopied,
                                          textKey: const Key(
                                            'peer-profile-did-value',
                                          ),
                                          buttonKey: const Key(
                                            'peer-profile-copy-did-button',
                                          ),
                                          textStyle: TextStyle(
                                            color: theme.body,
                                            fontSize: responsive.bodySm,
                                            height: 1.35,
                                          ),
                                          buttonSize: responsive.displayScaled(
                                            30,
                                          ),
                                          iconSize: responsive.displayScaled(
                                            14,
                                          ),
                                        ),
                                      ),
                                      if (homepageUrl.isNotEmpty)
                                        IdentityProfileMetadataRow(
                                          label:
                                              context.l10n.profileHomepageLabel,
                                          child: IdentityProfileLinkValue(
                                            value: homepageUrl,
                                            actionLabel: context
                                                .l10n
                                                .profileOpenHomepage,
                                            onTap: () async {
                                              final url = Uri.parse(
                                                homepageUrl,
                                              );
                                              try {
                                                await launchUrl(
                                                  url,
                                                  mode: LaunchMode
                                                      .externalApplication,
                                                );
                                              } catch (error) {
                                                ref
                                                    .read(
                                                      peerProfileProvider(
                                                        did,
                                                      ).notifier,
                                                    )
                                                    .showLinkOpenError(error);
                                              }
                                            },
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: responsive.spacing(14)),
                                SelectionArea(
                                  child: IdentityDocumentCard(
                                    key: const Key(
                                      'peer-profile-identity-document',
                                    ),
                                    title:
                                        context.l10n.chatPeerInfoIdentityCard,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        if (profileContent.isEmpty)
                                          Text(
                                            context.l10n.profileEmpty,
                                            style:
                                                AwikiMeTextStyles.cardSubtitle,
                                          )
                                        else
                                          MarkdownBody(
                                            data: profileContent,
                                            styleSheet: _peerMarkdownStyleSheet(
                                              context,
                                            ),
                                          ),
                                        if (profile
                                            .tags
                                            .isNotEmpty) ...<Widget>[
                                          SizedBox(
                                            height: responsive.spacing(16),
                                          ),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: profile.tags
                                                .map(
                                                  (tag) => AppPill(label: tag),
                                                )
                                                .toList(),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(height: responsive.spacing(14)),
                                AppPrimaryButton(
                                  key: const Key('peer-profile-send-message'),
                                  label: context.l10n.peerProfileSendMessage,
                                  onPressed: () async {
                                    await openDirectConversationForProfile(
                                      context,
                                      ref,
                                      profile,
                                    );
                                    if (!embedded && context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  },
                                ),
                                SizedBox(height: responsive.spacing(10)),
                                AppDangerButton(
                                  label: context.l10n.peerProfileDeleteThread,
                                  onPressed: () async {
                                    try {
                                      final conversationId =
                                          await resolveCanonicalConversationIdForProfile(
                                            ref,
                                            profile,
                                          );
                                      final conversations = ref
                                          .read(conversationListProvider)
                                          .conversations
                                          .where(
                                            (item) =>
                                                item.conversationId ==
                                                conversationId,
                                          )
                                          .toList(growable: false);
                                      if (conversations.length > 1) {
                                        throw StateError(
                                          'canonical_conversation_not_unique',
                                        );
                                      }
                                      if (conversations.length == 1) {
                                        await ref
                                            .read(chatThreadsProvider.notifier)
                                            .deleteConversation(
                                              conversations.single,
                                            );
                                      }
                                      ref
                                          .read(uiFeedbackProvider.notifier)
                                          .showInfo(
                                            AppMessage.peerProfileThreadDeleted(),
                                          );
                                    } catch (error) {
                                      if (isSessionEpochChangedError(error)) {
                                        return;
                                      }
                                      ref
                                          .read(uiFeedbackProvider.notifier)
                                          .showError(
                                            AppMessage.fromError(error),
                                          );
                                    }
                                  },
                                ),
                              ],
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

class _PeerProfileRelationshipButton extends StatelessWidget {
  const _PeerProfileRelationshipButton({
    required this.following,
    required this.onTap,
  });

  final bool following;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final label = following
        ? context.l10n.peerProfileUnfollow
        : context.l10n.friendsFollow;
    return AppPressable(
      key: following ? null : const Key('peer-profile-follow'),
      onTap: onTap,
      semanticLabel: label,
      tooltip: label,
      scaleOnPress: true,
      pressedScale: 0.97,
      borderRadius: BorderRadius.circular(responsive.radius(8)),
      child: Container(
        constraints: BoxConstraints(
          minWidth: responsive.displayScaled(62),
          minHeight: responsive.displayScaled(34),
        ),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: responsive.spacing(10)),
        decoration: BoxDecoration(
          color: following ? theme.surface : theme.primary,
          borderRadius: BorderRadius.circular(responsive.radius(8)),
          border: Border.all(color: following ? theme.border : theme.primary),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: following ? theme.secondaryText : theme.primaryForeground,
            fontSize: responsive.bodySm,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

MarkdownStyleSheet _peerMarkdownStyleSheet(BuildContext context) {
  final theme = context.awikiTheme;
  final responsive = context.awikiResponsive;
  final bodyStyle = AwikiMeTextStyles.markdownBody.copyWith(
    fontSize: responsive.isPhone ? 16 : 13,
    color: theme.body,
  );
  return MarkdownStyleSheet(
    p: bodyStyle,
    strong: bodyStyle.copyWith(fontWeight: FontWeight.w600),
    h1: bodyStyle.copyWith(fontSize: responsive.isPhone ? 20 : 17),
    h2: bodyStyle.copyWith(fontSize: responsive.isPhone ? 18 : 15),
  );
}
