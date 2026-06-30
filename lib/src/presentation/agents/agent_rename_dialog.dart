import 'package:flutter/cupertino.dart';

import '../../app/app_router.dart';
import '../../domain/entities/agent/agent_summary.dart';
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
      text: AgentDisplayName.title(widget.agent),
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
    final error = _validateAgentDisplayName(value);
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
    final errorText = _submittedError ?? _softValidateAgentDisplayName(value);
    final canSubmit = _validateAgentDisplayName(value) == null;
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
            title: '修改智能体名称',
            subtitle: '名称会显示在智能体列表、最近会话和对话窗口中。',
            onClose: () => Navigator.of(context).pop(),
          ),
          SizedBox(height: responsive.spacing(16)),
          Text(
            '名称',
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
            placeholder: '显示名称',
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
                    '最多 $agentDisplayNameMaxLength 个字符。',
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
                  label: '取消',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              SizedBox(width: responsive.spacing(10)),
              Expanded(
                child: AppPrimaryButton(
                  label: '保存',
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

String? _validateAgentDisplayName(String value) {
  if (value.trim().isEmpty) {
    return '请输入智能体名称';
  }
  if (value.trim().length > agentDisplayNameMaxLength) {
    return '名称最多 $agentDisplayNameMaxLength 个字符';
  }
  return null;
}

String? _softValidateAgentDisplayName(String value) {
  if (value.length > agentDisplayNameMaxLength) {
    return '名称最多 $agentDisplayNameMaxLength 个字符';
  }
  return null;
}
