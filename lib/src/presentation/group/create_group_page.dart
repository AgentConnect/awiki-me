import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

import '../app_shell/app_controller.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/awiki_me_top_bar.dart';
import 'group_list_page.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
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
      _showError('群名称不能为空');
      return;
    }
    final slug = _slugController.text.trim().isEmpty
        ? 'slug_${DateTime.now().millisecondsSinceEpoch}'
        : _slugController.text.trim();

    setState(() => _isLoading = true);
    try {
      final group = await widget.controller.createGroup(
        name: name,
        slug: slug,
        description: _descriptionController.text.trim(),
        goal: _goalController.text.trim(),
        rules: _rulesController.text.trim(),
        messagePrompt: _promptController.text.trim(),
        groupMode: _groupMode,
      );
      if (mounted && group != null) {
        await widget.controller.loadGroupMembers(group.groupId);
        if (!mounted) {
          return;
        }
        Navigator.of(context).pushReplacement(
          CupertinoPageRoute<void>(
            builder: (_) => GroupDetailPage(
              controller: widget.controller,
              initialGroup: group,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('错误'),
        content: Text(message),
        actions: <Widget>[
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        CupertinoPageScaffold(
          backgroundColor: AwikiMeColors.background,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: <Widget>[
                AwikiMeTopBar(
                  title: '创建群组',
                  padding: EdgeInsets.zero,
                  trailingWidth: 48,
                  leading: GestureDetector(
                    onTap: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: const Icon(
                      Icons.arrow_back,
                      color: AwikiMeColors.primaryDark,
                      size: 22,
                    ),
                  ),
                  trailing: _isLoading
                      ? const CupertinoActivityIndicator()
                      : GestureDetector(
                          onTap: _create,
                          child: const Text(
                            '完成',
                            style: TextStyle(
                              color: AwikiMeColors.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
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
                      const Text('群模式', style: AwikiMeTextStyles.sectionTitle),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: AwikiMeColors.mutedSurface,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: <Widget>[
                            _ModeButton(
                              active: _groupMode == 'chat',
                              label: 'Chat',
                              onTap: _isLoading
                                  ? () {}
                                  : () => setState(() => _groupMode = 'chat'),
                            ),
                            _ModeButton(
                              active: _groupMode == 'discovery',
                              label: 'Discovery',
                              onTap: _isLoading
                                  ? () {}
                                  : () => setState(() => _groupMode = 'discovery'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildField('名称', _nameController, '群组名称'),
                      _buildField('短链接', _slugController, '可选，不填则自动生成'),
                      _buildField('介绍', _descriptionController, '群资料介绍'),
                      _buildField('目标', _goalController, '建群目标', multiline: true),
                      _buildField('规则', _rulesController, '社群规则', multiline: true),
                      _buildField(
                        '提示',
                        _promptController,
                        '发声引导 Message Prompt',
                        multiline: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isLoading) const AwikiMeLoadingMask(label: '正在创建群组...'),
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
      child: Container(
        decoration: BoxDecoration(
          color: AwikiMeColors.background,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AwikiMeColors.secondaryText,
              ),
            ),
            const SizedBox(height: 6),
            CupertinoTextField(
              controller: controller,
              placeholder: placeholder,
              decoration: null,
              minLines: multiline ? 3 : 1,
              maxLines: multiline ? 5 : 1,
              textAlign: TextAlign.left,
              padding: const EdgeInsets.symmetric(vertical: 10),
              enabled: !_isLoading,
            ),
          ],
        ),
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
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AwikiMeColors.surface : CupertinoColors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: active ? AwikiMeColors.title : AwikiMeColors.primaryDark,
            ),
          ),
        ),
      ),
    );
  }
}
