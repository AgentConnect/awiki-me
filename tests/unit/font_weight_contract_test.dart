import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application source does not introduce medium or bold font weights', () {
    final disallowed = RegExp(r'FontWeight\.(?:w[5-9]00|bold)');
    final violations = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => disallowed.hasMatch(file.readAsStringSync()))
        .map((file) => file.path)
        .toList(growable: false);

    expect(violations, isEmpty);
  });
}
