import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../domain/entities/user_profile.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/session_provider.dart';
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
import '../shared/widgets/app_widgets.dart';
import 'peer_profile_provider.dart';

class PeerProfilePage extends ConsumerWidget {
  const PeerProfilePage({super.key, required this.did});

  final String did;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(peerProfileProvider(did));
    final theme = context.awikiTheme;
    final profile = state.profile;
    final profileContent = profile == null
        ? ''
        : (profile.profileMarkdown.trim().isNotEmpty
              ? profile.profileMarkdown.trim()
              : profile.bio.trim());
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
                                  seed: DidDisplayFormatter.profileName(
                                    profile,
                                  ),
                                  size: 72,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        DidDisplayFormatter.profileName(
                                          profile,
                                        ),
                                        style: TextStyle(
                                          fontSize:
                                              context.awikiResponsive.isPhone
                                              ? 22
                                              : 20,
                                          fontWeight: FontWeight.w500,
                                          color: theme.title,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      CopyableDidLine(
                                        value: profile.did,
                                        copySemanticLabel: '复制 DID',
                                        copiedMessage: 'DID 已复制',
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
                                AppPill(
                                  label: localizeRelationshipLabel(
                                    context.l10n,
                                    state.relationship,
                                  ),
                                ),
                                if (profile.handle?.isNotEmpty == true)
                                  AppPill(label: '@${profile.handle}'),
                              ],
                            ),
                            const SizedBox(height: 16),
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
                          final myDid = ref.read(sessionProvider).session?.did;
                          if (myDid == null) {
                            return;
                          }
                          final threadId = _threadIdForProfile(
                            ref,
                            profile,
                            ownerDid: myDid,
                          );
                          try {
                            await ref
                                .read(chatThreadsProvider.notifier)
                                .deleteThread(threadId);
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

String _threadIdForProfile(
  WidgetRef ref,
  UserProfile profile, {
  required String ownerDid,
}) {
  final peerTarget = _directPeerTarget(profile.fullHandle ?? profile.handle);
  final peerDid = profile.did.trim();
  final existing = ref
      .read(conversationListProvider)
      .conversations
      .where(
        (item) =>
            !item.isGroup &&
            ((peerTarget != null &&
                    _directPeerTarget(item.targetPeer) == peerTarget) ||
                item.targetDid?.trim() == peerDid),
      );
  if (existing.isNotEmpty) {
    return existing.first.threadId;
  }
  return dmThreadIdForDids(ownerDid, peerDid);
}

String? _directPeerTarget(String? value) {
  final target = value?.trim();
  if (target == null || target.isEmpty) {
    return null;
  }
  return target.startsWith('did:') ? target : target.toLowerCase();
}
