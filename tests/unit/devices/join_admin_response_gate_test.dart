import 'package:flutter_test/flutter_test.dart';

import '../../e2e/flutter/support/join_admin_response_gate.dart';
import 'device_test_support.dart';

void main() {
  test(
    'approval gate holds the successful delegate result until released',
    () async {
      final core = FakeDeviceManagementCore();
      final presence = FakeUserPresence();
      final gate = JoinAdminResponseGateService(
        core: core,
        userPresence: presence,
      );
      final progress = testJoinProgress();
      gate.holdNextApproval();
      var completed = false;
      final result = gate
          .approveAsMember(
            selector: progress.did,
            progress: progress,
            displayedSas: progress.sas!,
            sasConfirmed: true,
            presenceReason: 'test',
          )
          .then((value) {
            completed = true;
            return value;
          });
      await Future<void>.delayed(Duration.zero);
      expect(gate.approvalCaptured, isTrue);
      expect(completed, isFalse);
      expect(core.confirmCalls, 1);
      expect(presence.calls, 1);
      gate.releaseApproval();
      expect(
        (await result).authorizedDevice,
        core.confirmResult?.authorizedDevice,
      );
      expect(completed, isTrue);
      gate.releaseApproval();
    },
  );

  test(
    'gate delays one delegated response and releases it unchanged',
    () async {
      final core = FakeDeviceManagementCore();
      final response = testJoinProgress();
      core.verificationProgress = response;
      final gate = JoinAdminResponseGateService(
        core: core,
        userPresence: FakeUserPresence(),
      );
      gate.holdNextVerification();
      var completed = false;
      final first = gate
          .restoreAdminVerificationProgress(
            selector: response.did,
            joinSessionId: response.joinSessionId,
          )
          .then((value) {
            completed = true;
            return value;
          });
      await Future<void>.delayed(Duration.zero);
      expect(gate.verificationCaptured, isTrue);
      expect(completed, isFalse);
      expect(
        await gate.restoreAdminVerificationProgress(
          selector: response.did,
          joinSessionId: response.joinSessionId,
        ),
        same(response),
      );
      gate.releaseVerification();
      expect(await first, same(response));
      gate.releaseVerification();
    },
  );

  test('registry witness counts only successful real delegate reads', () async {
    final core = FakeDeviceManagementCore();
    final gate = JoinAdminResponseGateService(
      core: core,
      userPresence: FakeUserPresence(),
    );
    expect(await gate.loadRegistry(core.registry.did), same(core.registry));
    expect(gate.registryReadCount, 1);
    core.registryError = StateError('unavailable');
    await expectLater(gate.loadRegistry(core.registry.did), throwsStateError);
    expect(gate.registryReadCount, 1);
  });
}
