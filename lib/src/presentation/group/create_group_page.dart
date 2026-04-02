import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../../app/ui_feedback.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/widgets/app_widgets.dart';
import 'group_list_page.dart';
import 'group_provider.dart';

class CreateGroupPage extends ConsumerStatefulWidget {
  const CreateGroupPage({super.key});

  @override
  ConsumerState<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends ConsumerState<CreateGroupPage> {
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _goalController = TextEditingController();
  final _rulesController = TextEditingController();
  final _promptController = TextEditingController();
  String _groupMode = 'chat';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _descriptionController.dispose();
    _goalController.dispose();
    _rulesController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.groupNameRequired());
      return;
    }
    final slug = _slugController.text.trim().isEmpty
        ? 'slug_${DateTime.now().millisecondsSinceEpoch}'
        : _slugController.text.trim();
    setState(() => _isLoading = true);
    try {
      final group = await ref.read(groupProvider.notifier).createGroup(
            name: name,
            slug: slug,
            description: _descriptionController.text.trim(),
            goal: _goalController.text.trim(),
            rules: _rulesController.text.trim(),
            messagePrompt: _promptController.text.trim(),
            groupMode: _groupMode,
          );
      await ref.read(groupProvider.notifier).loadGroupMembers(group.groupId);
      if (!mounted) {
        return;
      }
      await AppNavigator.pushReplacement<void, void>(
        context,
        (_) => GroupDetailPage(initialGroup: group),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Stack(
      children: <Widget>[
        CupertinoPageScaffold(
          backgroundColor: theme.background,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: <Widget>[
                AwikiMeTopBar(
                  title: context.l10n.groupCreateTitle,
                  padding: EdgeInsets.zero,
                  trailingWidth: 48,
                  leading: TopBarActionButton(
                    onTap:
                        _isLoading ? null : () => Navigator.of(context).pop(),
                    child: const Icon(
                      Icons.arrow_back,
                      color: AwikiMeColors.primaryDark,
                      size: 22,
                    ),
                  ),
                  trailing: _isLoading
                      ? const CupertinoActivityIndicator()
                      : TopBarActionButton(
                          onTap: _create,
                          child: Text(
                            context.l10n.commonDone,
                            style: TextStyle(
                              color: theme.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                AppCardSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.l10n.groupModeTitle,
                        style: AwikiMeTextStyles.sectionTitle,
                      ),
                      const SizedBox(height: 12),
                      AppSurface(
                        color: theme.mutedSurface,
                        padding: const EdgeInsets.all(4),
                        radius: AwikiMeRadii.pill,
                        child: Row(
                          children: <Widget>[
                            _ModeButton(
                              active: _groupMode == 'chat',
                              label: context.l10n.groupModeChat,
                              onTap: () => setState(() => _groupMode = 'chat'),
                            ),
                            _ModeButton(
                              active: _groupMode == 'discovery',
                              label: context.l10n.groupModeDiscovery,
                              onTap: () =>
                                  setState(() => _groupMode = 'discovery'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildField(
                        context.l10n.groupFieldName,
                        _nameController,
                        context.l10n.groupFieldNamePlaceholder,
                      ),
                      _buildField(
                        context.l10n.groupFieldSlug,
                        _slugController,
                        context.l10n.groupFieldSlugPlaceholder,
                      ),
                      _buildField(
                        context.l10n.groupFieldDescription,
                        _descriptionController,
                        context.l10n.groupFieldDescriptionPlaceholder,
                      ),
                      _buildField(
                        context.l10n.groupFieldGoal,
                        _goalController,
                        context.l10n.groupFieldGoalPlaceholder,
                        multiline: true,
                      ),
                      _buildField(
                        context.l10n.groupFieldRules,
                        _rulesController,
                        context.l10n.groupFieldRulesPlaceholder,
                        multiline: true,
                      ),
                      _buildField(
                        context.l10n.groupFieldPrompt,
                        _promptController,
                        context.l10n.groupFieldPromptPlaceholder,
                        multiline: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isLoading) AwikiMeLoadingMask(label: context.l10n.groupCreating),
      ],
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    String placeholder, {
    bool multiline = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppTextField(
        controller: controller,
        label: label,
        placeholder: placeholder,
        multiline: multiline,
        enabled: !_isLoading,
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.active,
    required this.label,
    required this.onTap,
  });

  final bool active;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? theme.surface : CupertinoColors.transparent,
            borderRadius: BorderRadius.circular(AwikiMeRadii.pill),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: active ? theme.title : theme.primaryDark,
            ),
          ),
        ),
      ),
    );
  }
}
