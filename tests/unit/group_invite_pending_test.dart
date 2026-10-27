import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/group/group_member_invite_dialog.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_feedback.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

const _group = 'did:wba:awiki.info:groups:invite-pending';
const _owner = 'did:wba:awiki.info:user:owner:e1_key';
const _peer = 'did:wba:awiki.info:user:peer:e1_key';

class _PendingGateway extends FakeAwikiGateway {
  @override
  Future<GroupSummary> addGroupMember({
    required String groupId,
    required String memberRef,
    String role = 'member',
  }) async {
    final added = await super.addGroupMember(
      groupId: groupId,
      memberRef: memberRef,
      role: role,
    );
    return added.withSecurity(
      encrypted: true,
      canSendSecure: false,
      secureState: 'syncing',
      operation: const GroupOperationSummary(
        businessCommitted: true,
        encryptionReady: false,
        phase: 'preparing',
      ),
    );
  }
}

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      fail
          ? 'failed membership keeps the invite dialog and its error'
          : 'committed membership closes the dialog while encryption remains pending',
      (tester) async {
        final gateway = _PendingGateway()
          ..groups = const [
            GroupSummary(
              conversationId: 'group-conversation',
              groupId: _group,
              description: '',
              memberCount: 1,
              lastMessageAt: null,
              encrypted: true,
              canSendSecure: true,
              membershipStatus: 'active',
              myRole: 'owner',
            ),
          ]
          ..following = const [
            RelationshipSummary(
              did: _peer,
              displayName: 'Peer',
              relationship: 'following',
              handle: 'peer.awiki.info',
            ),
          ]
          ..groupMembersByGroupId = {
            _group: const [
              GroupMemberSummary(
                userId: _owner,
                did: _owner,
                role: 'owner',
                handle: 'owner.awiki.info',
                profileUrl: null,
              ),
            ],
          }
          ..publicProfilesByQuery = const {
            'peer.awiki.info': UserProfile(
              did: _peer,
              displayName: 'Peer',
              bio: '',
              tags: [],
              profileMarkdown: '',
              handle: 'peer',
              fullHandle: 'peer.awiki.info',
            ),
            _peer: UserProfile(
              did: _peer,
              displayName: 'Peer',
              bio: '',
              tags: [],
              profileMarkdown: '',
              handle: 'peer',
              fullHandle: 'peer.awiki.info',
            ),
          }
          ..failNextAddGroupMember = fail;
        GroupSummary? updated;
        await tester.pumpWidget(
          buildLocalizedTestApp(
            gateway: gateway,
            session: const SessionIdentity(
              did: _owner,
              credentialName: 'owner',
              handle: 'owner.awiki.info',
              displayName: 'Owner',
            ),
            home: Builder(
              builder: (context) => CupertinoPageScaffold(
                child: Center(
                  child: CupertinoButton(
                    key: const Key('open-invite'),
                    child: const Text('Invite'),
                    onPressed: () => showCupertinoDialog<void>(
                      context: context,
                      builder: (_) => GroupMemberInviteDialog(
                        groupId: _group,
                        existingMembers: const [],
                        onGroupUpdated: (group) => updated = group,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('open-invite')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('group-invite-candidate:$_peer')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('identity-add-group-member-button')),
        );
        await tester.pumpAndSettle();
        if (fail) {
          expect(find.byType(GroupMemberInviteDialog), findsOneWidget);
          expect(find.byType(AwikiMeErrorNotice), findsOneWidget);
          expect(updated, isNull);
          expect(gateway.groupMembersByGroupId[_group], hasLength(1));
        } else {
          expect(find.byType(GroupMemberInviteDialog), findsNothing);
          expect(updated!.operation!.businessCommitted, isTrue);
          expect(updated!.operation!.encryptionReady, isFalse);
          expect(updated!.canSendSecure, isFalse);
          expect(
            gateway.groupMembersByGroupId[_group]!.any(
              (member) => member.did == _peer,
            ),
            isTrue,
          );
        }
      },
    );
  }
}
