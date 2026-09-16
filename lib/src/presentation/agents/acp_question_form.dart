part of 'acp_task_status.dart';

class AcpQuestionForm extends StatefulWidget {
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
  State<AcpQuestionForm> createState() => _AcpQuestionFormState();
}

class _AcpQuestionFormState extends State<AcpQuestionForm>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final Map<String, Object?> _answers = {};
  final Map<String, TextEditingController> _controllers = {};
  Map<String, String> _errors = {};
  Timer? _expiry;
  bool _expired = false;
  bool _submitted = false;
  String? _busyAction;
  String? _uncertainAction;

  Map<String, Object?> get _request => acpMap(widget.question['request']);
  Map<String, Object?> get _schema => acpMap(_request['requestedSchema']);
  bool get _available =>
      widget.canAnswer &&
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
      _submitted = false;
      _busyAction = null;
      _uncertainAction = null;
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
    for (final field in acpMap(_schema['properties']).entries) {
      final error = _validateQuestionField(
        context,
        acpMap(field.value),
        _answers[field.key],
        required: required.contains(field.key),
      );
      if (error != null) errors[field.key] = error;
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
    final theme = context.awikiTheme;
    final properties = acpMap(_schema['properties']);
    final required = _schema['required'] is List
        ? _schema['required']! as List
        : const [];
    final supported =
        _schema['type'] == 'object' &&
        (_request['mode'] == null || _request['mode'] == 'form') &&
        properties.values.every((p) => _supportedQuestionField(acpMap(p)));
    final notice = _submitted
        ? acpText(
            context,
            '回答已发送，等待智能体继续。',
            'Response sent. Waiting for the agent.',
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
            '暂不支持这种问题形式，请拒绝回答或取消问题。',
            'This question format is not supported. Decline or cancel to continue.',
          )
        : _uncertainAction != null
        ? acpText(
            context,
            '回答尚未确认。内容已保留，可重试同一操作。',
            'Response not confirmed. Your answer is kept; retry the same action.',
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
          if (supported)
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
                  }),
                ),
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
              _action('decline', acpText(context, '拒绝回答', 'Decline')),
              _action('cancel', acpText(context, '取消问题', 'Cancel question')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(
    String action,
    String label, {
    bool primary = false,
  }) => AcpActionButton(
    key: ValueKey(
      '${widget.session.key}:${widget.question['run_id']}:${widget.question['id']}:$action',
    ),
    session: widget.session,
    action: 'answer',
    label: label,
    primary: primary,
    enabled:
        _available &&
        !_submitted &&
        (_busyAction == null || _busyAction == action) &&
        (_uncertainAction == null || _uncertainAction == action),
    values: {
      'run_id': widget.question['run_id'],
      'question_id': widget.question['id'],
      'response': {
        'action': action,
        if (action == 'accept') 'content': Map<String, Object?>.from(_answers),
      },
    },
    beforeSend: () => _beforeSend(action),
    onBusyChanged: (busy) {
      if (mounted) setState(() => _busyAction = busy ? action : null);
    },
    onUncertain: (uncertain) {
      if (mounted) setState(() => _uncertainAction = uncertain ? action : null);
    },
    onDone: () {
      if (mounted) setState(() => _submitted = true);
    },
  );
}
