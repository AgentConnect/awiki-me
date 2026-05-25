import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_router.dart';
import '../../app/ui_feedback.dart';
import '../../application/thread_id_utils.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/navigation_provider.dart';
import '../app_shell/providers/selected_conversation_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../chat/chat_page.dart';
import '../chat/chat_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/avatar_badge.dart';
import '../shared/formatters/display_formatters.dart';
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
                    child: Text(
                      context.l10n.peerProfileLoadFailed,
                      style: TextStyle(color: theme.danger),
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
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                          color: theme.title,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        profile.did,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AwikiMeTextStyles.cardSubtitle,
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
                              label: DidDisplayFormatter.homepageUrl(profile),
                              onTap: () async {
                                final url = Uri.parse(
                                  DidDisplayFormatter.homepageUrl(profile),
                                );
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
                              MarkdownBody(data: profileContent),
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
                          final myDid = ref.read(sessionProvider).session?.did;
                          if (myDid == null) {
                            return;
                          }
                          final threadId = canonicalDirectThreadId(
                            myDid,
                            profile.did,
                          );
                          final conversation = ConversationSummary(
                            threadId: threadId,
                            displayName: DidDisplayFormatter.profileName(
                              profile,
                            ),
                            lastMessagePreview: '',
                            lastMessageAt: DateTime.now(),
                            unreadCount: 0,
                            isGroup: false,
                            targetDid: profile.did,
                          );
                          await ref
                              .read(chatThreadsProvider.notifier)
                              .openConversation(conversation);
                          if (!context.mounted) {
                            return;
                          }
                          if (context.awikiResponsive.supportsTwoPane) {
                            ref
                                .read(selectedConversationProvider.notifier)
                                .selectConversation(conversation);
                            ref.read(shellTabProvider.notifier).setTab(0);
                            Navigator.of(context).pop();
                            return;
                          }
                          Navigator.of(context).pop();
                          await AppNavigator.push(
                            context,
                            (_) => ChatPage(conversation: conversation),
                          );
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
                          final threadId = canonicalDirectThreadId(
                            myDid,
                            profile.did,
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
