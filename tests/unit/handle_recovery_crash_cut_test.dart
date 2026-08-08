import 'package:awiki_me/src/presentation/recovery/handle_recovery_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Recovery crash cut is enabled only for an E2E build', () {
    expect(
      shouldStopHandleRecoveryBeforeProductReset(
        e2eEnabled: true,
        crashCutEnabled: true,
        releaseMode: false,
      ),
      isTrue,
    );
    expect(
      shouldStopHandleRecoveryBeforeProductReset(
        e2eEnabled: false,
        crashCutEnabled: true,
        releaseMode: false,
      ),
      isFalse,
    );
    expect(
      shouldStopHandleRecoveryBeforeProductReset(
        e2eEnabled: true,
        crashCutEnabled: false,
        releaseMode: false,
      ),
      isFalse,
    );
    expect(
      shouldStopHandleRecoveryBeforeProductReset(
        e2eEnabled: true,
        crashCutEnabled: true,
        releaseMode: true,
      ),
      isFalse,
    );
  });
}
