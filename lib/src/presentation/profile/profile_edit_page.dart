import 'package:flutter/cupertino.dart';

import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/user_profile.dart';
import '../../l10n/l10n.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({
    super.key,
    required this.profile,
    required this.onSave,
    this.onChangeAvatar,
  });

  final UserProfile profile;
  final Future<void> Function(ProfilePatch patch) onSave;
  final VoidCallback? onChangeAvatar;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _bioController;
  late final TextEditingController _tagsController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text: widget.profile.displayName,
    )..addListener(_refreshSaveState);
    _bioController = TextEditingController(text: widget.profile.bio);
    _tagsController = TextEditingController(
      text: widget.profile.tags.join(', '),
    );
  }

  @override
  void dispose() {
    _nicknameController
      ..removeListener(_refreshSaveState)
      ..dispose();
    _bioController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _refreshSaveState() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _save() async {
    if (_saving || _nicknameController.text.trim().isEmpty) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(
        ProfilePatch(
          displayName: _nicknameController.text.trim(),
          bio: _bioController.text.trim(),
          tags: _tagsController.text
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .take(5)
              .toList(),
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final canSave = !_saving && _nicknameController.text.trim().isNotEmpty;

    return CupertinoPageScaffold(
      key: const Key('profile-edit-page'),
      backgroundColor: theme.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.surface,
                border: Border(
                  bottom: BorderSide(color: theme.border, width: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: AwikiMeTopBar(
                  title: l10n.profileEditTitle,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  titleFontSize: awikiMeCompactTopBarTitleFontSize,
                  titleFontWeight: awikiMeCompactTopBarTitleFontWeight,
                  titleHeight: awikiMeCompactTopBarTitleHeight,
                  leading: TopBarActionButton(
                    key: const Key('profile-edit-back-button'),
                    onTap: () => Navigator.of(context).pop(),
                    semanticsLabel: l10n.commonBack,
                    child: Icon(
                      CupertinoIcons.chevron_left,
                      size: responsive.iconMd,
                      color: AwikiMePalette.actionBlue,
                    ),
                  ),
                  trailingWidth: 56,
                  trailing: CupertinoButton(
                    key: const Key('profile-edit-save-button'),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(56, 44),
                    onPressed: canSave ? _save : null,
                    child: _saving
                        ? const CupertinoActivityIndicator(radius: 9)
                        : Text(
                            l10n.commonSave,
                            style: TextStyle(
                              color: canSave
                                  ? AwikiMePalette.actionBlue
                                  : theme.tertiaryText,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.zero,
                children: <Widget>[
                  _AvatarEditRow(
                    profile: widget.profile,
                    onChangeAvatar: widget.onChangeAvatar,
                  ),
                  const _ProfileEditDivider(inset: 0),
                  _CompactFieldRow(
                    key: const Key('profile-edit-nickname-row'),
                    label: l10n.onboardingNickname,
                    controller: _nicknameController,
                    textInputAction: TextInputAction.next,
                  ),
                  const _ProfileEditDivider(),
                  _CompactFieldRow(
                    key: const Key('profile-edit-bio-row'),
                    label: l10n.profileBioPlaceholder,
                    placeholder: l10n.profileBioHint,
                    controller: _bioController,
                    minHeight: 200,
                    maxLines: 4,
                    maxLength: 100,
                    showCounter: true,
                    textInputAction: TextInputAction.newline,
                  ),
                  const _ProfileEditDivider(),
                  _CompactFieldRow(
                    key: const Key('profile-edit-tags-row'),
                    label: l10n.profileTagsLabel,
                    controller: _tagsController,
                    minHeight: 150,
                    maxLines: 2,
                    helper: l10n.profileTagsLimit,
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarEditRow extends StatelessWidget {
  const _AvatarEditRow({required this.profile, this.onChangeAvatar});

  final UserProfile profile;
  final VoidCallback? onChangeAvatar;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final l10n = context.l10n;
    return ColoredBox(
      color: theme.surface,
      child: SizedBox(
        height: 152,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 72,
                child: Text(
                  l10n.profileAvatarLabel,
                  style: TextStyle(
                    color: theme.title,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: AvatarBadge(
                    seed: profile.displayName,
                    avatarUri: profile.avatarUri,
                    size: 88,
                  ),
                ),
              ),
              SizedBox(
                width: 72,
                child: CupertinoButton(
                  key: const Key('profile-edit-change-avatar-button'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(72, 48),
                  onPressed: onChangeAvatar,
                  child: Text(
                    l10n.profileAvatarChange,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: onChangeAvatar == null
                          ? theme.tertiaryText
                          : AwikiMePalette.actionBlue,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactFieldRow extends StatelessWidget {
  const _CompactFieldRow({
    super.key,
    required this.label,
    required this.controller,
    required this.textInputAction,
    this.placeholder,
    this.helper,
    this.minHeight = 96,
    this.maxLines = 1,
    this.maxLength,
    this.showCounter = false,
  });

  final String label;
  final String? placeholder;
  final String? helper;
  final TextEditingController controller;
  final TextInputAction textInputAction;
  final double minHeight;
  final int maxLines;
  final int? maxLength;
  final bool showCounter;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return ColoredBox(
      color: theme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  color: theme.title,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Stack(
                children: <Widget>[
                  CupertinoTextField(
                    key: ValueKey<String>('profile-edit-field-$label'),
                    controller: controller,
                    placeholder: placeholder,
                    maxLines: maxLines,
                    maxLength: maxLength,
                    textInputAction: textInputAction,
                    padding: EdgeInsets.only(
                      right: showCounter ? 52 : 0,
                      bottom: showCounter ? 22 : 0,
                    ),
                    decoration: null,
                    style: TextStyle(
                      color: theme.title,
                      fontSize: 16,
                      height: 1.5,
                    ),
                    placeholderStyle: TextStyle(
                      color: theme.tertiaryText,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  if (showCounter)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, _) => Text(
                          '${value.text.characters.length}/${maxLength ?? 0}',
                          key: const Key('profile-edit-bio-counter'),
                          style: TextStyle(
                            color: theme.tertiaryText,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (helper != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  helper!,
                  style: TextStyle(
                    color: theme.tertiaryText,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileEditDivider extends StatelessWidget {
  const _ProfileEditDivider({this.inset = 24});

  final double inset;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.awikiTheme.surface,
      child: Padding(
        padding: EdgeInsets.only(left: inset, right: inset),
        child: ColoredBox(
          color: context.awikiTheme.border,
          child: const SizedBox(height: 1, width: double.infinity),
        ),
      ),
    );
  }
}
