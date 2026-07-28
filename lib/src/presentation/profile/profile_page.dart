import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea, SelectionContainer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_services.dart';
import '../../app/app_router.dart';
import '../../app/ui_feedback.dart';
import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/user_profile.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../friends/friends_provider.dart';
import '../shared/app_dialog.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_semantic_icon.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/copyable_did_line.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/identity_profile_surface.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'profile_markdown.dart';
import 'profile_provider.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({
    super.key,
    this.homepageMarkdownLoader,
    this.embedded = false,
    this.bottomInset = 120,
    this.showTitle = true,
    this.shrinkWrap = false,
    this.onBack,
  });

  final Future<String?> Function(String url)? homepageMarkdownLoader;
  final bool embedded;
  final double bottomInset;
  final bool showTitle;
  final bool shrinkWrap;
  final VoidCallback? onBack;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  String? _loadedHomepageUrl;
  bool _requestedRelationshipCounts = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final overrides = <Override>[
      if (widget.homepageMarkdownLoader != null)
        homepageMarkdownLoaderProvider.overrideWithValue(
          widget.homepageMarkdownLoader!,
        ),
    ];
    if (overrides.isNotEmpty) {
      return ProviderScope(
        overrides: overrides,
        child: ProfilePage(
          embedded: widget.embedded,
          bottomInset: widget.bottomInset,
          showTitle: widget.showTitle,
          shrinkWrap: widget.shrinkWrap,
          onBack: widget.onBack,
        ),
      );
    }
    final state = ref.watch(profileProvider);
    final profile = state.profile;
    if (profile == null) {
      return const Center(child: CupertinoActivityIndicator());
    }
    _syncHomepage(profile);
    _syncRelationshipCounts();

    final displayName = DidDisplayFormatter.profileName(profile);
    final handleLabel = DidDisplayFormatter.identityLookupSecondaryHandle(
      profile,
    );
    final homepageUrl = ref
        .watch(profileHomepageResolverProvider)
        .homepageUrl(profile);
    final profileContent = DidDisplayFormatter.withoutRedundantIdentityMetadata(
      ref.read(profileProvider.notifier).visibleProfileContent(),
    );
    final responsive = context.awikiResponsive;
    final friendsState = ref.watch(friendsProvider);

    final profileBody = SelectionArea(
      child: ListView(
        shrinkWrap: widget.shrinkWrap,
        padding: EdgeInsets.fromLTRB(
          IdentityProfileLayout.contentInset(context),
          responsive.displayScaled(widget.embedded ? 8 : 18),
          IdentityProfileLayout.contentInset(context),
          widget.embedded ? widget.bottomInset : 120,
        ),
        children: <Widget>[
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  IdentityProfileCard(
                    key: const Key('profile-identity-card'),
                    header: IdentityProfileHeader(
                      displayName: displayName,
                      displayNameKey: const Key('profile-display-name'),
                      avatarSeed: handleLabel.isEmpty
                          ? displayName
                          : handleLabel,
                      avatarUri: profile.avatarUri,
                      handle: handleLabel,
                      handleKey: const Key('profile-handle-value'),
                      badges: <Widget>[
                        IdentityProfileBadge(
                          label: context.l10n.identityTypeUser,
                        ),
                      ],
                      trailing: SelectionContainer.disabled(
                        child: AppIconButton(
                          key: const Key('profile-edit-button'),
                          onPressed: state.isSaving
                              ? null
                              : () => _showEditProfileDialog(context, profile),
                          semanticLabel: context.l10n.profileEditTitle,
                          tooltip: context.l10n.profileEditTitle,
                          size: responsive.displayScaled(40),
                          backgroundColor: theme.subtleSurface,
                          borderColor: theme.border,
                          borderRadius: BorderRadius.circular(
                            responsive.displayScaled(AwikiMeRadii.control),
                          ),
                          child: AwikiMeSemanticIcon(
                            role: AwikiMeIconRole.edit,
                            size: responsive.iconSm,
                            color: theme.primaryDark,
                          ),
                        ),
                      ),
                    ),
                    metadata: <Widget>[
                      IdentityProfileMetadataRow(
                        label: 'DID',
                        child: CopyableDidLine(
                          value: profile.did,
                          displayValue: DidDisplayFormatter.compactDidPath(
                            profile.did,
                          ),
                          maxLines: 2,
                          copySemanticLabel: context.l10n.chatPeerInfoCopyDid,
                          copiedMessage: context.l10n.chatPeerInfoDidCopied,
                          textKey: const Key('profile-did-value'),
                          buttonKey: const Key('profile-copy-did-button'),
                          textStyle: TextStyle(
                            fontSize: responsive.bodyMd,
                            height: 1.35,
                            color: theme.body,
                          ),
                          buttonSize: responsive.displayScaled(30),
                          iconSize: responsive.displayScaled(14),
                          showButtonChrome: false,
                        ),
                      ),
                      if (homepageUrl.isNotEmpty)
                        IdentityProfileMetadataRow(
                          label: context.l10n.profileHomepageLabel,
                          child: IdentityProfileLinkValue(
                            value: homepageUrl,
                            actionLabel: context.l10n.profileOpenHomepage,
                            onTap: () => _openHomepage(homepageUrl),
                          ),
                        ),
                    ],
                    footer: _ProfileStatistics(
                      followersCount: friendsState.followers.length,
                      followingCount: friendsState.following.length,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(14)),
                  IdentityDocumentCard(
                    key: const Key('profile-identity-document'),
                    title: context.l10n.chatPeerInfoIdentityCard,
                    child: IdentityDocumentContent(
                      content: profileArticleBody(profileContent),
                      emptyText: context.l10n.profileEmpty,
                      tags: profile.tags,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    final content = widget.showTitle
        ? widget.onBack == null
              ? AwikiMeShellTabPage(
                  title: context.l10n.profileMeTitle,
                  child: profileBody,
                )
              : Column(
                  children: <Widget>[
                    Padding(
                      padding: responsive.scaledInsets(
                        responsive.tabInnerPadding.copyWith(bottom: 8),
                      ),
                      child: AwikiMeTopBar(
                        title: context.l10n.profileMeTitle,
                        padding: EdgeInsets.zero,
                        leading: TopBarActionButton(
                          key: const Key('profile-back-button'),
                          onTap: widget.onBack,
                          semanticsLabel: context.l10n.commonBack,
                          tooltip: context.l10n.commonBack,
                          child: Icon(
                            CupertinoIcons.chevron_left,
                            size: responsive.iconMd,
                            color: theme.secondaryText,
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: profileBody),
                  ],
                )
        : profileBody;
    if (widget.embedded) {
      return content;
    }
    if (responsive.supportsTwoPane) {
      return AwikiAdaptiveScaffold(maxWidth: 900, child: content);
    }
    return CupertinoPageScaffold(
      backgroundColor: theme.surface,
      child: SafeArea(bottom: false, child: content),
    );
  }

  void _syncHomepage(UserProfile profile) {
    final homepageUrl = ref
        .read(profileHomepageResolverProvider)
        .homepageUrl(profile);
    if (homepageUrl.isEmpty || _loadedHomepageUrl == homepageUrl) {
      return;
    }
    _loadedHomepageUrl = homepageUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(profileProvider.notifier).loadHomepageMarkdown(homepageUrl);
    });
  }

  void _syncRelationshipCounts() {
    if (_requestedRelationshipCounts) {
      return;
    }
    _requestedRelationshipCounts = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(friendsProvider.notifier).refresh();
    });
  }

  Future<void> _openHomepage(String homepageUrl) async {
    final url = Uri.parse(homepageUrl);
    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.linkOpenFailed());
    }
  }

  Future<void> _showEditProfileDialog(
    BuildContext context,
    UserProfile profile,
  ) async {
    final nickController = TextEditingController(text: profile.displayName);
    final bioController = TextEditingController(text: profile.bio);
    final tagsController = TextEditingController(text: profile.tags.join(', '));

    try {
      await AppNavigator.showDialog<void>(
        context,
        (dialogContext) => _ProfileEditDialog(
          nickController: nickController,
          bioController: bioController,
          tagsController: tagsController,
          onSave: () async {
            final patch = ProfilePatch(
              displayName: nickController.text.trim(),
              bio: bioController.text.trim(),
              tags: tagsController.text
                  .split(',')
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .toList(),
            );
            Navigator.of(dialogContext).pop();
            await ref.read(profileProvider.notifier).updateProfile(patch);
          },
        ),
      );
    } finally {
      nickController.dispose();
      bioController.dispose();
      tagsController.dispose();
    }
  }
}

class _ProfileEditDialog extends StatelessWidget {
  const _ProfileEditDialog({
    required this.nickController,
    required this.bioController,
    required this.tagsController,
    required this.onSave,
  });

  final TextEditingController nickController;
  final TextEditingController bioController;
  final TextEditingController tagsController;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppDialogScaffold(
      key: const Key('profile-edit-dialog'),
      maxWidth: 560,
      maxHeightFraction: 0.9,
      avoidViewInsets: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          responsive.spacing(20),
          responsive.spacing(16),
          responsive.spacing(20),
          responsive.spacing(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppDialogHeader(
              title: context.l10n.profileEditTitle,
              onClose: () => Navigator.of(context).pop(),
            ),
            SizedBox(height: responsive.spacing(16)),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    AppTextField(
                      controller: nickController,
                      label: context.l10n.onboardingNickname,
                      placeholder: context.l10n.onboardingNicknamePlaceholder,
                    ),
                    SizedBox(height: responsive.spacing(10)),
                    AppTextField(
                      controller: bioController,
                      label: context.l10n.profileEditTitle,
                      placeholder: context.l10n.profileBioPlaceholder,
                      multiline: true,
                    ),
                    SizedBox(height: responsive.spacing(10)),
                    AppTextField(
                      controller: tagsController,
                      label: context.l10n.profileTagsPlaceholder,
                      placeholder: context.l10n.profileTagsPlaceholder,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: responsive.spacing(16)),
            Row(
              children: <Widget>[
                Expanded(
                  child: AppSecondaryButton(
                    label: context.l10n.commonCancel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                SizedBox(width: responsive.spacing(10)),
                Expanded(
                  child: AppPrimaryButton(
                    label: context.l10n.commonSave,
                    onPressed: onSave,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStatistics extends StatelessWidget {
  const _ProfileStatistics({
    required this.followersCount,
    required this.followingCount,
  });

  final int followersCount;
  final int followingCount;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Row(
      children: <Widget>[
        _ProfileStat(
          value: _formatCount(followersCount),
          label: context.l10n.profileFollowers,
        ),
        SizedBox(width: responsive.displayScaled(28)),
        _ProfileStat(
          value: _formatCount(followingCount),
          label: context.l10n.profileFollowing,
        ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count < 1000) {
      return count.toString();
    }
    if (count < 1000000) {
      final value = count / 1000;
      return '${_trimDecimal(value)}k';
    }
    final value = count / 1000000;
    return '${_trimDecimal(value)}m';
  }

  String _trimDecimal(double value) {
    final fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: responsive.bodyMd + 2,
            fontWeight: FontWeight.w600,
            color: theme.title,
          ),
        ),
        SizedBox(width: responsive.spacing(5)),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: responsive.metaSm,
            color: theme.secondaryText,
          ),
        ),
      ],
    );
  }
}
