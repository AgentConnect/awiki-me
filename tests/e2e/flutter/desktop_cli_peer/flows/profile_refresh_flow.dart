part of '../desktop_cli_peer_e2e.dart';

const String _profileRefreshCaseId = 'DISPLAY-NAME-E2E-004';

Future<void> _verifyProfileRefreshConvergence({
  required _DesktopAppRobot robot,
  required ConversationService conversations,
  required GroupApplicationService groups,
  required RelationshipApplicationService relationships,
  required String ownerDid,
  required _DirectRegressionResult direct,
  required _GroupRegressionResult group,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  final updatedName = 'AWiki Updated $nonce';
  if (updatedName == direct.displayName ||
      updatedName == config.expectedCliPeerDisplayName) {
    fail('Profile refresh fixture must use a distinct nickname.');
  }

  final profileUpdate = await _runCli(config, <String>[
    '--format',
    'json',
    'id',
    'profile',
    'set',
    '--display-name',
    updatedName,
  ]);
  if (profileUpdate.exitCode != 0) {
    fail(
      'CLI profile fixture update failed: '
      '${_summarizeCliResult(profileUpdate)}',
    );
  }

  await robot.openConversationRow(direct.conversationId);
  await robot.expectSelectedPeerInfoDisplayNameAfterRefresh(updatedName);
  await robot.closePeerInfo();
  await robot.expectSelectedConversationHeader(updatedName);

  await robot.pumpUntilObservation(
    description: 'Direct display projection adopts refreshed nickname',
    timeout: const Duration(seconds: 90),
    observe: () {
      try {
        final current = requireExactlyOneDirectConversationForPersona(
          conversations: robot.container
              .read(conversationListProvider)
              .conversations,
          conversationId: direct.conversationId,
          peerPersonaId: direct.peerPersonaId,
          unreadCount: 0,
        );
        if (robot.expectedDirectDisplayName(current) != updatedName) {
          return const E2eObservation.pending(
            'direct_profile_projection_refresh_pending',
          );
        }
      } on StateError {
        return const E2eObservation.fatal(
          'direct_profile_refresh_identity_invariant_failed',
        );
      }
      return const E2eObservation.pass();
    },
  );
  final directProjection = requireExactlyOneDirectConversationForPersona(
    conversations: robot.container.read(conversationListProvider).conversations,
    conversationId: direct.conversationId,
    peerPersonaId: direct.peerPersonaId,
    unreadCount: 0,
  );
  await robot.navigateToMessages();
  await robot.expectConversationRowPresentation(
    conversationId: direct.conversationId,
    expectedTitle: updatedName,
    expectedPreview: directProjection.lastMessagePreview,
    unreadCount: directProjection.unreadCount,
  );

  final reopened = await robot.startDirectConversation(
    config.cliHandle,
    expectedPrimaryDisplayName: updatedName,
  );
  if (reopened.conversationId != direct.conversationId ||
      reopened.peerPersonaId != direct.peerPersonaId) {
    fail('Profile refresh split the canonical Direct identity.');
  }
  await robot.expectSelectedConversationHeader(updatedName);

  final cliFollow = await _runCli(config, <String>[
    '--format',
    'json',
    'people',
    'follow',
    config.appHandle,
  ]);
  if (cliFollow.exitCode != 0) {
    fail(
      'CLI follower fixture update failed: '
      '${_summarizeCliResult(cliFollow)}',
    );
  }
  await _waitForAppRelationshipStatus(
    relationships: relationships,
    peer: direct.peerDid,
    expected: 'follower',
  );
  await robot.refreshRelationshipProjection(
    peerDid: direct.peerDid,
    expectedFollowing: false,
  );
  final contactConversation = await robot.openContactConversation(
    direct.peerDid,
    expectedTitle: updatedName,
    fromFollowers: true,
    forceViewAll: true,
  );
  if (contactConversation.conversationId != direct.conversationId ||
      contactConversation.peerPersonaId != direct.peerPersonaId) {
    fail('Refreshed Contact row opened a different Direct identity.');
  }
  await robot.expectSelectedConversationHeader(updatedName);

  final committedDirect = await conversations.listConversations(
    ownerDid: ownerDid,
  );
  requireExactlyOneDirectConversationForPersona(
    conversations: committedDirect,
    conversationId: direct.conversationId,
    peerPersonaId: direct.peerPersonaId,
    unreadCount: 0,
  );

  await robot.openConversationRow(group.conversationId);
  await robot.expectSelectedConversationHeader(group.groupName);
  final cliFullHandle = config.cliHandle.contains('.')
      ? config.cliHandle
      : '${config.cliHandle}.${config.environment.didDomain}';
  final refreshedMember = await _findGroupMember(
    groups: groups,
    groupDid: group.groupDid,
    memberRef: cliFullHandle,
  );
  await robot.expectGroupMemberDisplayName(
    member: refreshedMember,
    expectedName: updatedName,
  );
  await robot.expectMemberAddedSystemEvent(
    conversationId: group.conversationId,
    subjectDid: group.cliMemberDid,
    expectedMemberName: updatedName,
  );
  final groupMessage = await _waitForUiMessage(
    robot: robot,
    conversationId: group.conversationId,
    content: group.cliMessageText,
    messageId: group.cliMessageId,
    senderDid: group.cliMemberDid,
    sendState: MessageSendState.sent,
  );
  await robot.expectMessageSenderDisplayName(
    conversationId: group.conversationId,
    message: groupMessage,
    expectedName: updatedName,
  );

  await robot.assertStableFor(
    description: 'profile refresh remains canonical and consistent',
    observe: () {
      final state = robot.container.read(conversationListProvider);
      try {
        final current = requireExactlyOneDirectConversationForPersona(
          conversations: state.conversations,
          conversationId: direct.conversationId,
          peerPersonaId: direct.peerPersonaId,
          unreadCount: 0,
        );
        if (robot.expectedDirectDisplayName(current) != updatedName) {
          return const E2eObservation.fatal(
            'profile_refresh_direct_name_reverted',
          );
        }
        requireExactlyOneGroupConversation(
          conversations: state.conversations,
          conversationId: group.conversationId,
          canonicalGroupDid: group.groupDid,
          unreadCount: 0,
        );
      } on StateError {
        return const E2eObservation.fatal(
          'profile_refresh_identity_invariant_failed',
        );
      }
      return const E2eObservation.pass();
    },
  );
}
