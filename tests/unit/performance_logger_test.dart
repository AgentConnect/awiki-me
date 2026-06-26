import 'package:awiki_me/src/core/performance_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('performance logging is disabled by default', () {
    expect(AwikiPerformanceLogger.enabled, isFalse);
  });

  test('safeHash is stable and does not expose source text', () {
    const source = 'did:example:alice-secret';
    final first = AwikiPerformanceLogger.safeHash(source);
    final second = AwikiPerformanceLogger.safeHash(source);

    expect(first, second);
    expect(first, hasLength(12));
    expect(first, isNot(source));
    expect(first, isNot(contains('alice')));
  });

  test('threadField exposes only hashed thread id', () {
    final fields = AwikiPerformanceLogger.threadField('thread-secret');

    expect(fields.keys, contains('thread_hash'));
    expect(fields.values.single, isNot('thread-secret'));
  });
}
