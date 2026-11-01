import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/group_inventory_retry.dart';

const stale = core.AwikiImCoreException(
  code: 'service_error',
  serviceCode: 'group.local_cursor_stale',
  message: 'synthetic inventory fence',
);

void main() {
  final start = DateTime.utc(2026, 11, 1);
  final deadline = start.add(const Duration(seconds: 45));

  test(
    'one stale inventory yields before repeating the same public operation',
    () async {
      var calls = 0;
      var yields = 0;
      final result = await retryStaleGroupInventory(
        () async {
          if (++calls == 1) throw stale;
          return 'ready';
        },
        deadline: deadline,
        now: () => start,
        yieldToReceive: () async {
          yields++;
        },
      );
      expect(result, 'ready');
      expect(calls, 2);
      expect(yields, 1);
    },
  );

  test('persistent stale inventory fails after three attempts', () async {
    var calls = 0;
    var yields = 0;
    await expectLater(
      retryStaleGroupInventory<String>(
        () async {
          calls++;
          throw stale;
        },
        deadline: deadline,
        now: () => start,
        yieldToReceive: () async {
          yields++;
        },
      ),
      throwsA(same(stale)),
    );
    expect(calls, 3);
    expect(yields, 2);
  });

  for (final error in [
    const core.AwikiImCoreException(
      code: 'permission_denied',
      message: 'synthetic',
    ),
    const core.AwikiImCoreException(
      code: 'service_error',
      serviceCode: 'group.local_cursor_invalid',
      message: 'synthetic',
    ),
  ]) {
    test(
      'non-stale error ${error.code}/${error.serviceCode} is never retried',
      () async {
        var calls = 0;
        await expectLater(
          retryStaleGroupInventory<String>(
            () async {
              calls++;
              throw error;
            },
            deadline: deadline,
            now: () => start,
            yieldToReceive: () async =>
                fail('non-stale errors cannot yield or retry'),
          ),
          throwsA(same(error)),
        );
        expect(calls, 1);
      },
    );
  }

  test(
    'yield reaching the original deadline does not start another attempt',
    () async {
      var current = start;
      var calls = 0;
      await expectLater(
        retryStaleGroupInventory<String>(
          () async {
            calls++;
            throw stale;
          },
          deadline: deadline,
          now: () => current,
          yieldToReceive: () async {
            current = deadline;
          },
        ),
        throwsA(same(stale)),
      );
      expect(calls, 1);
    },
  );
}
