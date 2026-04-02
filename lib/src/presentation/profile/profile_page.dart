import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_router.dart';
import '../../app/ui_feedback.dart';
import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/user_profile.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../group/create_group_page.dart';
import '../group/group_list_page.dart';
import '../settings/settings_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/widgets/app_widgets.dart';
import 'profile_provider.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({
    super.key,
    this.homepageMarkdownLoader,
  });

  final Future<String?> Function(String url)? homepageMarkdownLoader;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  String? _loadedSignature;

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
        child: const ProfilePage(),
      );
    }
    final state = ref.watch(profileProvider);
    final profile = state.profile;
    if (profile == null) {
      return const Center(child: CupertinoActivityIndicator());
    }
    _syncHomepage(profile);

    final title = DidDisplayFormatter.profileName(profile);
    final homepageUrl = DidDisplayFormatter.homepageUrl(profile);
    final profileContent = _profileContent(profile);

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 120),
      children: <Widget>[
        AwikiMeTopBar(
          title: context.l10n.profileMeTitle,
          padding: EdgeInsets.zero,
          leading: TopBarActionButton(
            onTap: () =>
                AppNavigator.push(context, (_) => const SettingsPage()),
            child: Icon(
              Icons.settings_outlined,
              size: 24,
              color: theme.title,
            ),
          ),
          trailing: TopBarActionButton(
            onTap: () => _showQuickActions(context),
            child: Icon(
              Icons.add,
              size: 26,
              color: theme.title,
            ),
          ),
        ),
        const SizedBox(height: 16),
        AppCardSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AvatarBadge(seed: title, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: theme.title,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TopBarActionButton(
                              onTap: state.isSaving
                                  ? null
                                  : () =>
                                      _showEditProfileDialog(context, profile),
                              child: const Icon(
                                Icons.edit,
                                size: 18,
                                color: AwikiMeColors.title,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profile.did,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.tertiaryText,
                          ),
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
                  if (profile.handle?.isNotEmpty == true)
                    AppPill(label: '@${profile.handle}'),
                  if (profile.region?.isNotEmpty == true)
                    AppPill(label: profile.region!),
                ],
              ),
              const SizedBox(height: 16),
              AppInlineLinkRow(
                label: homepageUrl,
                icon: Icons.link,
                onTap: () async {
                  final url = Uri.parse(homepageUrl);
                  final launched = await launchUrl(
                    url,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!launched && context.mounted) {
                    ref
                        .read(uiFeedbackProvider.notifier)
                        .showError(AppMessage.linkOpenFailed());
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
                  children:
                      profile.tags.map((tag) => AppPill(label: tag)).toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _syncHomepage(UserProfile profile) {
    final signature =
        '${profile.did}|${profile.handle ?? ''}|${profile.nickName}|'
        '${profile.bio}|${profile.tags.join(',')}|${profile.profileMarkdown}';
    if (_loadedSignature == signature) {
      return;
    }
    _loadedSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(profileProvider.notifier).refreshWithHomepage(
            DidDisplayFormatter.homepageUrl(profile),
          );
    });
  }

  String _profileContent(UserProfile profile) {
    final markdown = profile.profileMarkdown.trim();
    if (markdown.isNotEmpty) {
      return markdown;
    }
    return profile.bio.trim();
  }

  Future<void> _showQuickActions(BuildContext context) async {
    await AppNavigator.showSheet<void>(
      context,
      (sheetContext) => AppDropMenu(
        title: context.l10n.quickActionsTitle.toUpperCase(),
        items: <AppDropMenuItem>[
          AppDropMenuItem(
            label: context.l10n.quickActionCreateGroup,
            onTap: () {
              AppNavigator.push(context, (_) => const CreateGroupPage());
            },
          ),
          AppDropMenuItem(
            label: context.l10n.quickActionJoinGroup,
            onTap: () {
              AppNavigator.push(context, (_) => const GroupListPage());
            },
          ),
        ],
      ),
    );
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
