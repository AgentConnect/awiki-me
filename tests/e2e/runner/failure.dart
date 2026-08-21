// [INPUT]: One stable, redacted runner failure message.
// [OUTPUT]: The shared typed exception used by E2E orchestration modules.
// [POS]: Dependency leaf for runner modules; contains no scenario behavior.

class E2eFailure implements Exception {
  E2eFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
