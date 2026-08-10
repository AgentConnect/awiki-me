import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_identity_adapter.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dotless local alias falls back after identity id lookup', () {
    final selectors = identitySelectorCandidates('cgw-038');

    expect(selectors, hasLength(2));
    expect(selectors[0], isA<core.IdIdentitySelector>());
    expect((selectors[0] as core.IdIdentitySelector).id, 'cgw-038');
    expect(selectors[1], isA<core.LocalAliasIdentitySelector>());
    expect((selectors[1] as core.LocalAliasIdentitySelector).alias, 'cgw-038');
  });

  test('unambiguous selectors do not add a local alias fallback', () {
    expect(
      identitySelectorCandidates('default').single,
      isA<core.DefaultIdentitySelector>(),
    );
    expect(
      identitySelectorCandidates('did:wba:awiki.info:user:alice:e1_a').single,
      isA<core.DidIdentitySelector>(),
    );
    expect(
      identitySelectorCandidates('alice.awiki.info').single,
      isA<core.HandleIdentitySelector>(),
    );
  });

  test(
    'registration_recovery_join projects only the Core mode and reset reference',
    () {
      expect(
        existingHandleJoinModeFromCore(
          core.HandleRegistrationJoinMode.handleRecoveryRebind,
        ),
        ExistingHandleJoinMode.handleRecoveryRebind,
      );
      final projected = preparedRegistrationJoinProgressFromCore(
        _authorizedRegistrationJoin(
          reset: const core.HandleRecoveryRegistryEpochReset(
            accountUserId: 'account-alice',
            ownerIdentityId: 'owner-alice',
            handle: 'alice.awiki.info',
            previousDid: 'did:wba:awiki.info:user:alice:e1_previous',
            currentDid: 'did:wba:awiki.info:user:alice:e1_current',
            bindingGeneration: '8',
            sourceKind: core.HandleRecoveryTransitionSourceKind.joinedDevice,
            sourceId: 'join-registration-recovery',
          ),
        ),
        ExistingHandleJoinMode.handleRecoveryRebind,
      );

      expect(projected.cause, DeviceJoinCause.handleRecovery);
      expect(projected.handleRecovery?.handle, 'alice.awiki.info');
      expect(projected.joinSessionId, 'join-registration-recovery');
    },
  );

  test('registration_recovery_join fails closed on an ordinary-mode reset', () {
    expect(
      () => preparedRegistrationJoinProgressFromCore(
        _authorizedRegistrationJoin(
          reset: const core.HandleRecoveryRegistryEpochReset(
            accountUserId: 'account-alice',
            ownerIdentityId: 'owner-alice',
            handle: 'alice.awiki.info',
            previousDid: 'did:wba:awiki.info:user:alice:e1_previous',
            currentDid: 'did:wba:awiki.info:user:alice:e1_current',
            bindingGeneration: '8',
            sourceKind: core.HandleRecoveryTransitionSourceKind.joinedDevice,
            sourceId: 'join-registration-recovery',
          ),
        ),
        ExistingHandleJoinMode.ordinary,
      ),
      throwsA(isA<StateError>()),
    );
  });
}

core.AuthorizedJoinActivationProgress _authorizedRegistrationJoin({
  core.HandleRecoveryRegistryEpochReset? reset,
}) => core.AuthorizedJoinActivationProgress(
  join: const core.DeviceJoinProgress(
    session: core.DeviceJoinSessionSummary(
      joinSessionId: 'join-registration-recovery',
      did: 'did:wba:awiki.info:user:alice:e1_current',
      protocolDeviceId: 'device-registration-recovery',
      side: core.DeviceJoinSide.newDevice,
      phase: core.DeviceJoinPhase.pending,
      expiresAt: '2030-01-01T00:00:00Z',
    ),
    remoteState: core.DeviceJoinRemoteState.pending,
  ),
  registryEpochReset: reset,
);
