import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../app/e2e_semantics.dart';
import '../../app/ui_feedback.dart';
import '../../domain/entities/group_identity.dart';
import '../../domain/entities/group_summary.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../shared/app_dialog.dart';
import '../shared/awiki_me_design.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/awiki_desktop.dart';
import 'group_chat_navigation.dart';
import 'group_provider.dart';

Future<void> showCreateGroupDialog(BuildContext context, WidgetRef ref) async {
  final group = await AppNavigator.showDialog<GroupSummary>(
    context,
    (_) => const CreateGroupDialog(),
  );
  if (group == null || !context.mounted) {
    return;
  }
  await openGroupChat(context, ref, group);
}

class CreateGroupDialog extends ConsumerStatefulWidget {
  const CreateGroupDialog({super.key});

  @override
  ConsumerState<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends ConsumerState<CreateGroupDialog> {
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameFocusNode.addListener(_handleFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nameFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _nameFocusNode.removeListener(_handleFocusChanged);
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _create() async {
    if (_isLoading) {
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.groupNameRequired());
      _nameFocusNode.requestFocus();
      return;
    }
    setState(() => _isLoading = true);
    try {
      final group = await ref
          .read(groupProvider.notifier)
          .createGroup(
            name: name,
            slug: _generatedSlug(),
            description: '',
            goal: '',
            rules: '',
            messagePrompt: '',
            identity: const GroupIdentitySelection.didOnly(),
          );
      await ref.read(groupProvider.notifier).loadGroupMembers(group.groupId);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(group);
    } catch (error) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _generatedSlug() => 'slug_${DateTime.now().millisecondsSinceEpoch}';

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    // Reference `.dlg`: title, the name field and right-aligned actions.
    return AppDialogScaffold(
      maxWidth: 420,
      maxHeightFraction: 0.9,
      horizontalPadding: responsive.isPhone ? 14 : 16,
      verticalPadding: 24,
      avoidViewInsets: true,
      compactCentered: true,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            context.l10n.groupCreateTitle,
            style: TextStyle(
              color: theme.title,
              fontSize: 19,
              height: 1.25,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 14),
          _GroupNameInput(
            controller: _nameController,
            focusNode: _nameFocusNode,
            enabled: !_isLoading,
            label: context.l10n.groupFieldName,
            placeholder: context.l10n.groupFieldNamePlaceholder,
            onSubmitted: _create,
          ),
          const SizedBox(height: 16),
          AwikiDialogActionRow(
            cancelLabel: context.l10n.commonCancel,
            onCancel: _isLoading ? null : () => Navigator.of(context).pop(),
            primaryKey: const Key('create-group-submit-button'),
            primaryLabel: _isLoading
                ? context.l10n.groupCreating
                : context.l10n.groupCreateSubmit,
            primarySemanticsIdentifier: 'e2e-create-group-submit-button',
            onPrimary: _isLoading ? null : _create,
          ),
        ],
      ),
    );
  }
}

class _GroupNameInput extends StatelessWidget {
  const _GroupNameInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.label,
    required this.placeholder,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String label;
  final String placeholder;
  final FutureOr<void> Function() onSubmitted;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: theme.secondaryText,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? focusNode.requestFocus : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            height: responsive.isPhone ? 48 : 38,
            padding: EdgeInsets.symmetric(
              horizontal: responsive.isPhone ? 14 : 10,
            ),
            decoration: BoxDecoration(
              color: responsive.isPhone
                  ? (focusNode.hasFocus ? theme.glassLens : theme.glass)
                  : theme.surface,
              borderRadius: BorderRadius.circular(responsive.isPhone ? 16 : 6),
              border: Border.all(
                color: focusNode.hasFocus
                    ? theme.primary
                    : (responsive.isPhone ? theme.glassEdge : theme.border),
                width: responsive.isPhone && !focusNode.hasFocus ? 0.5 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  CupertinoIcons.person_3_fill,
                  color: theme.secondaryText,
                  size: responsive.iconSm,
                ),
                SizedBox(width: responsive.spacing(10)),
                Expanded(
                  child: e2eSemantics(
                    identifier: 'e2e-create-group-name-input',
                    label: label,
                    textField: true,
                    child: CupertinoTextField(
                      key: const Key('create-group-name-input'),
                      controller: controller,
                      focusNode: focusNode,
                      enabled: enabled,
                      maxLines: 1,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      inputFormatters: <TextInputFormatter>[
                        LengthLimitingTextInputFormatter(80),
                      ],
                      onSubmitted: (_) async {
                        if (enabled) {
                          await onSubmitted();
                        }
                      },
                      decoration: null,
                      padding: EdgeInsets.zero,
                      placeholder: placeholder,
                      style: TextStyle(
                        color: theme.title,
                        fontSize: responsive.bodyMd,
                        fontWeight: FontWeight.w400,
                      ),
                      placeholderStyle: TextStyle(
                        color: theme.secondaryText,
                        fontSize: responsive.bodyMd,
                        fontWeight: FontWeight.w400,
                      ),
                      cursorColor: theme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
