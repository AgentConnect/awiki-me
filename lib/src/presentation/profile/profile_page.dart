import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea, SelectionContainer;
import 'package:flutter_markdown/flutter_markdown.dart';
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
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/formatters/display_formatters.dart';
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
  });

  final Future<String?> Function(String url)? homepageMarkdownLoader;
  final bool embedded;
  final double bottomInset;

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
      return ProviderScope(overrides: overrides, child: const ProfilePage());
    }
    final state = ref.watch(profileProvider);
    final profile = state.profile;
    if (profile == null) {
      return const Center(child: CupertinoActivityIndicator());
    }
    _syncHomepage(profile);
    _syncRelationshipCounts();

    final title = DidDisplayFormatter.profileName(profile);
    final homepageUrl = ref
        .watch(profileHomepageResolverProvider)
        .homepageUrl(profile);
    final profileContent = ref
        .read(profileProvider.notifier)
        .visibleProfileContent();
    final responsive = context.awikiResponsive;
    final friendsState = ref.watch(friendsProvider);

    final content = AwikiMeShellTabPage(
      title: context.l10n.profileMeTitle,
      child: SelectionArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            responsive.tabContentHorizontalPadding,
            responsive.spacing(26),
            responsive.tabContentHorizontalPadding,
            widget.embedded ? widget.bottomInset : 120,
          ),
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AvatarBadge(seed: title, size: responsive.isPhone ? 54 : 44),
                SizedBox(width: responsive.spacing(16)),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: responsive.spacing(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: responsive.isPhone ? 20 : 18,
                                  fontWeight: FontWeight.w500,
                                  color: theme.title,
                                ),
                              ),
                            ),
                            SizedBox(width: responsive.spacing(8)),
                            SelectionContainer.disabled(
                              child: TopBarActionButton(
                                onTap: state.isSaving
                                    ? null
                                    : () => _showEditProfileDialog(
                                        context,
                                        profile,
                                      ),
                                child: Icon(
                                  CupertinoIcons.pencil,
                                  size: responsive.iconMd,
                                  color: theme.primaryDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: responsive.spacing(4)),
                        Text(
                          profile.did,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: responsive.bodyMd,
                            height: 1.35,
                            color: theme.tertiaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: responsive.spacing(28)),
            _ProfileRelationshipBar(
              homepageUrl: homepageUrl,
              followersCount: friendsState.followers.length,
              followingCount: friendsState.following.length,
              onHomepageTap: () async {
                await _openHomepage(homepageUrl);
              },
            ),
            SizedBox(height: responsive.spacing(48)),
            _ProfileContentSection(
              content: profileContent,
              emptyText: context.l10n.profileEmpty,
              tags: profile.tags,
            ),
          ],
        ),
      ),
    );
    if (widget.embedded) {
      return content;
    }
    if (responsive.supportsTwoPane) {
      return AwikiAdaptiveScaffold(maxWidth: 900, child: content);
    }
    return content;
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
    final nickController = TextEditingController(text: profile.nickName);
    final bioController = TextEditingController(text: profile.bio);
    final tagsController = TextEditingController(text: profile.tags.join(', '));

    await AppNavigator.showDialog<void>(
      context,
      (dialogContext) => CupertinoAlertDialog(
        title: Text(context.l10n.profileEditTitle),
        content: Column(
          children: <Widget>[
            const SizedBox(height: 12),
            AppTextField(
              controller: nickController,
              label: context.l10n.onboardingNickname,
              placeholder: context.l10n.onboardingNicknamePlaceholder,
            ),
            const SizedBox(height: 8),
            AppTextField(
              controller: bioController,
              label: context.l10n.profileEditTitle,
              placeholder: context.l10n.profileBioPlaceholder,
              multiline: true,
            ),
            const SizedBox(height: 8),
            AppTextField(
              controller: tagsController,
              label: context.l10n.profileTagsPlaceholder,
              placeholder: context.l10n.profileTagsPlaceholder,
            ),
          ],
        ),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              final patch = ProfilePatch(
                nickName: nickController.text.trim(),
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
            child: Text(context.l10n.commonSave),
          ),
        ],
      ),
    );
  }
}

class _ProfileRelationshipBar extends StatelessWidget {
  const _ProfileRelationshipBar({
    required this.homepageUrl,
    required this.followersCount,
    required this.followingCount,
    required this.onHomepageTap,
  });

  final String homepageUrl;
  final int followersCount;
  final int followingCount;
  final VoidCallback onHomepageTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackVertically = constraints.maxWidth < 360;
        final link = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: responsive.isPhone ? 320 : 260),
          child: _ProfileHomepageLink(
            homepageUrl: homepageUrl,
            onTap: onHomepageTap,
          ),
        );
        final stats = Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _ProfileStat(
              value: _formatCount(followersCount),
              label: context.l10n.profileFollowers,
            ),
            SizedBox(width: responsive.spacing(28)),
            _ProfileStat(
              value: _formatCount(followingCount),
              label: context.l10n.profileFollowing,
            ),
          ],
        );
        if (stackVertically) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              link,
              SizedBox(height: responsive.spacing(12)),
              stats,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(child: link),
            SizedBox(width: responsive.spacing(18)),
            stats,
          ],
        );
      },
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

class _ProfileHomepageLink extends StatelessWidget {
  const _ProfileHomepageLink({required this.homepageUrl, required this.onTap});

  final String homepageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Container(
      padding: responsive.scaledInsets(
        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      decoration: BoxDecoration(
        color: theme.subtleSurface,
        borderRadius: BorderRadius.circular(responsive.radius(12)),
      ),
      child: Row(
        children: <Widget>[
          SelectionContainer.disabled(
            child: Icon(
              CupertinoIcons.link,
              color: theme.primaryDark,
              size: responsive.iconSm,
            ),
          ),
          SizedBox(width: responsive.spacing(8)),
          Expanded(
            child: Text(
              homepageUrl,
              softWrap: true,
              style: AwikiMeTextStyles.listSubtitle.copyWith(
                fontSize: responsive.bodySm,
                color: theme.primaryDark,
              ),
            ),
          ),
          SizedBox(width: responsive.spacing(8)),
          SelectionContainer.disabled(
            child: AppIconButton(
              onPressed: onTap,
              semanticLabel: '打开主页',
              tooltip: '打开主页',
              size: responsive.compactControlHeight,
              backgroundColor: theme.surface.withValues(alpha: 0.72),
              borderColor: theme.border,
              borderRadius: BorderRadius.circular(responsive.radius(8)),
              child: Icon(
                CupertinoIcons.arrow_up_right_square,
                color: theme.primaryDark,
                size: responsive.iconSm,
              ),
            ),
          ),
        ],
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
    return Column(
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
        SizedBox(height: responsive.spacing(4)),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: responsive.metaSm,
            color: theme.primaryDark,
          ),
        ),
      ],
    );
  }
}

class _ProfileContentSection extends StatelessWidget {
  const _ProfileContentSection({
    required this.content,
    required this.emptyText,
    required this.tags,
  });

  final String content;
  final String emptyText;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final article = ProfileArticle.fromMarkdown(content);
    if (content.trim().isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(emptyText, style: AwikiMeTextStyles.cardSubtitle),
          _TagWrap(tags: tags),
        ],
      );
    }
    if (article == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MarkdownBody(data: content, styleSheet: _markdownStyleSheet(context)),
          _TagWrap(tags: tags),
        ],
      );
    }
    if (article.body.trim().isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(emptyText, style: AwikiMeTextStyles.cardSubtitle),
          _TagWrap(tags: tags),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (article.body.isNotEmpty) ...<Widget>[
          MarkdownBody(
            data: article.body,
            styleSheet: _markdownStyleSheet(context),
          ),
        ],
        _TagWrap(tags: tags),
      ],
    );
  }

  MarkdownStyleSheet _markdownStyleSheet(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final bodyStyle = TextStyle(
      fontSize: responsive.isPhone ? 16 : 13,
      height: 1.55,
      color: theme.body,
    );
    return MarkdownStyleSheet(
      p: bodyStyle,
      strong: bodyStyle.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _TagWrap extends StatelessWidget {
  const _TagWrap({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(top: context.awikiResponsive.spacing(20)),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tags.map((tag) => AppPill(label: tag)).toList(),
      ),
    );
  }
}
