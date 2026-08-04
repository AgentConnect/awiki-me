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
import '../app_shell/providers/navigation_provider.dart';
import '../shared/app_dialog.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_semantic_icon.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/copyable_did_line.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/identity_profile_surface.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'profile_edit_page.dart';
import 'profile_provider.dart';

enum _CompactProfileSection { did, homepage }

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({
    super.key,
    this.homepageMarkdownLoader,
    this.embedded = false,
    this.bottomInset = 120,
    this.showTitle = true,
    this.shrinkWrap = false,
    this.title,
    this.onBack,
    this.onFollowingTap,
    this.onFollowersTap,
  });

  final Future<String?> Function(String url)? homepageMarkdownLoader;
  final bool embedded;
  final double bottomInset;
  final bool showTitle;
  final bool shrinkWrap;
  final String? title;
  final VoidCallback? onBack;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onFollowersTap;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  String? _loadedHomepageUrl;
  bool _requestedRelationshipCounts = false;
  _CompactProfileSection? _compactExpandedSection;

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
          title: widget.title,
          onBack: widget.onBack,
          onFollowingTap: widget.onFollowingTap,
          onFollowersTap: widget.onFollowersTap,
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
    final responsive = context.awikiResponsive;
    final pageTitle = widget.title ?? context.l10n.profileMeTitle;
    final friendsState = ref.watch(friendsProvider);
    final profileBody = SelectionArea(
      child: ListView(
        shrinkWrap: widget.shrinkWrap,
        padding: responsive.isCompact
            ? EdgeInsets.fromLTRB(
                0,
                40,
                0,
                widget.embedded ? widget.bottomInset : 88,
              )
            : EdgeInsets.fromLTRB(
                IdentityProfileLayout.contentInset(context),
                responsive.displayScaled(widget.embedded ? 8 : 10),
                IdentityProfileLayout.contentInset(context),
                widget.embedded ? widget.bottomInset : 88,
              ),
        children: <Widget>[
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (responsive.isCompact) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _CompactProfileSummary(
                        displayName: displayName,
                        bio: profile.bio,
                        tags: profile.tags,
                        avatarUri: profile.avatarUri,
                        isSaving: state.isSaving,
                        onEdit: () => _showEditProfileDialog(context, profile),
                        followersCount: friendsState.followers.length,
                        followingCount: friendsState.following.length,
                        onFollowingTap: widget.onFollowingTap,
                        onFollowersTap: widget.onFollowersTap,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SelectionContainer.disabled(
                      child: _CompactProfileNavigationGroup(
                        did: profile.did,
                        homepageUrl: homepageUrl,
                        didTitle: 'DID',
                        homepageTitle: context.l10n.profileHomepageLabel,
                        settingsTitle: context.l10n.settingsTitle,
                        expandedSection: _compactExpandedSection,
                        onDidTap: () => setState(
                          () => _compactExpandedSection =
                              _compactExpandedSection ==
                                  _CompactProfileSection.did
                              ? null
                              : _CompactProfileSection.did,
                        ),
                        onHomepageTap: () => setState(
                          () => _compactExpandedSection =
                              _compactExpandedSection ==
                                  _CompactProfileSection.homepage
                              ? null
                              : _CompactProfileSection.homepage,
                        ),
                        onOpenHomepage: () => _openHomepage(homepageUrl),
                        onSettingsTap: () => _openSettings(context),
                      ),
                    ),
                  ] else ...<Widget>[
                    IdentityProfileCard(
                      key: const Key('profile-identity-card'),
                      header: IdentityProfileHeader(
                        displayName: displayName,
                        displayNameKey: const Key('profile-display-name'),
                        avatarSeed: displayName,
                        avatarUri: profile.avatarUri,
                        avatarSize: responsive.displayScaled(64),
                        handle: handleLabel,
                        handleKey: const Key('profile-handle-value'),
                        trailing: SelectionContainer.disabled(
                          child: AppIconButton(
                            key: const Key('profile-edit-button'),
                            onPressed: state.isSaving
                                ? null
                                : () =>
                                      _showEditProfileDialog(context, profile),
                            semanticLabel: context.l10n.profileEditTitle,
                            tooltip: context.l10n.profileEditTitle,
                            size: responsive.displayScaled(40),
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
                      footer: _ProfileStatistics(
                        followersCount: friendsState.followers.length,
                        followingCount: friendsState.following.length,
                        onFollowingTap: widget.onFollowingTap,
                        onFollowersTap: widget.onFollowersTap,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(
                        top: responsive.spacing(20),
                        bottom: responsive.spacing(6),
                      ),
                      child: Text(
                        context.l10n.profileIdentitySectionTitle,
                        style: TextStyle(
                          color: theme.title,
                          fontSize: responsive.bodyMd,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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
                          fontSize: responsive.bodySm,
                          height: 1.35,
                          color: theme.secondaryText,
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
                    SelectionContainer.disabled(
                      child: _ProfileNavigationRow(
                        key: const Key('profile-settings-row'),
                        icon: CupertinoIcons.gear,
                        title: context.l10n.settingsTitle,
                        subtitle: context.l10n.profileSettingsSubtitle,
                        neutral: true,
                        onTap: () => _openSettings(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    final content = widget.showTitle
        ? responsive.isCompact
              ? _CompactProfileFrame(
                  title: pageTitle,
                  onBack: widget.onBack,
                  child: profileBody,
                )
              : widget.onBack == null
              ? AwikiMeShellTabPage(title: pageTitle, child: profileBody)
              : Column(
                  children: <Widget>[
                    Padding(
                      padding: responsive.scaledInsets(
                        responsive.tabInnerPadding.copyWith(bottom: 8),
                      ),
                      child: AwikiMeTopBar(
                        title: pageTitle,
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

  void _openSettings(BuildContext context) {
    if (AwikiShellNavigationScope.isPresent(context)) {
      ref
          .read(shellDestinationProvider.notifier)
          .selectCompact(ShellDestination.settings);
      return;
    }
    Navigator.of(context).maybePop();
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
    if (context.awikiResponsive.isCompact) {
      await AppNavigator.push<void>(
        context,
        (_) => ProfileEditPage(
          profile: profile,
          onSave: (patch) =>
              ref.read(profileProvider.notifier).updateProfile(patch),
        ),
        rootNavigator: true,
      );
      return;
    }
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

class _CompactProfileFrame extends StatelessWidget {
  const _CompactProfileFrame({
    required this.title,
    required this.child,
    this.onBack,
  });

  final String title;
  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return ColoredBox(
      key: const Key('shell-tab-page-surface'),
      color: theme.background,
      child: Column(
        children: <Widget>[
          DecoratedBox(
            key: const Key('profile-compact-header'),
            decoration: BoxDecoration(color: theme.surface),
            child: AwikiMeTopBar(
              title: title,
              padding: EdgeInsets.symmetric(
                horizontal: onBack == null ? 14 : 24,
                vertical: 6,
              ),
              titleFontSize: awikiMeCompactTopBarTitleFontSize,
              titleFontWeight: awikiMeCompactTopBarTitleFontWeight,
              titleHeight: awikiMeCompactTopBarTitleHeight,
              leading: onBack == null
                  ? const SizedBox.shrink()
                  : TopBarActionButton(
                      key: const Key('profile-back-button'),
                      onTap: onBack,
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
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _CompactProfileSummary extends StatelessWidget {
  const _CompactProfileSummary({
    required this.displayName,
    required this.bio,
    required this.tags,
    required this.avatarUri,
    required this.isSaving,
    required this.onEdit,
    required this.followersCount,
    required this.followingCount,
    required this.onFollowingTap,
    required this.onFollowersTap,
  });

  final String displayName;
  final String bio;
  final List<String> tags;
  final String? avatarUri;
  final bool isSaving;
  final VoidCallback onEdit;
  final int followersCount;
  final int followingCount;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onFollowersTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final visibleTags = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(3)
        .toList(growable: false);
    return Container(
      key: const Key('profile-compact-summary'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.subtleSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AvatarBadge(
                key: const Key('profile-avatar'),
                seed: displayName,
                size: 72,
                avatarUri: avatarUri,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      displayName,
                      key: const Key('profile-display-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.title,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if (bio.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        bio.trim(),
                        key: const Key('profile-bio'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.secondaryText,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (visibleTags.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      Wrap(
                        key: const Key('profile-tags'),
                        spacing: 8,
                        runSpacing: 8,
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
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: SelectionContainer.disabled(
                  child: AppPressable(
                    key: const Key('profile-edit-button'),
                    onTap: isSaving ? null : onEdit,
                    semanticLabel: context.l10n.profileEditTitle,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        context.l10n.profileEditTitle,
                        style: TextStyle(
                          color: theme.primaryForeground,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SelectionContainer.disabled(
                child: Container(
                  width: 126,
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: _CompactProfileStatistics(
                    followersCount: followersCount,
                    followingCount: followingCount,
                    onFollowingTap: onFollowingTap,
                    onFollowersTap: onFollowersTap,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactProfileStatistics extends StatelessWidget {
  const _CompactProfileStatistics({
    required this.followersCount,
    required this.followingCount,
    required this.onFollowingTap,
    required this.onFollowersTap,
  });

  final int followersCount;
  final int followingCount;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onFollowersTap;

  @override
  Widget build(BuildContext context) {
    final followingValue = _formatCompactProfileCount(followingCount);
    final followersValue = _formatCompactProfileCount(followersCount);
    return Stack(
      children: <Widget>[
        const Positioned(
          top: 7,
          left: 0,
          right: 0,
          height: 30,
          child: SizedBox(key: Key('profile-statistics')),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: _ProfileStatAction(
                key: const Key('profile-following-stat-button'),
                value: followingValue,
                label: context.l10n.profileFollowing,
                onTap: onFollowingTap,
              ),
            ),
            Container(
              key: const Key('profile-statistics-divider'),
              width: 1,
              height: 30,
              color: context.awikiTheme.border,
            ),
            Expanded(
              child: _ProfileStatAction(
                key: const Key('profile-followers-stat-button'),
                value: followersValue,
                label: context.l10n.profileFollowers,
                onTap: onFollowersTap,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _formatCompactProfileCount(int count) {
  if (count < 1000) {
    return count.toString();
  }
  if (count < 1000000) {
    return _compactCountWithSuffix(count / 1000, 'k');
  }
  return _compactCountWithSuffix(count / 1000000, 'm');
}

String _compactCountWithSuffix(double value, String suffix) {
  final fixed = value.toStringAsFixed(1);
  final compact = fixed.endsWith('.0')
      ? fixed.substring(0, fixed.length - 2)
      : fixed;
  return '$compact$suffix';
}

class _CompactProfileNavigationGroup extends StatelessWidget {
  const _CompactProfileNavigationGroup({
    required this.did,
    required this.homepageUrl,
    required this.didTitle,
    required this.homepageTitle,
    required this.settingsTitle,
    required this.expandedSection,
    required this.onDidTap,
    required this.onHomepageTap,
    required this.onOpenHomepage,
    required this.onSettingsTap,
  });

  final String did;
  final String homepageUrl;
  final String didTitle;
  final String homepageTitle;
  final String settingsTitle;
  final _CompactProfileSection? expandedSection;
  final VoidCallback onDidTap;
  final VoidCallback onHomepageTap;
  final VoidCallback onOpenHomepage;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final hasHomepage = homepageUrl.trim().isNotEmpty;
    final didExpanded = expandedSection == _CompactProfileSection.did;
    final homepageExpanded =
        hasHomepage && expandedSection == _CompactProfileSection.homepage;
    return SizedBox(
      key: const Key('profile-navigation-group'),
      width: double.infinity,
      child: Column(
        children: <Widget>[
          Container(
            key: const Key('profile-navigation-top-divider'),
            height: 1,
            color: theme.border,
          ),
          _CompactProfileNavigationRow(
            key: const Key('profile-did-row'),
            iconBoxKey: const Key('profile-did-icon-box'),
            iconTargetKey: const Key('profile-did-icon-target'),
            arrowKey: const Key('profile-did-arrow'),
            icon: CupertinoIcons.link,
            iconColor: AwikiMePalette.actionBlue,
            title: didTitle,
            arrowIcon: didExpanded
                ? CupertinoIcons.chevron_down
                : CupertinoIcons.chevron_right,
            isExpanded: didExpanded,
            onTap: onDidTap,
          ),
          if (didExpanded) _CompactProfileDidDetails(did: did),
          Container(
            key: const Key('profile-did-divider'),
            height: 1,
            color: theme.border,
          ),
          if (hasHomepage) ...<Widget>[
            _CompactProfileNavigationRow(
              key: const Key('profile-homepage-row'),
              iconBoxKey: const Key('profile-homepage-icon-box'),
              iconTargetKey: const Key('profile-homepage-icon-target'),
              arrowKey: const Key('profile-homepage-arrow'),
              icon: CupertinoIcons.globe,
              iconColor: AwikiMePalette.actionBlue,
              title: homepageTitle,
              arrowIcon: homepageExpanded
                  ? CupertinoIcons.chevron_down
                  : CupertinoIcons.chevron_right,
              isExpanded: homepageExpanded,
              onTap: onHomepageTap,
            ),
            if (homepageExpanded)
              _CompactProfileHomepageDetails(
                homepageUrl: homepageUrl,
                onOpenHomepage: onOpenHomepage,
              ),
            Container(
              key: const Key('profile-homepage-divider'),
              height: 1,
              color: theme.border,
            ),
          ],
          _CompactProfileNavigationRow(
            key: const Key('profile-settings-row'),
            iconBoxKey: const Key('profile-settings-icon-box'),
            iconTargetKey: const Key('profile-settings-icon-target'),
            arrowKey: const Key('profile-settings-arrow'),
            icon: CupertinoIcons.gear,
            iconColor: theme.secondaryText,
            title: settingsTitle,
            arrowIcon: CupertinoIcons.chevron_right,
            onTap: onSettingsTap,
          ),
        ],
      ),
    );
  }
}

class _CompactProfileDidDetails extends StatelessWidget {
  const _CompactProfileDidDetails({required this.did});

  final String did;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return ColoredBox(
      key: const Key('profile-did-details'),
      color: theme.subtleSurface,
      child: SizedBox(
        height: 84,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: CopyableDidLine(
            value: did,
            displayValue: did,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            copySemanticLabel: context.l10n.chatPeerInfoCopyDid,
            copiedMessage: context.l10n.chatPeerInfoDidCopied,
            textKey: const Key('profile-did-value'),
            buttonKey: const Key('profile-copy-did-button'),
            textStyle: TextStyle(
              color: theme.title,
              fontSize: 12,
              height: 16 / 12,
            ),
            gap: 4,
            buttonSize: 44,
            iconSize: 20,
            showButtonChrome: false,
          ),
        ),
      ),
    );
  }
}

class _CompactProfileHomepageDetails extends StatelessWidget {
  const _CompactProfileHomepageDetails({
    required this.homepageUrl,
    required this.onOpenHomepage,
  });

  final String homepageUrl;
  final VoidCallback onOpenHomepage;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return ColoredBox(
      key: const Key('profile-homepage-details'),
      color: theme.subtleSurface,
      child: SizedBox(
        height: 64,
        child: AppPressable(
          onTap: onOpenHomepage,
          semanticLabel: context.l10n.profileOpenHomepage,
          borderRadius: BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(36, 10, 16, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    homepageUrl,
                    key: const Key('profile-homepage-value'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.primary,
                      fontSize: 13,
                      height: 20 / 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox.square(
                  key: const Key('profile-homepage-action-target'),
                  dimension: 44,
                  child: Icon(
                    CupertinoIcons.arrow_up_right_square,
                    key: const Key('profile-homepage-action-icon'),
                    color: theme.primary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactProfileNavigationRow extends StatelessWidget {
  const _CompactProfileNavigationRow({
    super.key,
    required this.iconBoxKey,
    required this.iconTargetKey,
    required this.arrowKey,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.arrowIcon,
    required this.onTap,
    this.isExpanded,
  });

  final Key iconBoxKey;
  final Key iconTargetKey;
  final Key arrowKey;
  final IconData icon;
  final Color iconColor;
  final String title;
  final IconData arrowIcon;
  final VoidCallback onTap;
  final bool? isExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Semantics(
      expanded: isExpanded,
      child: ColoredBox(
        color: theme.surface,
        child: SizedBox(
          height: 52,
          child: AppPressable(
            onTap: onTap,
            semanticLabel: title,
            borderRadius: BorderRadius.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  SizedBox.square(
                    key: iconTargetKey,
                    dimension: 44,
                    child: Center(
                      child: Icon(
                        icon,
                        key: iconBoxKey,
                        size: 22,
                        color: iconColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.title,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    arrowIcon,
                    key: arrowKey,
                    size: 18,
                    color: theme.tertiaryText,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
    required this.onFollowingTap,
    required this.onFollowersTap,
  });

  final int followersCount;
  final int followingCount;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onFollowersTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Row(
      children: <Widget>[
        _ProfileStatAction(
          value: _formatCount(followingCount),
          label: context.l10n.profileFollowing,
          onTap: onFollowingTap,
        ),
        Container(
          width: 1,
          height: responsive.displayScaled(30),
          margin: EdgeInsets.symmetric(
            horizontal: responsive.displayScaled(28),
          ),
          color: context.awikiTheme.border,
        ),
        _ProfileStatAction(
          value: _formatCount(followersCount),
          label: context.l10n.profileFollowers,
          onTap: onFollowersTap,
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

class _ProfileStatAction extends StatelessWidget {
  const _ProfileStatAction({
    super.key,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: '$value $label',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: _ProfileStat(value: value, label: label),
        ),
      ),
    );
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

class _ProfileNavigationRow extends StatelessWidget {
  const _ProfileNavigationRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.neutral = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final iconColor = neutral ? theme.secondaryText : AwikiMePalette.actionBlue;
    final iconBackground = neutral
        ? theme.subtleSurface
        : AwikiMePalette.actionBlueSoft;
    return AppPressable(
      onTap: onTap,
      semanticLabel: title,
      borderRadius: BorderRadius.circular(responsive.radius(12)),
      child: Container(
        constraints: BoxConstraints(minHeight: responsive.displayScaled(82)),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.border)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: responsive.displayScaled(48),
              height: responsive.displayScaled(48),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(responsive.radius(13)),
              ),
              child: Icon(icon, size: responsive.iconMd, color: iconColor),
            ),
            SizedBox(width: responsive.displayScaled(18)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.title,
                      fontSize: responsive.bodyMd,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.trim().isNotEmpty) ...<Widget>[
                    SizedBox(height: responsive.spacing(4)),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.secondaryText,
                        fontSize: responsive.metaSm,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: responsive.spacing(12)),
            Icon(
              CupertinoIcons.chevron_right,
              size: responsive.iconSm,
              color: theme.tertiaryText,
            ),
          ],
        ),
      ),
    );
  }
}
