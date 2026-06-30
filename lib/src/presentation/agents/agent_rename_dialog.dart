import 'package:flutter/cupertino.dart';

import '../../app/app_router.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../l10n/l10n.dart';
import '../shared/app_dialog.dart';
import '../shared/awiki_me_design.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'agent_display_name.dart';

const int agentDisplayNameMaxLength = 40;

Future<String?> showAgentRenameDialog(
  BuildContext context,
  AgentSummary agent,
) {
  return AppNavigator.showDialog<String>(
    context,
    (_) => AgentRenameDialog(agent: agent),
  );
}

class AgentRenameDialog extends StatefulWidget {
  const AgentRenameDialog({super.key, required this.agent});

  final AgentSummary agent;

  @override
  State<AgentRenameDialog> createState() => _AgentRenameDialogState();
}

class _AgentRenameDialogState extends State<AgentRenameDialog> {
  late final TextEditingController _controller;
  String? _submittedError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: AgentDisplayName.isUserVisibleName(widget.agent.displayName)
          ? widget.agent.displayName.trim()
          : '',
    )..addListener(_handleChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    super.dispose();
  }

  void _handleChanged() {
    if (_submittedError != null) {
      setState(() => _submittedError = null);
      return;
    }
    setState(() {});
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = _validateAgentDisplayName(context, value);
    if (error != null) {
      setState(() => _submittedError = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final value = _controller.text.trim();
    final errorText =
        _submittedError ?? _softValidateAgentDisplayName(context, value);
    final canSubmit = _validateAgentDisplayName(context, value) == null;
    final fieldBorderColor = errorText == null
        ? const Color(0xFFE4E9F2)
        : const Color(0xFFD84A4A);
    return AppDialogScaffold(
      maxWidth: 420,
      maxHeightFraction: 0.9,
      horizontalPadding: responsive.spacing(18),
      verticalPadding: responsive.spacing(22),
      avoidViewInsets: true,
      padding: EdgeInsets.all(responsive.spacing(18)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppDialogHeader(
            title: context.l10n.agentRenameTitle,
            subtitle: context.l10n.agentRenameSubtitle,
            onClose: () => Navigator.of(context).pop(),
          ),
          SizedBox(height: responsive.spacing(16)),
          Text(
            context.l10n.agentNameField,
            style: TextStyle(
              color: theme.secondaryText,
              fontSize: responsive.metaSm,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: responsive.spacing(6)),
          CupertinoTextField(
            key: const Key('agent-rename-field'),
            controller: _controller,
            autofocus: true,
            maxLength: agentDisplayNameMaxLength,
            placeholder: context.l10n.agentNamePlaceholder,
            textInputAction: TextInputAction.done,
            clearButtonMode: OverlayVisibilityMode.editing,
            onSubmitted: (_) => _submit(),
            padding: EdgeInsets.symmetric(
              horizontal: responsive.spacing(12),
              vertical: responsive.spacing(11),
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFD),
              borderRadius: BorderRadius.circular(responsive.radius(9)),
              border: Border.all(color: fieldBorderColor),
            ),
            style: AwikiMeTextStyles.inputText.copyWith(
              color: theme.title,
              fontSize: responsive.bodyMd,
            ),
            placeholderStyle: AwikiMeTextStyles.inputText.copyWith(
              color: theme.secondaryText,
              fontSize: responsive.bodyMd,
            ),
          ),
          SizedBox(height: responsive.spacing(6)),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            child: errorText == null
                ? Text(
                    context.l10n.agentNameHelp(agentDisplayNameMaxLength),
                    key: const ValueKey<String>('agent-rename-help'),
                    style: TextStyle(
                      color: theme.secondaryText,
                      fontSize: responsive.metaSm,
                      height: 1.3,
                    ),
                  )
                : Text(
                    errorText,
                    key: const ValueKey<String>('agent-rename-error'),
                    style: TextStyle(
                      color: const Color(0xFFD84A4A),
                      fontSize: responsive.metaSm,
                      height: 1.3,
                    ),
                  ),
          ),
          SizedBox(height: responsive.spacing(18)),
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
                  onPressed: canSubmit ? _submit : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String? _validateAgentDisplayName(BuildContext context, String value) {
  if (value.trim().isEmpty) {
    return context.l10n.agentNameRequired;
  }
  if (value.trim().length > agentDisplayNameMaxLength) {
    return context.l10n.agentNameTooLong(agentDisplayNameMaxLength);
  }
  return null;
}

String? _softValidateAgentDisplayName(BuildContext context, String value) {
  if (value.length > agentDisplayNameMaxLength) {
    return context.l10n.agentNameTooLong(agentDisplayNameMaxLength);
  }
  return null;
}
