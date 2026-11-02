import 'dart:async';

/// Return the exact observation that satisfied readiness. Reading again after
/// awaiting this future can observe the next legitimate background sync.
Future<T> waitForE2eObservation<T>({
  required T Function() read,
  required bool Function(T) ready,
  required Future<void> Function() pump,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final observation = read();
    if (ready(observation)) return observation;
    if (!DateTime.now().isBefore(deadline)) {
      throw TimeoutException('E2E observation did not become ready.', timeout);
    }
    await pump();
  }
}
