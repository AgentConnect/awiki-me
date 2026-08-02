import 'package:flutter_test/flutter_test.dart';

import '../../e2e/e2e_user_presence_port.dart';

void main() {
  test('E2E user presence approves and counts each explicit request', () async {
    final presence = E2eUserPresencePort();

    expect(
      await presence.confirm(reason: 'Approve a test-only device Join'),
      isTrue,
    );
    expect(presence.calls, 1);
    expect(presence.completions, 1);
    expect(presence.lastResult, isTrue);
  });
}
