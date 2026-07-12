import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/data/im_core/awiki_im_core_group_adapter.dart';
import 'package:awiki_me/src/domain/entities/group_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
