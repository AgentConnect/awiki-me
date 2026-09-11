import 'package:flutter_test/flutter_test.dart';

import '../../e2e/runtime_message_sync_readiness.dart';

void main() {
  test('new Runtime at a committed tail is ready before its first prompt', () {
    expect(
      runtimeCoreBootstrapReady(
        bootstrapState: 'tail_bootstrapped',
        lastErrorCode: null,
      ),
      isTrue,
      reason:
          'Core exposes a successful tail bootstrap as idle; a new Runtime '
          'must be allowed to receive its first real prompt',
    );
  });

  test('an active Runtime remains ready after receiving messages', () {
    expect(
      runtimeCoreBootstrapReady(bootstrapState: 'active', lastErrorCode: null),
      isTrue,
    );
  });

  test(
    'missing, blocked, recovering and unknown bootstrap states stay unready',
    () {
      for (final state in <String?>[
        null,
        '',
        'uninitialized',
        'recovering',
        'blocked',
        'unknown',
        'active ',
      ]) {
        expect(
          runtimeCoreBootstrapReady(bootstrapState: state, lastErrorCode: null),
          isFalse,
          reason: 'state=$state',
        );
      }
    },
  );

  test('a bootstrap error prevents readiness for either completed state', () {
    for (final state in <String>['tail_bootstrapped', 'active']) {
      expect(
        runtimeCoreBootstrapReady(
          bootstrapState: state,
          lastErrorCode: 'anp.device_state_changed',
        ),
        isFalse,
      );
    }
  });

  test(
    'public readiness requires strict V2 completion without Legacy fallback',
    () {
      final probe = <String, Object?>{
        'v2_subprotocol_negotiated': true,
        'v2_bootstrap_completed': true,
        'last_reconcile_protocol': 'sync_v2',
        'legacy_sync_used': false,
      };
      expect(
        daemonPublicSyncV2Ready(<String, Object?>{'sync_probe': probe}),
        isTrue,
      );
      for (final field in probe.keys) {
        for (final invalid in <Object?>[
          null,
          'true',
          'legacy',
          !(probe[field] == true),
        ]) {
          final changed = <String, Object?>{...probe, field: invalid};
          expect(
            daemonPublicSyncV2Ready(<String, Object?>{'sync_probe': changed}),
            isFalse,
            reason: 'invalid public field $field',
          );
        }
      }
    },
  );

  test('missing or malformed public status cannot satisfy readiness', () {
    for (final status in <Object?>[
      null,
      'ready',
      <String, Object?>{},
      <String, Object?>{'sync_probe': null},
      <String, Object?>{'sync_probe': <Object?>[]},
    ]) {
      expect(daemonPublicSyncV2Ready(status), isFalse);
    }
  });
}
