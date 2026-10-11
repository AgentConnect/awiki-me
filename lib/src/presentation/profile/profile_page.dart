import 'avatar_edit_dialog.dart';
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
import '../shared/profile_avatar.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_semantic_icon.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/copyable_did_line.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/identity_profile_surface.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import '../shared/widgets/awiki_glass.dart';
import '../devices/devices_page.dart';
import '../devices/devices_provider.dart';
import 'profile_edit_page.dart';
import 'profile_provider.dart';

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
    final pendingDeviceRequests = ref.watch(
      devicesProvider.select(
        (state) =>
            state.currentDeviceCanManage ? state.visibleJoinRequests.length : 0,
      ),
    );
    final profileBody = SelectionArea(
      child: ListView(
        shrinkWrap: widget.shrinkWrap,
        padding: responsive.isCompact
            ? EdgeInsets.fromLTRB(
                16,
                widget.onBack == null ? 16 : 4,
                16,
                (widget.embedded ? widget.bottomInset : 24) +
                    AwikiFloatingTabBarInset.of(context),
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
                    SelectionContainer.disabled(
                      child: _CompactMeCard(
                        displayName: displayName,
                        handle: handleLabel,
                        bio: profile.bio,
                        avatarUri: profile.avatarUri,
                        userId: profile.did,
                        isSaving: state.isSaving,
                        onEdit: () => _showEditProfileDialog(context, profile),
                        onAvatarEdit: () => showAvatarEditor(context),
                        followersCount: friendsState.followers.length,
                        followingCount: friendsState.following.length,
                        onFollowingTap: widget.onFollowingTap,
                        onFollowersTap: widget.onFollowersTap,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SelectionContainer.disabled(
                      child: _CompactMeLinks(
                        homepageUrl: homepageUrl,
                        pendingDeviceRequests: pendingDeviceRequests,
                        onDevicesTap: () => AppNavigator.push<void>(
                          context,
                          (_) => const DevicesPage(),
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
                        avatarUserId: profile.did,
                        avatarKey: const Key('profile-avatar'),
                        onAvatarEdit: () => showAvatarEditor(context),
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
                          fontWeight: FontWeight.w400,
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
                        key: const Key('profile-homepage-metadata-row'),
                        label: context.l10n.profileHomepageLabel,
                        showDivider: false,
                        child: IdentityProfileLinkValue(
                          value: homepageUrl,
                          actionLabel: context.l10n.profileOpenHomepage,
                          onTap: () => _openHomepage(homepageUrl),
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
                            color: context.awikiTheme.title,
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
    // The root Me tab has no title bar: the profile card is the header.
    return AwikiGlassBackdrop(
      key: const Key('shell-tab-page-surface'),
      color: awikiCompactListBackground(context),
      child: Column(
        children: <Widget>[
          if (onBack != null)
            Padding(
              key: const Key('profile-compact-header'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: AwikiMeTopBar(
                title: title,
                padding: EdgeInsets.zero,
                titleFontSize: awikiMeCompactTopBarTitleFontSize,
                titleFontWeight: awikiMeCompactTopBarTitleFontWeight,
                titleHeight: awikiMeCompactTopBarTitleHeight,
                leading: AwikiBackButton(
                  key: const Key('profile-back-button'),
                  onTap: onBack,
                  semanticsLabel: context.l10n.commonBack,
                ),
              ),
            ),
          Expanded(child: child),
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
          top: 10,
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
            fontWeight: FontWeight.w400,
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

/// Phone Me tab identity card: avatar, name, handle and bio, with the
/// relationship counts kept as the card's footer.
class _CompactMeCard extends StatelessWidget {
  const _CompactMeCard({
    required this.displayName,
    required this.handle,
    required this.bio,
    required this.avatarUri,
    required this.userId,
    required this.isSaving,
    required this.onEdit,
    required this.onAvatarEdit,
    required this.followersCount,
    required this.followingCount,
    required this.onFollowingTap,
    required this.onFollowersTap,
  });

  final String displayName;
  final String handle;
  final String bio;
  final String? avatarUri;
  final String userId;
  final bool isSaving;
  final VoidCallback onEdit;

  /// Tapping the avatar itself opens the avatar editor; the rest of the
  /// card edits the profile.
  final VoidCallback onAvatarEdit;
  final int followersCount;
  final int followingCount;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onFollowersTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return AwikiGlassSurface(
      key: const Key('profile-compact-summary'),
      child: Column(
        children: <Widget>[
          AppPressable(
            key: const Key('profile-edit-button'),
            onTap: isSaving ? null : onEdit,
            semanticLabel: context.l10n.profileEditTitle,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 10, 20),
              child: Row(
                children: <Widget>[
                  ProfileAvatar(
                    key: const Key('profile-avatar'),
                    onEdit: onAvatarEdit,
                    seed: displayName,
                    size: 64,
                    avatarUri: avatarUri,
                    userId: userId,
                  ),
                  const SizedBox(width: 14),
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
                            fontWeight: FontWeight.w400,
                            height: 1.3,
                          ),
                        ),
                        if (handle.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            handle.startsWith('@') ? handle : '@$handle',
                            key: const Key('profile-handle-value'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.secondaryText,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (bio.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            bio.trim(),
                            key: const Key('profile-bio'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.secondaryText,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox.square(
                    dimension: 36,
                    child: Icon(
                      CupertinoIcons.chevron_right,
                      key: const Key('profile-edit-chevron'),
                      size: 18,
                      color: theme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            key: const Key('profile-statistics-top-divider'),
            height: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 18),
            color: theme.glassEdgeActive,
          ),
          SizedBox(
            height: 50,
            child: _CompactProfileStatistics(
              followersCount: followersCount,
              followingCount: followingCount,
              onFollowingTap: onFollowingTap,
              onFollowersTap: onFollowersTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactMeLinks extends StatelessWidget {
  const _CompactMeLinks({
    required this.homepageUrl,
    required this.pendingDeviceRequests,
    required this.onDevicesTap,
    required this.onOpenHomepage,
    required this.onSettingsTap,
  });

  final String homepageUrl;
  final int pendingDeviceRequests;
  final VoidCallback onDevicesTap;
  final VoidCallback onOpenHomepage;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AwikiGlassSurface(
      key: const Key('profile-navigation-group'),
      padding: const EdgeInsets.all(4),
      child: Column(
        children: <Widget>[
          _CompactMeLink(
            key: const Key('profile-devices-row'),
            icon: CupertinoIcons.device_laptop,
            title: l10n.devicesTitle,
            meta: pendingDeviceRequests > 0
                ? l10n.profileDevicePendingCount(pendingDeviceRequests)
                : null,
            onTap: onDevicesTap,
          ),
          if (homepageUrl.isNotEmpty)
            _CompactMeLink(
              key: const Key('profile-homepage-row'),
              icon: CupertinoIcons.globe,
              title: l10n.profileHomepageLabel,
              onTap: onOpenHomepage,
            ),
          _CompactMeLink(
            key: const Key('profile-settings-row'),
            icon: CupertinoIcons.gear,
            title: l10n.settingsTitle,
            onTap: onSettingsTap,
          ),
        ],
      ),
    );
  }
}

class _CompactMeLink extends StatelessWidget {
  const _CompactMeLink({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.meta,
  });

  final IconData icon;
  final String title;
  final String? meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return AppPressable(
      onTap: onTap,
      semanticLabel: title,
      borderRadius: BorderRadius.circular(18),
      builder: (context, state, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: state.pressed || state.hovered
              ? theme.glassLens
              : theme.glassLens.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: SizedBox(
          height: 52,
          child: Row(
            children: <Widget>[
              Icon(icon, size: 20, color: theme.title),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.title,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              if (meta != null) ...<Widget>[
                Text(
                  meta!,
                  style: TextStyle(color: theme.secondaryText, fontSize: 13),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: theme.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
