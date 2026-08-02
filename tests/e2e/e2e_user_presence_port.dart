// [INPUT]: A product request for explicit user-presence confirmation.
// [OUTPUT]: One deterministic, counted approval decision for unattended E2E.
// [POS]: Test-only UserPresencePort; production never imports this adapter.

import 'package:awiki_me/src/application/ports/user_presence_port.dart';

class E2eUserPresencePort implements UserPresencePort {
  int calls = 0;
  int completions = 0;
  bool lastResult = false;

  @override
  Future<bool> confirm({required String reason}) async {
    calls += 1;
    lastResult = true;
    completions += 1;
    return lastResult;
  }
}
