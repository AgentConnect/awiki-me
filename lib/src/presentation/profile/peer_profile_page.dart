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
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/copyable_did_line.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/identity_flow.dart';
import '../shared/identity_profile_surface.dart';
import '../shared/responsive_layout.dart';
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
    final isFollowing =
        state.relationship == 'following' || state.relationship == 'friend';
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
                          horizontal: IdentityProfileLayout.contentInset(
                            context,
                          ),
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
                                    header: IdentityProfileHeader(
                                      displayName: displayName,
                                      displayNameKey: const Key(
                                        'peer-profile-display-name',
                                      ),
                                      avatarSeed: displayName,
                                      avatarUri: profile.avatarUri,
                                      handle: handleLabel,
                                      handleKey: const Key(
                                        'peer-profile-handle-value',
                                      ),
                                      badges: <Widget>[
                                        IdentityProfileBadge(
                                          label: context.l10n.identityTypeUser,
                                        ),
                                        IdentityProfileBadge(
                                          label: localizeRelationshipLabel(
                                            context.l10n,
                                            state.relationship,
                                          ),
                                          tone: isFollowing
                                              ? IdentityProfileBadgeTone.success
                                              : IdentityProfileBadgeTone
                                                    .outlined,
                                        ),
                                      ],
                                      trailing: _PeerProfileRelationshipButton(
                                        following: isFollowing,
                                        onTap: () => isFollowing
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
                                            fontSize: responsive.bodyMd,
                                            height: 1.35,
                                          ),
                                          buttonSize: responsive.displayScaled(
                                            30,
                                          ),
                                          iconSize: responsive.displayScaled(
                                            14,
                                          ),
                                          showButtonChrome: false,
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
                                SizedBox(
                                  height: IdentityProfileLayout.sectionGap(
                                    context,
                                  ),
                                ),
                                SelectionArea(
                                  child: IdentityDocumentCard(
                                    key: const Key(
                                      'peer-profile-identity-document',
                                    ),
                                    title:
                                        context.l10n.chatPeerInfoIdentityCard,
                                    child: IdentityDocumentContent(
                                      content: profileContent,
                                      emptyText: context.l10n.profileEmpty,
                                      tags: profile.tags,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: IdentityProfileLayout.sectionGap(
                                    context,
                                  ),
                                ),
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
    final label = following
        ? context.l10n.peerProfileUnfollow
        : context.l10n.friendsFollow;
    return IdentityProfileActionButton(
      key: following ? null : const Key('peer-profile-follow'),
      label: label,
      emphasized: !following,
      onPressed: () {
        onTap();
      },
    );
  }
}
