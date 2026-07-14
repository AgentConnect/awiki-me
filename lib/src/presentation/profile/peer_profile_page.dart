import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../chat/chat_provider.dart';
import '../conversation_list/conversation_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/avatar_badge.dart';
import '../shared/copyable_did_line.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/identity_flow.dart';
import '../shared/responsive_layout.dart';
import '../shared/semantic_pill.dart';
import '../shared/widgets/app_widgets.dart';
import 'peer_display_profile_provider.dart';
import 'peer_profile_provider.dart';

class PeerProfilePage extends ConsumerWidget {
  const PeerProfilePage({super.key, required this.did});

  final String did;

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
    final profileContent = DidDisplayFormatter.withoutRedundantIdentityMetadata(
      rawProfileContent,
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
    final secondaryName = profile == null
        ? ''
        : DidDisplayFormatter.secondaryProfileName(profile);
    final homepageUrl = profile == null
        ? ''
        : ref.watch(profileHomepageResolverProvider).homepageUrl(profile);
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
                    padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
                    children: <Widget>[
                      AwikiMeTopBar(
                        title: context.l10n.peerProfileTitle,
                        padding: EdgeInsets.zero,
                        leading: TopBarActionButton(
                          onTap: () => Navigator.of(context).pop(),
                          child: AwikiAssetIcon(
                            assetName: 'assets/icons/icon_left.svg',
                            color: theme.primaryDark,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppCardSection(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                AvatarBadge(
                                  seed: displayName,
                                  size: 72,
                                  avatarUri: profile.avatarUri,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        handleLabel,
                                        key: const Key(
                                          'peer-profile-handle-value',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize:
                                              context.awikiResponsive.isPhone
                                              ? 24
                                              : 22,
                                          fontWeight: FontWeight.w700,
                                          color: theme.title,
                                        ),
                                      ),
                                      if (secondaryName.isNotEmpty) ...<Widget>[
                                        const SizedBox(height: 4),
                                        Text(
                                          secondaryName,
                                          key: const Key(
                                            'peer-profile-display-name',
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AwikiMeTextStyles.cardSubtitle,
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      CopyableDidLine(
                                        value: profile.did,
                                        displayValue:
                                            DidDisplayFormatter.compactDidPath(
                                              profile.did,
                                            ),
                                        maxLines: 2,
                                        copySemanticLabel:
                                            context.l10n.chatPeerInfoCopyDid,
                                        copiedMessage:
                                            context.l10n.chatPeerInfoDidCopied,
                                        textKey: const Key(
                                          'peer-profile-did-value',
                                        ),
                                        buttonKey: const Key(
                                          'peer-profile-copy-did-button',
                                        ),
                                        textStyle:
                                            AwikiMeTextStyles.cardSubtitle,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: <Widget>[
                                SemanticPill(
                                  label: context.l10n.identityTypeUser,
                                  tone: SemanticPillTone.identity,
                                ),
                                SemanticPill(
                                  label: localizeRelationshipLabel(
                                    context.l10n,
                                    state.relationship,
                                  ),
                                  tone: SemanticPillTone.relationship,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (homepageUrl.isNotEmpty)
                              AppInlineLinkRow(
                                label: homepageUrl,
                                onTap: () async {
                                  final url = Uri.parse(homepageUrl);
                                  try {
                                    await launchUrl(
                                      url,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  } catch (error) {
                                    ref
                                        .read(peerProfileProvider(did).notifier)
                                        .showLinkOpenError(error);
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppCardSection(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (profileContent.isEmpty)
                              Text(
                                context.l10n.profileEmpty,
                                style: AwikiMeTextStyles.cardSubtitle,
                              )
                            else
                              MarkdownBody(
                                data: profileContent,
                                styleSheet: _peerMarkdownStyleSheet(context),
                              ),
                            if (profile.tags.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: profile.tags
                                    .map((tag) => AppPill(label: tag))
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppPrimaryButton(
                        label: context.l10n.peerProfileSendMessage,
                        onPressed: () async {
                          await openDirectConversationForProfile(
                            context,
                            ref,
                            profile,
                          );
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                      if (state.relationship == 'following' ||
                          state.relationship == 'friend') ...<Widget>[
                        const SizedBox(height: 10),
                        AppSecondaryButton(
                          label: context.l10n.peerProfileUnfollow,
                          onPressed: () => ref
                              .read(peerProfileProvider(did).notifier)
                              .unfollow(),
                        ),
                      ],
                      const SizedBox(height: 10),
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
                                      item.conversationId == conversationId,
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
                                  .deleteConversation(conversations.single);
                            }
                            ref
                                .read(uiFeedbackProvider.notifier)
                                .showInfo(
                                  AppMessage.peerProfileThreadDeleted(),
                                );
                          } catch (error) {
                            ref
                                .read(uiFeedbackProvider.notifier)
                                .showError(AppMessage.fromError(error));
                          }
                        },
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
