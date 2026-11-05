import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../../e2e/content_sync_read_budget.dart';

void main() {
  test('sequential UI and Core waits consume one original 90s budget', () {
    var now = DateTime.utc(2026, 11, 5);
    final budget = ContentSyncReadBudget(now: () => now);
    expect(budget.remaining(), const Duration(seconds: 90));
    now = now.add(const Duration(seconds: 60));
    expect(budget.remaining(), const Duration(seconds: 30));
    now = now.add(const Duration(seconds: 30));
    expect(budget.remaining, throwsA(isA<TimeoutException>()));
  });
  test('peer receives the same deadline without restarting the budget', () {
    final started = DateTime.utc(2026, 11, 5);
    final admin = ContentSyncReadBudget(now: () => started);
    final joiner = ContentSyncReadBudget(
      deadline: admin.deadline,
      now: () => started.add(const Duration(seconds: 15)),
    );
    expect(joiner.remaining(), const Duration(seconds: 75));
    expect(
      joiner.remaining(cap: const Duration(seconds: 30)),
      const Duration(seconds: 30),
    );
    expect(
      joiner.remaining(cap: const Duration(seconds: 90)),
      const Duration(seconds: 75),
    );
  });
}
