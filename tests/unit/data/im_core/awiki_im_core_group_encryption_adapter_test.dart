import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/data/im_core/awiki_im_core_group_encryption_adapter.dart';
import 'package:awiki_me/src/domain/entities/group_encryption_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const groupDid = 'did:wba:awiki.info:group:e1_group';

  test('maps Core group status to product-safe readiness only', () async {
    final adapter = AwikiImCoreGroupEncryptionAdapter.withCalls(
      status: (_) async =>
          _status(state: core.GroupSecureState.ready, canSendSecure: true),
      repair: (_) async => _repair(core.GroupSecureState.ready),
    );

    final status = await adapter.status('  $groupDid  ');

    expect(status.groupDid, groupDid);
    expect(status.readiness, GroupEncryptionReadiness.ready);
    expect(status.canSendSecure, isTrue);
    expect(status.retryable, isFalse);
  });

  test('maps synchronization and repair without exposing Core internals', () {
    final preparing = mapCoreGroupEncryptionStatus(
      _status(state: core.GroupSecureState.waitingForMembershipUpdate),
    );
    final needsRetry = mapCoreGroupEncryptionStatus(
      _status(
        state: core.GroupSecureState.needsRepair,
        problem: const core.SecureProblem(
          code: core.SecureProblemCode.groupStateUnavailable,
          message: 'must-not-enter-product-state',
          retryable: true,
        ),
      ),
    );

    expect(preparing.readiness, GroupEncryptionReadiness.preparing);
    expect(needsRetry.readiness, GroupEncryptionReadiness.needsRetry);
    expect(needsRetry.retryable, isTrue);
  });

  test('retry delegates repair then reloads authoritative status', () async {
    final calls = <String>[];
    final adapter = AwikiImCoreGroupEncryptionAdapter.withCalls(
      repair: (groupDid) async {
        calls.add('repair:$groupDid');
        return _repair(core.GroupSecureState.syncing);
      },
      status: (groupDid) async {
        calls.add('status:$groupDid');
        return _status(state: core.GroupSecureState.ready, canSendSecure: true);
      },
    );

    final result = await adapter.retry(groupDid);

    expect(calls, <String>['repair:$groupDid', 'status:$groupDid']);
    expect(result.readiness, GroupEncryptionReadiness.ready);
  });

  for (final state in <core.GroupSecureState>[
    core.GroupSecureState.ready,
    core.GroupSecureState.waitingForMembershipUpdate,
  ]) {
    test('stale repair reloads actual Core readiness ${state.name}', () async {
      final calls = <String>[];
      final adapter = AwikiImCoreGroupEncryptionAdapter.withCalls(
        repair: (_) async {
          calls.add('repair');
          throw const core.AwikiImCoreException(
            code: 'service_error',
            serviceCode: 'group.local_cursor_stale',
            message: 'synthetic local version fence',
          );
        },
        status: (_) async {
          calls.add('status');
          return _status(
            state: state,
            canSendSecure: state == core.GroupSecureState.ready,
          );
        },
      );
      final result = await adapter.retry(groupDid);
      expect(calls, <String>['repair', 'status']);
      expect(result.canSendSecure, state == core.GroupSecureState.ready);
      expect(
        result.readiness,
        state == core.GroupSecureState.ready
            ? GroupEncryptionReadiness.ready
            : GroupEncryptionReadiness.preparing,
      );
    });
  }
  for (final error in <core.AwikiImCoreException>[
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
      'repair rejection ${error.code}/${error.serviceCode} stays terminal',
      () async {
        var reads = 0;
        final adapter = AwikiImCoreGroupEncryptionAdapter.withCalls(
          repair: (_) async => throw error,
          status: (_) async {
            reads++;
            return _status(
              state: core.GroupSecureState.ready,
              canSendSecure: true,
            );
          },
        );
        await expectLater(adapter.retry(groupDid), throwsA(same(error)));
        expect(reads, 0);
      },
    );
  }

  test('empty Group DID fails before calling Core', () async {
    var called = false;
    final adapter = AwikiImCoreGroupEncryptionAdapter.withCalls(
      status: (_) async {
        called = true;
        return _status(state: core.GroupSecureState.ready);
      },
      repair: (_) async => _repair(core.GroupSecureState.ready),
    );

    await expectLater(adapter.status('  '), throwsFormatException);
    expect(called, isFalse);
  });

  test('mismatched Core group binding fails closed', () async {
    final adapter = AwikiImCoreGroupEncryptionAdapter.withCalls(
      status: (_) async => const core.GroupSecureStatus(
        group: 'did:wba:awiki.info:group:e1_other',
        state: core.GroupSecureState.ready,
        canSendSecure: true,
        localReadiness: core.GroupSecureLocalReadiness(
          hasLocalState: true,
          hasActiveMembership: true,
        ),
        pendingWork: core.GroupSecurePendingWork(
          pendingNotices: 0,
          pendingCommits: 0,
        ),
      ),
      repair: (_) async => _repair(core.GroupSecureState.ready),
    );

    await expectLater(adapter.status(groupDid), throwsStateError);
  });
}

core.GroupSecureStatus _status({
  required core.GroupSecureState state,
  bool canSendSecure = false,
  core.SecureProblem? problem,
}) => core.GroupSecureStatus(
  group: 'did:wba:awiki.info:group:e1_group',
  state: state,
  canSendSecure: canSendSecure,
  localReadiness: const core.GroupSecureLocalReadiness(
    hasLocalState: false,
    hasActiveMembership: false,
  ),
  pendingWork: const core.GroupSecurePendingWork(
    pendingNotices: 0,
    pendingCommits: 0,
  ),
  problem: problem,
);

core.GroupSecureRepairResult _repair(core.GroupSecureState state) =>
    core.GroupSecureRepairResult(
      group: 'did:wba:awiki.info:group:e1_group',
      state: state,
      repaired: true,
    );
