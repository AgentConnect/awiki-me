part of 'acp_task_status.dart';

class AcpQuestionForm extends ConsumerStatefulWidget {
  const AcpQuestionForm({
    super.key,
    required this.session,
    required this.question,
    required this.canAnswer,
  });
  final AcpSession session;
  final Map<String, Object?> question;
  final bool canAnswer;
  @override
  ConsumerState<AcpQuestionForm> createState() => _AcpQuestionFormState();
}

class _AcpQuestionFormState extends ConsumerState<AcpQuestionForm>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final Map<String, Object?> _answers = {};
  final Map<String, TextEditingController> _controllers = {};
  Map<String, String> _errors = {};
  Timer? _expiry;
  bool _expired = false;
  AcpQuestionDraft _draft = const AcpQuestionDraft();
  AcpQuestionScope? _restoredScope;
  Object? _restoredEpoch;
  final _custom = TextEditingController();
  final _additional = TextEditingController();
  bool _customMode = false;
  bool _additionalExpanded = false;
  AcpQuestionScope get _scope =>
      acpQuestionScope(widget.session, widget.question);
  bool get _submitted => _draft.phase == AcpAnswerPhase.accepted;
  String? get _busyAction =>
      _draft.phase == AcpAnswerPhase.sending ? _draft.action : null;
  String? get _uncertainAction =>
      _draft.phase == AcpAnswerPhase.uncertain ? _draft.action : null;
  bool get _version2 =>
      widget.question['interaction_version'] == 2 &&
      widget.question['definition_hash'] is String;
  bool get _hasChoices => acpMap(
    _schema['properties'],
  ).values.any((p) => _questionOptions(acpMap(p)).isNotEmpty);
  bool get _canCustom =>
      _version2 &&
      widget.question['can_custom_answer'] == true &&
      (_hasChoices ||
          acpMap(_schema['properties']).length > 1 ||
          acpMap(
            _schema['properties'],
          ).values.any((p) => acpMap(p)['type'] != 'string'));
  bool get _canAdditional =>
      _version2 &&
      widget.question['can_additional_text'] == true &&
      _hasChoices;
  bool get _canCancel =>
      !_version2 || widget.question['can_cancel_question'] == true;

  void _persistDraft() =>
      ref.read(acpQuestionControllerProvider(_scope).notifier).edit({
        'answers': _answers,
        'field_texts': {
          for (final e in _controllers.entries) e.key: e.value.text,
        },
        'custom_text': _custom.text,
        'additional_text': _additional.text,
        'mode': _customMode ? 'custom' : 'structured',
        'additional_expanded': _additionalExpanded,
      });

  void _restoreDraft() {
    if (_draft.loading || _restoredScope == _scope) return;
    _restoredScope = _scope;
    final data = _draft.data;
    _answers
      ..clear()
      ..addAll(acpMap(data['answers']));
    for (final entry in acpMap(data['field_texts']).entries) {
      _controllers.putIfAbsent(entry.key, TextEditingController.new).text =
          entry.value?.toString() ?? '';
    }
    _custom.text = data['custom_text']?.toString() ?? '';
    _additional.text = data['additional_text']?.toString() ?? '';
    _customMode = _canCustom && data['mode'] == 'custom';
    _additionalExpanded = data['additional_expanded'] == true;
  }

  Map<String, Object?> get _request => acpMap(widget.question['request']);
  Map<String, Object?> get _schema => acpMap(_request['requestedSchema']);
  bool get _available =>
      !_draft.loading &&
      _draft.error != 'draft_load_failed' &&
      widget.canAnswer &&
      widget.question['response'] == null &&
      (widget.question['status'] == null ||
          widget.question['status'] == 'pending') &&
      !widget.session.stopping &&
      !_expired &&
      widget.session.active['run_id'] == widget.question['run_id'] &&
      widget.question['expires_at_ms'] is int &&
      (widget.question['expires_at_ms']! as int) >
          DateTime.now().millisecondsSinceEpoch;
  bool get _editing =>
      _available &&
      !_submitted &&
      _busyAction == null &&
      _uncertainAction == null;

  @override
  void initState() {
    super.initState();
    _armExpiry();
  }

  @override
  void didUpdateWidget(AcpQuestionForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.session.key != widget.session.key ||
        oldWidget.question['id'] != widget.question['id'] ||
        oldWidget.question['run_id'] != widget.question['run_id'] ||
        jsonEncode(oldWidget.question['request']) !=
            jsonEncode(widget.question['request']);
    if (changed) {
      _answers.clear();
      _errors.clear();
      _restoredScope = null;
      for (final controller in _controllers.values) {
        controller.dispose();
      }
      _controllers.clear();
    }
    if (changed ||
        oldWidget.question['expires_at_ms'] !=
            widget.question['expires_at_ms']) {
      _armExpiry();
    }
  }

  void _armExpiry() {
    _expiry?.cancel();
    final expires = widget.question['expires_at_ms'];
    final remaining = expires is int
        ? expires - DateTime.now().millisecondsSinceEpoch
        : 0;
    _expired = remaining <= 0;
    if (!_expired) {
      _expiry = Timer(Duration(milliseconds: remaining), () {
        if (mounted) setState(() => _expired = true);
      });
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _custom.dispose();
    _additional.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _beforeSend(String action) {
    if (!_available ||
        _submitted ||
        _busyAction != null ||
        (_uncertainAction != null && _uncertainAction != action)) {
      return false;
    }
    if (action != 'accept' || _uncertainAction == action) return true;
    final errors = <String, String>{};
    final required = _schema['required'] is List
        ? _schema['required']! as List
        : const [];
    if (!_customMode) {
      for (final field in acpMap(_schema['properties']).entries) {
        final error = _validateQuestionField(
          context,
          acpMap(field.value),
          _answers[field.key],
          required: required.contains(field.key),
        );
        if (error != null) errors[field.key] = error;
      }
    }
    final text = _customMode
        ? _custom.text
        : _canAdditional
        ? _additional.text
        : '';
    if (_customMode && text.trim().isEmpty) {
      errors['_text'] = acpText(context, '请输入你的回答。', 'Enter your answer.');
    }
    if (utf8.encode(text).length > 16384) {
      errors['_text'] = acpText(
        context,
        '文字过长，请缩短后提交（最多 16 KiB）。',
        'Text is too long. Shorten it to 16 KiB or less.',
      );
    }
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      final fieldContext = _fieldKeys[errors.keys.first]?.currentContext;
      if (fieldContext != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (fieldContext.mounted) {
            Scrollable.ensureVisible(fieldContext, alignment: 0.15);
          }
        });
      }
    }
    return errors.isEmpty;
  }

  final Map<String, GlobalKey> _fieldKeys = {};

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final epoch = ref.watch(sessionProvider.select((s) => s.activeEpoch));
    if (_restoredEpoch != epoch) {
      _restoredEpoch = epoch;
      _restoredScope = null;
      _answers.clear();
      for (final controller in _controllers.values) {
        controller.clear();
      }
      _custom.clear();
      _additional.clear();
    }
    _draft = ref.watch(acpQuestionControllerProvider(_scope));
    _restoreDraft();
    final theme = context.awikiTheme;
    final properties = acpMap(_schema['properties']);
    final required = _schema['required'] is List
        ? _schema['required']! as List
        : const [];
    final supported =
        (widget.question['interaction_version'] == null ||
            const {1, 2}.contains(widget.question['interaction_version'])) &&
        _schema['type'] == 'object' &&
        (_request['mode'] == null || _request['mode'] == 'form') &&
        properties.values.every((p) => _supportedQuestionField(acpMap(p)));
    final notice = _draft.loading
        ? acpText(context, '正在恢复回答草稿…', 'Restoring your draft…')
        : _draft.error == 'draft_load_failed'
        ? acpText(
            context,
            '无法读取回答草稿，请重试。',
            'Could not restore your answer. Please retry.',
          )
        : _submitted
        ? acpText(
            context,
            '回答已接收，等待智能体继续。',
            'Answer received. Waiting for the agent.',
          )
        : _expired || widget.session.stopping || !_available && widget.canAnswer
        ? acpText(
            context,
            '问题已失效，无法继续提交。',
            'This question is no longer available.',
          )
        : !widget.canAnswer
        ? acpText(context, '等待任务发起人回答。', 'Waiting for the task requester.')
        : !supported
        ? acpText(
            context,
            '暂不支持这种问题形式，可以跳过此问题。',
            'This question format is not supported. You can skip this question.',
          )
        : _uncertainAction != null
        ? acpText(
            context,
            '回答尚未确认。内容已保留，可重试同一操作。',
            'Response not confirmed. Your answer is kept; retry the same action.',
          )
        : _draft.error == 'answer_validation_failed'
        ? acpText(
            context,
            '回答不符合要求，内容已保留。请根据问题说明修改后重新提交。',
            'The answer does not meet the requirements. Your input is kept; check the question instructions, edit and submit again.',
          )
        : _draft.error != null
        ? acpText(
            context,
            '未能确认操作，内容已保留，请检查状态后重试。',
            'The action was not confirmed. Your answer is kept; check the state and retry.',
          )
        : null;
    return Container(
      key: ValueKey('acp-question:${widget.question['id']}'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.chat_bubble_text,
                size: 16,
                color: theme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  acpText(context, '需要你的回答', 'Your input is needed'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: theme.secondaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _request['message']?.toString() ??
                acpText(context, '请回答', 'Please answer'),
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: theme.title,
            ),
          ),
          if (_schema['description'] is String) ...[
            const SizedBox(height: 6),
            Text(
              _schema['description']! as String,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: theme.secondaryText,
              ),
            ),
          ],
          if (notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                notice,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: theme.secondaryText,
                ),
              ),
            ),
          if (_draft.error == 'draft_load_failed')
            CupertinoButton(
              onPressed: () => ref
                  .read(acpQuestionControllerProvider(_scope).notifier)
                  .reload(),
              child: Text(acpText(context, '重试', 'Retry')),
            ),
          if (supported && !_customMode)
            for (final field in properties.entries)
              Padding(
                key: _fieldKeys.putIfAbsent(field.key, GlobalKey.new),
                padding: const EdgeInsets.only(top: 18),
                child: _AcpQuestionField(
                  fieldId: field.key,
                  property: acpMap(field.value),
                  single: properties.length == 1,
                  required: required.contains(field.key),
                  enabled: _editing,
                  answer: _answers[field.key],
                  error: _errors[field.key],
                  controller: _controllers.putIfAbsent(
                    field.key,
                    TextEditingController.new,
                  ),
                  onChanged: (value) => setState(() {
                    if (value == null) {
                      _answers.remove(field.key);
                    } else {
                      _answers[field.key] = value;
                    }
                    _errors.remove(field.key);
                    _persistDraft();
                  }),
                ),
              ),
          if (supported && _customMode)
            _textAnswer(
              _custom,
              'acp-custom-answer',
              acpText(context, '你的回答', 'Your answer'),
              autofocus: true,
            ),
          if (supported && !_customMode && _canAdditional) ...[
            CupertinoButton(
              key: const Key('acp-additional-toggle'),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(vertical: 8),
              onPressed: _editing
                  ? () => setState(() {
                      _additionalExpanded = !_additionalExpanded;
                      _persistDraft();
                    })
                  : null,
              child: Text(
                acpText(
                  context,
                  _additionalExpanded ? '收起补充说明' : '＋ 补充说明（选填）',
                  _additionalExpanded
                      ? 'Hide additional details'
                      : '+ Additional details (optional)',
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (_additionalExpanded)
              _textAnswer(
                _additional,
                'acp-additional-text',
                acpText(context, '补充说明', 'Additional details'),
              ),
          ],
          if (_errors['_text'] != null)
            Text(
              _errors['_text']!,
              style: TextStyle(fontSize: 12, color: theme.danger),
            ),
          if (supported && _canCustom)
            CupertinoButton(
              key: const Key('acp-answer-mode'),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(vertical: 8),
              onPressed: _editing
                  ? () => setState(() {
                      _customMode = !_customMode;
                      _errors.clear();
                      _persistDraft();
                    })
                  : null,
              child: Text(
                acpText(
                  context,
                  _customMode ? '返回选项' : '不选这些，自己回答',
                  _customMode ? 'Back to fields' : 'Write my own answer',
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          if (supported && _hasChoices && !_canCustom)
            Text(
              acpText(
                context,
                '此问题仅支持所列选项。',
                'This question only accepts the listed choices.',
              ),
              style: TextStyle(fontSize: 12, color: theme.secondaryText),
            ),
          const SizedBox(height: 18),
          if (supported)
            _action(
              'accept',
              acpText(context, '提交回答', 'Submit answer'),
              primary: true,
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _action('decline', acpText(context, '跳过此问题', 'Skip question')),
              if (_canCancel)
                CupertinoButton(
                  key: const Key('acp-question-more'),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed:
                      _available &&
                          !_submitted &&
                          _busyAction == null &&
                          (_uncertainAction == null ||
                              _uncertainAction == 'cancel')
                      ? _showMore
                      : null,
                  child: Text(
                    acpText(context, '更多操作', 'More'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _textAnswer(
    TextEditingController controller,
    String key,
    String label, {
    bool autofocus = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: CupertinoTextField(
      key: Key(key),
      controller: controller,
      enabled: _editing,
      autofocus: autofocus,
      minLines: 3,
      maxLines: 8,
      textInputAction: TextInputAction.newline,
      placeholder: label,
      padding: const EdgeInsets.all(12),
      onChanged: (_) {
        setState(() => _errors.remove('_text'));
        _persistDraft();
      },
    ),
  );

  Future<void> _showMore() async {
    final epoch = ref.read(sessionProvider).activeEpoch;
    final cancel = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        message: Text(
          acpText(
            context,
            '取消本次询问，不会停止整个任务。',
            'Dismiss this question without stopping the task.',
          ),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, true),
            child: Text(acpText(context, '取消本次询问', 'Dismiss question')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context, false),
          child: Text(acpText(context, '返回', 'Back')),
        ),
      ),
    );
    if (cancel == true &&
        mounted &&
        ref.read(sessionProvider).activeEpoch == epoch) {
      await _send('cancel');
    }
  }

  Future<void> _send(String action) async {
    if (!_beforeSend(action)) return;
    final response = <String, Object?>{
      'action': action,
      if (_version2) 'answer_format': 'awiki.answer.v2',
      if (action == 'accept') ...{
        if (_version2) 'mode': _customMode ? 'custom' : 'structured',
        if (!_customMode) 'content': Map<String, Object?>.from(_answers),
        if (_customMode || _canAdditional && _additional.text.isNotEmpty)
          'text': _customMode ? _custom.text : _additional.text,
      },
    };
    await ref
        .read(acpQuestionControllerProvider(_scope).notifier)
        .submit(widget.session, widget.question, response);
  }

  Widget _action(String action, String label, {bool primary = false}) =>
      CupertinoButton(
        key: ValueKey('acp-answer:$action:${widget.question['id']}'),
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.symmetric(
          horizontal: primary ? 14 : 8,
          vertical: primary ? 10 : 6,
        ),
        color: primary ? context.awikiTheme.primary : null,
        borderRadius: BorderRadius.circular(10),
        onPressed:
            _available &&
                !_submitted &&
                _busyAction == null &&
                (_uncertainAction == null || _uncertainAction == action)
            ? () => _send(action)
            : null,
        child: _busyAction == action
            ? const CupertinoActivityIndicator()
            : Text(
                label,
                style: TextStyle(
                  fontSize: primary ? 14 : 12,
                  color: primary ? CupertinoColors.white : null,
                ),
              ),
      );
}
