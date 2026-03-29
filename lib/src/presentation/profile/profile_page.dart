import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/user_profile.dart';
import '../app_shell/app_controller.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_top_bar.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.controller,
    required this.onOpenSettings,
    required this.onOpenQuickActions,
    this.homepageMarkdownLoader,
  });

  final AppController controller;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenQuickActions;
  final Future<String?> Function(String url)? homepageMarkdownLoader;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  UserProfile? _resolvedProfile;
  String? _loadedSignature;

  @override
  void initState() {
    super.initState();
    _syncProfile();
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncProfile();
  }

  void _syncProfile() {
    final profile = widget.controller.profile;
    if (profile == null) {
      if (_resolvedProfile != null) {
        setState(() {
          _resolvedProfile = null;
          _loadedSignature = null;
        });
      }
      return;
    }

    final signature =
        '${profile.did}|${profile.handle ?? ''}|${profile.nickName}|'
        '${profile.bio}|${profile.tags.join(',')}|${profile.profileMarkdown}';
    if (_loadedSignature == signature) {
      return;
    }

    _loadedSignature = signature;
    _resolvedProfile = profile;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
    _loadHomepageMarkdown(profile, signature);
  }

  Future<void> _loadHomepageMarkdown(
    UserProfile profile,
    String signature,
  ) async {
    final homepageMarkdown = await _fetchHomepageMarkdown(_homepageUrl(profile));
    if (!mounted || _loadedSignature != signature) {
      return;
    }
    if (homepageMarkdown == null || homepageMarkdown.trim().isEmpty) {
      return;
    }
    setState(() {
      _resolvedProfile = profile.copyWith(profileMarkdown: homepageMarkdown);
    });
  }

  Future<String?> _fetchHomepageMarkdown(String url) async {
    final loader = widget.homepageMarkdownLoader;
    if (loader != null) {
      return loader(url);
    }
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        return null;
      }
      final body = response.body.trim();
      if (body.isEmpty) {
        return null;
      }
      return body;
    } catch (_) {
      return null;
    }
  }

  String _homepageUrl(UserProfile profile) {
    final handle = profile.handle?.trim();
    final username = handle != null && handle.isNotEmpty
        ? handle
        : (profile.nickName.trim().isNotEmpty
              ? profile.nickName.trim()
              : 'AWiki Me');
    return 'https://$username.awiki.ai';
  }

  @override
  Widget build(BuildContext context) {
    final profile = _resolvedProfile ?? widget.controller.profile;
    if (profile == null) {
      return const Center(child: CupertinoActivityIndicator());
    }

    final title = profile.nickName.trim().isNotEmpty
        ? profile.nickName.trim()
        : (profile.handle ?? 'AWiki Me');
    final homepageUrl = _homepageUrl(profile);
    final profileContent = _profileContent(profile);

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 120),
      children: <Widget>[
        AwikiMeTopBar(
          title: '我',
          padding: EdgeInsets.zero,
          leading: GestureDetector(
            onTap: widget.onOpenSettings,
            child: const Icon(
              Icons.settings_outlined,
              size: 24,
              color: AwikiMeColors.title,
            ),
          ),
          trailing: GestureDetector(
            onTap: widget.onOpenQuickActions,
            child: const Icon(
              Icons.add,
              size: 26,
              color: AwikiMeColors.title,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: AwikiMeDecorations.card(color: AwikiMeColors.surface),
          padding: const EdgeInsets.all(20),
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
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AwikiMeColors.title,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: widget.controller.isBusy
                                  ? null
                                  : () => _showEditProfileDialog(context, profile),
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
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF9A9AA1),
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
                    _ProfilePill(label: '@${profile.handle}'),
                  if (profile.region?.isNotEmpty == true)
                    _ProfilePill(label: profile.region!),
                ],
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final url = Uri.parse(homepageUrl);
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                },
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 284),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AwikiMeColors.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.link,
                        size: 18,
                        color: Color(0xFF5B3B00),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          homepageUrl,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF5B3B00),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _StatColumn(
              value: _formatMetric(widget.controller.followers.length),
              label: '粉丝',
            ),
            _StatColumn(
              value: _formatMetric(widget.controller.following.length),
              label: '关注',
            ),
            _StatColumn(
              value: _formatMetric(widget.controller.groups.length),
              label: '群组',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: AwikiMeDecorations.card(color: AwikiMeColors.surface),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (profileContent.isEmpty)
                const Text(
                  '暂无 profile',
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
                      profile.tags.map((tag) => _ProfilePill(label: tag)).toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showEditProfileDialog(
    BuildContext context,
    UserProfile profile,
  ) async {
    final nickNameController =
        TextEditingController(text: profile.nickName.trim());
    final bioController = TextEditingController(text: profile.bio.trim());
    final tagsController = TextEditingController(
      text: profile.tags.join(', '),
    );

    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('编辑个人资料'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: <Widget>[
              CupertinoTextField(
                controller: nickNameController,
                placeholder: '昵称',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: bioController,
                placeholder: '个人简介',
                minLines: 3,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: tagsController,
                placeholder: '标签，使用英文逗号分隔',
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              final nickName = nickNameController.text.trim();
              final bio = bioController.text.trim();
              final tags = tagsController.text
                  .split(',')
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .toList();
              final originalTags = profile.tags
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .toList();
              final unchanged = nickName == profile.nickName.trim() &&
                  bio == profile.bio.trim() &&
                  _listEquals(tags, originalTags);
              if (unchanged) {
                Navigator.of(dialogContext).pop();
                return;
              }
              Navigator.of(dialogContext).pop();
              await widget.controller.updateMyProfile(
                ProfilePatch(
                  nickName: nickName,
                  bio: bio,
                  tags: tags,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static String _formatMetric(int value) {
    if (value >= 1000) {
      final compact = value / 1000;
      return compact == compact.roundToDouble()
          ? '${compact.toStringAsFixed(0)}k'
          : '${compact.toStringAsFixed(1)}k';
    }
    return '$value';
  }

  String _profileContent(UserProfile profile) {
    final markdown = profile.profileMarkdown.trim();
    if (markdown.isNotEmpty) {
      return markdown;
    }
    return profile.bio.trim();
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AwikiMeColors.title,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6E645D),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfilePill extends StatelessWidget {
  const _ProfilePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AwikiMeColors.subtleSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AwikiMeColors.primaryDark,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
