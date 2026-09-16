part of 'acp_task_status.dart';

List<Map<String, Object?>> _questionOptions(Map<String, Object?> property) {
  final p = property['type'] == 'array' ? acpMap(property['items']) : property;
  final choices = acpMaps(p[property['type'] == 'array' ? 'anyOf' : 'oneOf']);
  if (choices.isNotEmpty) return choices;
  final values = p['enum'];
  final names = p['enumNames'];
  if (values is! List) return const [];
  return [
    for (var i = 0; i < values.length; i++)
      {
        'const': values[i],
        'title': names is List && i < names.length ? names[i] : values[i],
      },
  ];
}

bool _supportedQuestionField(Map<String, Object?> p) => switch (p['type']) {
  'string' || 'number' || 'integer' || 'boolean' => true,
  'array' => _questionOptions(p).isNotEmpty,
  _ => false,
};

String? _validateQuestionField(
  BuildContext context,
  Map<String, Object?> p,
  Object? value, {
  required bool required,
}) {
  String text(String zh, String en) => acpText(context, zh, en);
  if (value == null ||
      value is String && value.trim().isEmpty ||
      value is List && value.isEmpty) {
    if (required) return text('请回答此问题。', 'Please answer this question.');
    if (value == null) return null;
  }
  if (p['type'] == 'boolean' && value is! bool) {
    return text('请选择是或否。', 'Choose yes or no.');
  }
  if (p['type'] == 'number' || p['type'] == 'integer') {
    if (value is! num ||
        !value.isFinite ||
        p['type'] == 'integer' && value is! int) {
      return text(
        p['type'] == 'integer' ? '请输入整数。' : '请输入有效数字。',
        p['type'] == 'integer'
            ? 'Enter a whole number.'
            : 'Enter a valid number.',
      );
    }
    for (final bound in [
      'minimum',
      'maximum',
      'exclusiveMinimum',
      'exclusiveMaximum',
    ]) {
      final limit = p[bound];
      if (limit is! num) continue;
      final invalid = switch (bound) {
        'minimum' => value < limit,
        'maximum' => value > limit,
        'exclusiveMinimum' => value <= limit,
        _ => value >= limit,
      };
      if (invalid) {
        return switch (bound) {
          'minimum' => text(
            '请输入不小于 $limit 的数字。',
            'Enter a number of at least $limit.',
          ),
          'maximum' => text(
            '请输入不大于 $limit 的数字。',
            'Enter a number of at most $limit.',
          ),
          'exclusiveMinimum' => text(
            '请输入大于 $limit 的数字。',
            'Enter a number greater than $limit.',
          ),
          _ => text('请输入小于 $limit 的数字。', 'Enter a number less than $limit.'),
        };
      }
    }
  }
  if (value is String) {
    final min = p['minLength'];
    final max = p['maxLength'];
    if (min is int && value.runes.length < min) {
      return text('请至少输入 $min 个字符。', 'Enter at least $min characters.');
    }
    if (max is int && value.runes.length > max) {
      return text('请不要超过 $max 个字符。', 'Use no more than $max characters.');
    }
    if (p['pattern'] is String) {
      try {
        if (!RegExp(p['pattern']! as String).hasMatch(value)) {
          return text('输入不符合要求，请检查格式。', 'Check the required format.');
        }
      } on FormatException {
        /* The daemon validates patterns outside Dart's regex syntax. */
      }
    }
    final format = p['format'];
    final valid = switch (format) {
      'email' => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value),
      'uri' => Uri.tryParse(value)?.hasScheme == true,
      'date' =>
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
            DateTime.tryParse(value)?.toIso8601String().startsWith(value) ==
                true,
      'date-time' => value.contains('T') && DateTime.tryParse(value) != null,
      _ => true,
    };
    if (!valid) {
      return text(
        '请输入有效的${switch (format) {
          'email' => '邮箱地址',
          'uri' => '链接',
          'date' => '日期（YYYY-MM-DD）',
          _ => '日期和时间',
        }}。',
        switch (format) {
          'email' => 'Enter a valid email address.',
          'uri' => 'Enter a complete URL.',
          'date' => 'Enter a date as YYYY-MM-DD.',
          _ => 'Enter a valid date and time.',
        },
      );
    }
  }
  if (value is List) {
    final min = p['minItems'];
    final max = p['maxItems'];
    if (min is int && value.length < min) {
      return text('请至少选择 $min 项。', 'Select at least $min options.');
    }
    if (max is int && value.length > max) {
      return text('最多可选择 $max 项。', 'Select no more than $max options.');
    }
  }
  return null;
}

class _AcpQuestionField extends StatelessWidget {
  const _AcpQuestionField({
    required this.fieldId,
    required this.property,
    required this.single,
    required this.required,
    required this.enabled,
    required this.answer,
    required this.error,
    required this.controller,
    required this.onChanged,
  });
  final String fieldId;
  final Map<String, Object?> property;
  final bool single, required, enabled;
  final Object? answer;
  final String? error;
  final TextEditingController controller;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final type = property['type'];
    final options = type == 'boolean'
        ? <Map<String, Object?>>[
            {'const': true, 'title': acpText(context, '是', 'Yes')},
            {'const': false, 'title': acpText(context, '否', 'No')},
          ]
        : _questionOptions(property);
    final label =
        property['title']?.toString() ??
        (single
            ? options.isNotEmpty
                  ? acpText(
                      context,
                      type == 'array' ? '选择选项' : '选择一项',
                      type == 'array' ? 'Select options' : 'Choose one',
                    )
                  : acpText(context, '你的回答', 'Your answer')
            : fieldId.replaceAll('_', ' '));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: theme.title,
              ),
            ),
            Text(
              acpText(
                context,
                required ? '必填' : '选填',
                required ? 'Required' : 'Optional',
              ),
              style: TextStyle(fontSize: 12, color: theme.secondaryText),
            ),
          ],
        ),
        if (property['description'] is String)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              property['description']! as String,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: theme.secondaryText,
              ),
            ),
          ),
        if (type == 'array')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              acpText(
                context,
                '可多选${property['maxItems'] is int ? ' · 最多 ${property['maxItems']} 项' : ''}',
                'Choose multiple${property['maxItems'] is int ? ' · up to ${property['maxItems']}' : ''}',
              ),
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: theme.secondaryText,
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (options.isNotEmpty)
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == options.length - 1 ? 0 : 6),
              child: _option(context, options[i], i, multiple: type == 'array'),
            )
        else
          CupertinoTextField(
            key: ValueKey('acp-field:$fieldId'),
            controller: controller,
            enabled: enabled,
            minLines: type == 'string' && property['format'] == null ? 2 : 1,
            maxLines: type == 'string' && property['format'] == null ? 6 : 1,
            padding: const EdgeInsets.all(12),
            style: TextStyle(fontSize: 14, height: 1.5, color: theme.body),
            keyboardType: type == 'integer' || type == 'number'
                ? TextInputType.numberWithOptions(
                    signed: true,
                    decimal: type == 'number',
                  )
                : property['format'] == 'email'
                ? TextInputType.emailAddress
                : property['format'] == 'uri'
                ? TextInputType.url
                : TextInputType.multiline,
            textInputAction: type == 'string' && property['format'] == null
                ? TextInputAction.newline
                : TextInputAction.done,
            decoration: BoxDecoration(
              color: theme.subtleSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: error == null ? theme.border : theme.danger,
              ),
            ),
            onChanged: (text) => onChanged(
              text.isEmpty
                  ? null
                  : type == 'integer'
                  ? int.tryParse(text) ?? text
                  : type == 'number'
                  ? double.tryParse(text) ?? text
                  : text,
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: theme.danger,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _option(
    BuildContext context,
    Map<String, Object?> option,
    int index, {
    required bool multiple,
  }) {
    final theme = context.awikiTheme;
    final value = option['const'];
    final selected = multiple
        ? answer is List && (answer! as List).contains(value)
        : answer != null && answer == value;
    return Semantics(
      selected: selected,
      checked: selected,
      inMutuallyExclusiveGroup: !multiple,
      child: CupertinoButton(
        key: ValueKey('acp-option:$fieldId:$index'),
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: !enabled
            ? null
            : () {
                if (multiple) {
                  final values = List<Object?>.from(
                    answer is List ? answer! as List : const [],
                  );
                  if (!values.remove(value)) values.add(value);
                  onChanged(values);
                } else {
                  onChanged(value);
                }
              },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? theme.primary.withValues(alpha: 0.08)
                : theme.subtleSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? theme.primary.withValues(alpha: enabled ? 0.65 : 0.3)
                  : theme.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  multiple
                      ? (selected
                            ? CupertinoIcons.checkmark_square_fill
                            : CupertinoIcons.square)
                      : (selected
                            ? CupertinoIcons.check_mark_circled_solid
                            : CupertinoIcons.circle),
                  size: 19,
                  color: selected ? theme.primary : theme.secondaryText,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${option['title'] ?? value}',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: enabled ? theme.body : theme.secondaryText,
                      ),
                    ),
                    if (option['description'] is String) ...[
                      const SizedBox(height: 4),
                      Text(
                        option['description']! as String,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: theme.secondaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
