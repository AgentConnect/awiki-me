import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../e2e/delete_isolated_directory.dart';

class ClosingDirectory implements Directory {
  ClosingDirectory(this.failures, this.code);
  final int failures;
  final int code;
  int attempts = 0;
  bool recursiveSeen = false;
  @override
  Future<bool> exists() async => true;
  @override
  Future<Directory> delete({bool recursive = false}) async {
    attempts += 1;
    recursiveSeen = recursive;
    if (attempts <= failures) {
      throw FileSystemException(
        'test teardown',
        'isolated-fixture',
        OSError('test', code),
      );
    }
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final code in [39, 66]) {
    test('retries transient nonempty teardown $code', () async {
      final root = ClosingDirectory(2, code);
      await deleteIsolatedDirectory(root);
      expect(root.attempts, 3);
      expect(root.recursiveSeen, isTrue);
    });
  }
  test('permission errors stay visible immediately', () async {
    final root = ClosingDirectory(20, 13);
    await expectLater(
      deleteIsolatedDirectory(root),
      throwsA(isA<FileSystemException>()),
    );
    expect(root.attempts, 1);
  });
  test('persistent writer fails after a bounded retry', () async {
    final root = ClosingDirectory(20, 66);
    await expectLater(
      deleteIsolatedDirectory(root),
      throwsA(isA<FileSystemException>()),
    );
    expect(root.attempts, 10);
  });
}
