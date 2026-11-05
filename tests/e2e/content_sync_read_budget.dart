// One content-read phase shares its original 90s budget across both App roles.
import 'dart:async';

class ContentSyncReadBudget {
  ContentSyncReadBudget({DateTime? deadline, DateTime Function()? now})
    : _now = now ?? DateTime.now {
    this.deadline = deadline ?? _now().add(const Duration(seconds: 90));
  }

  final DateTime Function() _now;
  late final DateTime deadline;

  Duration remaining({Duration? cap}) {
    final left = deadline.difference(_now());
    if (left <= Duration.zero) {
      throw TimeoutException('The content-read total budget expired.');
    }
    return cap != null && cap < left ? cap : left;
  }
}
