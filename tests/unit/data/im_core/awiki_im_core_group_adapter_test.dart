import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/ports/group_core_port.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_group_adapter.dart';
import 'package:awiki_me/src/domain/entities/group_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'group adapter requests E2EE and one-object attachments behind gate',
    () {
      final request = mapCoreCreateGroupRequest(
        name: 'Secure group',
        slug: 'secure-group',
        description: '',
        goal: '',
        rules: '',
        messagePrompt: null,
        identity: const GroupIdentitySelection.didOnly(),
        secureRequired: true,
      );

      expect(request.messageSecurityProfile?.value, 'group-e2ee');
      expect(request.e2ee, isTrue);
      expect(request.attachmentsAllowed, isTrue);
    },
  );

  test('AWiki Me default group creation stays non-E2EE', () {
    final request = mapCoreCreateGroupRequest(
      name: 'Legacy group',
      slug: 'legacy-group',
      description: '',
      goal: '',
      rules: '',
      messagePrompt: null,
      identity: const GroupIdentitySelection.didOnly(),
      secureRequired: defaultGroupCreationE2eeRequired,
    );

    expect(request.messageSecurityProfile, isNull);
    expect(request.e2ee, isFalse);
    expect(request.attachmentsAllowed, isNull);
  });

  test('group adapter preserves Handle identity in typed join request', () {
    final request = mapCoreJoinGroupRequest(
      'did:example:group',
      GroupIdentitySelection.handle(' alice.example.com '),
    );

    expect(request.groupDid, 'did:example:group');
    expect(request.identityMode, core.GroupIdentityMode.handle);
    expect(request.identityHandle, 'alice.example.com');
  });

  test('group adapter emits explicit DID-only join without Handle', () {
    final request = mapCoreJoinGroupRequest(
      'did:example:group',
      const GroupIdentitySelection.didOnly(),
    );

    expect(request.identityMode, core.GroupIdentityMode.didOnly);
    expect(request.identityHandle, isNull);
  });

  test(
    'group adapter maps structured admission denial at the Core boundary',
    () {
      final mapped = mapCoreGroupMemberAdmissionError(
        const core.AwikiImCoreException(
          code: 'service_error',
          message: 'raw backend detail',
          serviceCode: 'group.admission_not_allowed',
          serviceDataJson:
              '{"admission_reason":"agent_not_group_invitable",'
              '"retryable":false}',
        ),
      );

      expect(mapped, isNotNull);
      expect(
        mapped?.reason,
        GroupMemberAdmissionDenialReason.agentNotGroupInvitable,
      );
    },
  );

  test(
    'group adapter keeps unrelated Core failures outside admission mapping',
    () {
      final mapped = mapCoreGroupMemberAdmissionError(
        const core.AwikiImCoreException(
          code: 'service_error',
          message: 'unrelated',
          serviceCode: 'group.not_found',
        ),
      );

      expect(mapped, isNull);
    },
  );
}
