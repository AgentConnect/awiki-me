import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'regular typography keeps only the reference mention semibold exception',
    () {
      final violations = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .expand(
            (file) => _fontWeightViolations(file.path, file.readAsStringSync()),
          )
          .toList(growable: false);

      expect(violations, isEmpty);
    },
  );

  test('mention exception cannot allow other weights or unrelated text', () {
    const mention = '''
TextStyle _mentionHighlightStyle() {
  return const TextStyle(fontWeight: FontWeight.w600);
}
''';
    expect(_fontWeightViolations(_mentionPath, mention), isEmpty);
    expect(
      _fontWeightViolations(_mentionPath.replaceAll('/', '\\'), mention),
      isEmpty,
    );
    expect(_fontWeightViolations('lib/other.dart', mention), isNotEmpty);
    expect(
      _fontWeightViolations(_mentionPath, mention.replaceAll('w600', 'w700')),
      isNotEmpty,
    );
    expect(
      _fontWeightViolations(
        _mentionPath,
        '$mention\nconst weight = FontWeight.w600;',
      ),
      isNotEmpty,
    );
    expect(
      _fontWeightViolations(
        _mentionPath,
        mention.replaceFirst(
          'return',
          'final extra = FontWeight.w600;\n  return',
        ),
      ),
      isNotEmpty,
    );
  });
}

const _mentionPath = 'lib/src/presentation/chat/parts/chat_message_part.dart';
final _strongWeight = RegExp(r'FontWeight\.(?:w[5-9]00|bold)');
final _mentionFunction = RegExp(
  r'^TextStyle _mentionHighlightStyle\([\s\S]*?^\}',
  multiLine: true,
);

List<String> _fontWeightViolations(String path, String source) {
  // The October reference design explicitly uses one semibold mention style.
  // Keep every other location under the regular-weight rule, including this file.
  final mention = path.replaceAll('\\', '/') == _mentionPath
      ? _mentionFunction.firstMatch(source)
      : null;
  final matches = _strongWeight.allMatches(source).toList();
  bool insideMention(RegExpMatch match) =>
      mention != null &&
      match.start >= mention.start &&
      match.end <= mention.end;
  final mentionCount = matches.where(insideMention).length;
  return [
    for (final match in matches)
      if (!(insideMention(match) &&
          mentionCount == 1 &&
          match.group(0) == 'FontWeight.w600'))
        '$path:${source.substring(0, match.start).split('\n').length}',
  ];
}
