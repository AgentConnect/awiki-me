part of 'multi_device_join_ui_test.dart';

class _AppPairContentAdminResources {
  _JoinCli? peer;
  String? peerDid;
  String? directConversationId;
  String? groupDid;
  String? groupConversationId;
  String? preGroupMessageId;
  String? preAttachmentMessageId;
  String? preAttachmentId;

  Future<void> dispose() async {
    final currentPeer = peer;
    peer = null;
    await currentPeer?.deleteLocalState();
  }
}

String _contentText(String runId, String phase) =>
    'app-pair-${_safeId(runId, 20)}-content-$phase';

String _contentFilename(String runId, String phase) =>
    '${_safeId(runId, 12)}-$phase.txt';

Uint8List _contentBytes(String runId, String phase) =>
    Uint8List.fromList(utf8.encode('AWiki $runId $phase\n'));

Future<void> _prepareAppPairContentHistory({
  required _AppPairRunConfig config,
  required _DedicatedAccount account,
  required http.Client httpClient,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String adminDid,
  required _AppPairContentAdminResources resources,
}) async {
  final peer = _JoinCli.peer(config);
  resources.peer = peer;
  await peer.initialize();
  final peerHandle = _uniqueHandle(config.handlePrefix);
  final peerOtp = await _requestAndResolveOtp(
    client: httpClient,
    config: config,
    account: account,
    purpose: _registrationPurpose,
    handle: peerHandle,
  );
  final peerDid = await peer.registerReadyAdmin(
    handle: peerHandle,
    phone: account.phone,
    otp: peerOtp,
  );
  final resolution = await bootstrap.directoryApplicationService!.resolvePeer(
    peerDid,
  );
  final directConversationId = resolution.conversationId?.trim() ?? '';
  if (resolution.did != peerDid ||
      !directConversationId.startsWith('dm:peer-scope:v1:')) {
    fail('The content-sync Direct peer was not resolved canonically.');
  }

  final groups = bootstrap.groupApplicationService!;
  final group = await groups.createGroup(
    name: 'Pair content ${_safeId(config.runId, 10)}',
    slug: 'pair-content-${_safeId(config.runId, 12)}',
    description: 'Multi-device content-sync E2E',
    goal: 'Verify joined-device content convergence',
    rules: 'E2E only',
  );
  final groupDid = group.groupId.trim();
  final groupConversationId = 'group:$groupDid';
  await groups.addMember(groupDid: groupDid, memberRef: peerDid);

  final groupText = _contentText(config.runId, 'pre-group');
  final preGroup = await bootstrap.messagingService!.sendConversationText(
    conversation: AppConversationReadRef.fromConversationId(
      groupConversationId,
    ),
    content: groupText,
  );
  final preGroupId = _requireCommittedContentMessage(
    preGroup,
    conversationId: groupConversationId,
    senderDid: adminDid,
    isMine: true,
    groupDid: groupDid,
    failure: 'The existing App did not commit the pre-Join Group message.',
  );
  await _waitForContentMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: groupConversationId,
    content: groupText,
    messageId: preGroupId,
    senderDid: adminDid,
    isMine: true,
    groupDid: groupDid,
  );

  final attachmentBytes = _contentBytes(config.runId, 'pre-attachment');
  final attachmentCaption = _contentText(config.runId, 'pre-attachment');
  final preAttachment = await bootstrap.messagingService!
      .sendConversationAttachment(
        conversation: AppConversationReadRef.fromConversationId(
          directConversationId,
        ),
        attachment: AttachmentDraft(
          filename: _contentFilename(config.runId, 'prejoin'),
          mimeType: 'text/plain',
          bytes: attachmentBytes,
          sizeBytes: attachmentBytes.length,
        ),
        caption: attachmentCaption,
      );
  final preAttachmentId = _requireCommittedContentMessage(
    preAttachment,
    conversationId: directConversationId,
    senderDid: adminDid,
    isMine: true,
    failure: 'The existing App did not commit the pre-Join attachment.',
  );
  final attachmentId = preAttachment.attachment?.attachmentId.trim() ?? '';
  if (attachmentId.isEmpty) {
    fail('The pre-Join attachment omitted its canonical attachment ID.');
  }
  await _waitForContentMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: directConversationId,
    content: attachmentCaption,
    messageId: preAttachmentId,
    senderDid: adminDid,
    isMine: true,
    attachmentId: attachmentId,
  );

  resources
    ..peerDid = peerDid
    ..directConversationId = directConversationId
    ..groupDid = groupDid
    ..groupConversationId = groupConversationId
    ..preGroupMessageId = preGroupId
    ..preAttachmentMessageId = preAttachmentId
    ..preAttachmentId = attachmentId;
}

Future<void> _runAppPairAdminContentSync({
  required WidgetTester tester,
  required _AppPairRunConfig config,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String adminDid,
  required _AppPairContentAdminResources resources,
}) async {
  await _leaveCompletedAppPairApproval(tester);
  final peer = resources.peer;
  final peerDid = resources.peerDid;
  final directId = resources.directConversationId;
  final groupDid = resources.groupDid;
  final groupId = resources.groupConversationId;
  if (peer == null ||
      peerDid == null ||
      directId == null ||
      groupDid == null ||
      groupId == null) {
    fail('The content-sync pre-Join fixture was not prepared.');
  }
  await config.coordinator.publish(
    'admin',
    'content_fixture_ready',
    data: <String, Object?>{
      'peerDid': peerDid,
      'directConversationId': directId,
      'groupDid': groupDid,
      'groupConversationId': groupId,
      'preGroupMessageId': resources.preGroupMessageId!,
      'preAttachmentMessageId': resources.preAttachmentMessageId!,
      'preAttachmentId': resources.preAttachmentId!,
    },
  );
  await config.coordinator.waitFor('joiner', 'content_prejoin_absent');

  final postGroupText = _contentText(config.runId, 'post-group');
  final postGroup = await bootstrap.messagingService!.sendConversationText(
    conversation: AppConversationReadRef.fromConversationId(groupId),
    content: postGroupText,
  );
  final postGroupId = _requireCommittedContentMessage(
    postGroup,
    conversationId: groupId,
    senderDid: adminDid,
    isMine: true,
    groupDid: groupDid,
    failure: 'The existing App did not commit the post-Join Group message.',
  );

  final attachmentBytes = _contentBytes(config.runId, 'post-attachment');
  final attachmentCaption = _contentText(config.runId, 'post-attachment');
  final postAttachment = await bootstrap.messagingService!
      .sendConversationAttachment(
        conversation: AppConversationReadRef.fromConversationId(directId),
        attachment: AttachmentDraft(
          filename: _contentFilename(config.runId, 'postjoin'),
          mimeType: 'text/plain',
          bytes: attachmentBytes,
          sizeBytes: attachmentBytes.length,
        ),
        caption: attachmentCaption,
      );
  final postAttachmentMessageId = _requireCommittedContentMessage(
    postAttachment,
    conversationId: directId,
    senderDid: adminDid,
    isMine: true,
    failure: 'The existing App did not commit the post-Join attachment.',
  );
  final postAttachmentId = postAttachment.attachment?.attachmentId.trim() ?? '';
  if (postAttachmentId.isEmpty) {
    fail('The post-Join attachment omitted its canonical attachment ID.');
  }
  await config.coordinator.publish(
    'admin',
    'content_postjoin_sent',
    data: <String, Object?>{
      'groupMessageId': postGroupId,
      'attachmentMessageId': postAttachmentMessageId,
      'attachmentId': postAttachmentId,
    },
  );
  final reverse = await config.coordinator.waitFor(
    'joiner',
    'content_group_reverse_sent',
  );
  await _waitForContentMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: groupId,
    content: _contentText(config.runId, 'joiner-group'),
    messageId: _required(reverse, 'messageId'),
    senderDid: adminDid,
    isMine: true,
    groupDid: groupDid,
  );

  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: directId,
    matches: (value) => value == 0,
    failure: 'The existing App Direct unread baseline was not zero.',
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: groupId,
    matches: (value) => value == 0,
    failure: 'The existing App Group unread baseline was not zero.',
  );
  await config.coordinator.waitFor('joiner', 'content_unread_baseline_ready');

  final incomingDirectText = _contentText(config.runId, 'peer-direct');
  final incomingGroupText = _contentText(config.runId, 'peer-group');
  final incomingDirectId = await peer.sendDirectText(
    to: adminDid,
    text: incomingDirectText,
  );
  final incomingGroupId = await peer.sendGroupText(
    groupDid: groupDid,
    text: incomingGroupText,
  );
  await _waitForContentMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: directId,
    content: incomingDirectText,
    messageId: incomingDirectId,
    senderDid: peerDid,
    isMine: false,
  );
  await _waitForContentMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: groupId,
    content: incomingGroupText,
    messageId: incomingGroupId,
    senderDid: peerDid,
    isMine: false,
    groupDid: groupDid,
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: directId,
    matches: (value) => value == 1,
    failure: 'The existing App Direct unread count did not advance to one.',
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: groupId,
    matches: (value) => value == 1,
    failure: 'The existing App Group unread count did not advance to one.',
  );
  await config.coordinator.publish(
    'admin',
    'content_incoming_sent',
    data: <String, Object?>{
      'directMessageId': incomingDirectId,
      'groupMessageId': incomingGroupId,
    },
  );
  await config.coordinator.waitFor('joiner', 'content_direct_read_committed');
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: directId,
    matches: (value) => value == 0,
    failure: 'The sibling Direct read did not converge to the existing App.',
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: groupId,
    matches: (value) => value == 1,
    failure: 'Reading Direct incorrectly cleared Group unread state.',
  );
  await config.coordinator.publish('admin', 'content_direct_read_converged');

  await config.coordinator.waitFor('joiner', 'content_group_read_committed');
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: groupId,
    matches: (value) => value == 0,
    failure: 'The sibling Group read did not converge to the existing App.',
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: directId,
    matches: (value) => value == 0,
    failure: 'The converged Direct read state regressed after Group read.',
  );
  await container
      .read(messageSyncCoordinatorProvider.notifier)
      .requestSync('e2e_content_final_exact_once', immediate: true);
  await _assertContentMessageCount(
    messaging: bootstrap.messagingService!,
    conversationId: groupId,
    messageId: incomingGroupId,
    expected: 1,
  );
  await config.coordinator.publish('admin', 'content_group_read_converged');
}

Future<void> _runAppPairJoinerContentSync({
  required WidgetTester tester,
  required _AppPairRunConfig config,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String accountDid,
}) async {
  await _leaveCompletedAppPairJoin(tester);
  final fixture = await config.coordinator.waitFor(
    'admin',
    'content_fixture_ready',
  );
  final peerDid = _required(fixture, 'peerDid');
  final directId = _required(fixture, 'directConversationId');
  final groupDid = _required(fixture, 'groupDid');
  final groupId = _required(fixture, 'groupConversationId');
  await _assertContentPreJoinAbsent(
    tester: tester,
    container: container,
    messaging: bootstrap.messagingService!,
    peerDid: peerDid,
    directConversationId: directId,
    groupConversationId: groupId,
    forbidden: <String, String>{
      _required(fixture, 'preGroupMessageId'): _contentText(
        config.runId,
        'pre-group',
      ),
      _required(fixture, 'preAttachmentMessageId'): _contentText(
        config.runId,
        'pre-attachment',
      ),
    },
    forbiddenAttachmentId: _required(fixture, 'preAttachmentId'),
    forbiddenAttachmentFilename: _contentFilename(config.runId, 'prejoin'),
  );
  await container
      .read(messageSyncCoordinatorProvider.notifier)
      .requestSync('e2e_content_tail_stability', immediate: true);
  await _assertContentPreJoinAbsent(
    tester: tester,
    container: container,
    messaging: bootstrap.messagingService!,
    peerDid: peerDid,
    directConversationId: directId,
    groupConversationId: groupId,
    forbidden: <String, String>{
      _required(fixture, 'preGroupMessageId'): _contentText(
        config.runId,
        'pre-group',
      ),
      _required(fixture, 'preAttachmentMessageId'): _contentText(
        config.runId,
        'pre-attachment',
      ),
    },
    forbiddenAttachmentId: _required(fixture, 'preAttachmentId'),
    forbiddenAttachmentFilename: _contentFilename(config.runId, 'prejoin'),
  );
  await config.coordinator.publish('joiner', 'content_prejoin_absent');

  final sent = await config.coordinator.waitFor(
    'admin',
    'content_postjoin_sent',
  );
  await _waitForContentMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: groupId,
    content: _contentText(config.runId, 'post-group'),
    messageId: _required(sent, 'groupMessageId'),
    senderDid: accountDid,
    isMine: true,
    groupDid: groupDid,
  );
  final attachmentMessage = await _waitForContentMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: directId,
    content: _contentText(config.runId, 'post-attachment'),
    messageId: _required(sent, 'attachmentMessageId'),
    senderDid: accountDid,
    isMine: true,
    attachmentId: _required(sent, 'attachmentId'),
  );
  final expectedBytes = _contentBytes(config.runId, 'post-attachment');
  final attachment = attachmentMessage.attachment!;
  if (attachment.filename != _contentFilename(config.runId, 'postjoin') ||
      attachment.mimeType != 'text/plain' ||
      attachment.sizeBytes != expectedBytes.length) {
    fail('The joined App attachment metadata did not match the sender.');
  }
  final download = await bootstrap.messagingService!.downloadAttachment(
    thread: AppThreadRef.direct(peerDid),
    messageId: attachmentMessage.remoteId!,
    attachmentId: attachment.attachmentId,
  );
  if (download.bytes == null ||
      sha256.convert(download.bytes!) != sha256.convert(expectedBytes)) {
    fail('The joined App attachment bytes did not match the sender digest.');
  }
  await E2eCaseAttestationWriter.markPassed(
    _appPairContentTailOnlyCaseId,
    phases: const <String>[
      'prejoin_group_and_attachment_absent',
      'prejoin_content_contributed_no_unread',
      'explicit_pull_preserved_tail_boundary',
      'postjoin_group_and_attachment_visible_once',
    ],
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairAttachmentSyncCaseId,
    phases: const <String>[
      'canonical_attachment_message_and_object_preserved',
      'attachment_metadata_matched',
      'joined_device_download_digest_matched',
      'attachment_message_projected_once',
    ],
  );

  final reverseText = _contentText(config.runId, 'joiner-group');
  final reverse = await bootstrap.messagingService!.sendConversationText(
    conversation: AppConversationReadRef.fromConversationId(groupId),
    content: reverseText,
  );
  final reverseId = _requireCommittedContentMessage(
    reverse,
    conversationId: groupId,
    senderDid: accountDid,
    isMine: true,
    groupDid: groupDid,
    failure: 'The joining App did not commit its Group message.',
  );
  await config.coordinator.publish(
    'joiner',
    'content_group_reverse_sent',
    data: <String, Object?>{'messageId': reverseId},
  );

  await _openContentObserverPage(tester);
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: directId,
    matches: (value) => value == 0,
    failure: 'The joining App Direct unread baseline was not zero.',
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: groupId,
    matches: (value) => value == 0,
    failure: 'The joining App Group unread baseline was not zero.',
  );
  await config.coordinator.publish('joiner', 'content_unread_baseline_ready');
  final incoming = await config.coordinator.waitFor(
    'admin',
    'content_incoming_sent',
  );
  final incomingDirectText = _contentText(config.runId, 'peer-direct');
  final incomingGroupText = _contentText(config.runId, 'peer-group');
  await _waitForContentMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: directId,
    content: incomingDirectText,
    messageId: _required(incoming, 'directMessageId'),
    senderDid: peerDid,
    isMine: false,
  );
  await _waitForContentMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: groupId,
    content: incomingGroupText,
    messageId: _required(incoming, 'groupMessageId'),
    senderDid: peerDid,
    isMine: false,
    groupDid: groupDid,
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: directId,
    matches: (value) => value == 1,
    failure: 'The joining App Direct unread count did not advance to one.',
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: groupId,
    matches: (value) => value == 1,
    failure: 'The joining App Group unread count did not advance to one.',
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairGroupSyncCaseId,
    phases: const <String>[
      'admin_group_own_sync_projected_once',
      'joiner_group_own_sync_projected_once',
      'canonical_group_and_conversation_preserved',
      'external_group_message_projected_incoming_once',
    ],
  );

  await _openAppPairConversation(
    tester: tester,
    conversationId: directId,
    content: incomingDirectText,
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: directId,
    matches: (value) => value == 0,
    failure: 'Opening Direct did not commit its read state.',
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: groupId,
    matches: (value) => value == 1,
    failure: 'Opening Direct incorrectly cleared Group unread state.',
  );
  await config.coordinator.publish('joiner', 'content_direct_read_committed');
  await config.coordinator.waitFor('admin', 'content_direct_read_converged');

  await _openAppPairConversation(
    tester: tester,
    conversationId: groupId,
    content: incomingGroupText,
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: groupId,
    matches: (value) => value == 0,
    failure: 'Opening Group did not commit its read state.',
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: directId,
    matches: (value) => value == 0,
    failure: 'Opening Group regressed the Direct read state.',
  );
  await config.coordinator.publish('joiner', 'content_group_read_committed');
  await config.coordinator.waitFor('admin', 'content_group_read_converged');
  await container
      .read(messageSyncCoordinatorProvider.notifier)
      .requestSync('e2e_content_joiner_final_exact_once', immediate: true);
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: directId,
    matches: (value) => value == 0,
    failure: 'Repeated sync regressed the joining App Direct read state.',
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: groupId,
    matches: (value) => value == 0,
    failure: 'Repeated sync regressed the joining App Group read state.',
  );
  await _assertContentMessageCount(
    messaging: bootstrap.messagingService!,
    conversationId: groupId,
    messageId: _required(incoming, 'groupMessageId'),
    expected: 1,
  );

  await E2eCaseAttestationWriter.markPassed(
    _appPairGroupReadSyncCaseId,
    phases: const <String>[
      'direct_and_group_unread_projected_independently',
      'direct_read_converged_without_clearing_group',
      'group_read_converged_without_regressing_direct',
      'repeat_sync_preserved_exact_once_and_zero_unread',
    ],
  );
}

String _requireCommittedContentMessage(
  ChatMessage message, {
  required String conversationId,
  required String senderDid,
  required bool isMine,
  String? groupDid,
  required String failure,
}) {
  final id = message.remoteId?.trim() ?? '';
  if (id.isEmpty ||
      message.conversationId != conversationId ||
      message.senderDid != senderDid ||
      message.isMine != isMine ||
      message.sendState != MessageSendState.sent ||
      (groupDid != null && message.groupId != groupDid)) {
    fail(failure);
  }
  return id;
}

Future<ChatMessage> _waitForContentMessage({
  required ProviderContainer container,
  required MessagingService messaging,
  required String conversationId,
  required String content,
  required String messageId,
  required String senderDid,
  required bool isMine,
  String? groupDid,
  String? attachmentId,
}) async {
  if (messaging is! ConversationTimelineMessagingService) {
    fail('The content-sync suite requires canonical timeline reads.');
  }
  final timeline = messaging as ConversationTimelineMessagingService;
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    final messages = await timeline.loadConversationTimeline(
      AppConversationReadRef.fromConversationId(conversationId),
      limit: 50,
    );
    final matches = messages
        .where((message) => message.remoteId == messageId)
        .toList(growable: false);
    if (matches.length > 1) {
      fail(
        'The content-sync timeline projected a duplicate canonical message.',
      );
    }
    if (matches.length == 1) {
      final message = matches.single;
      if (message.content == content &&
          message.conversationId == conversationId &&
          message.senderDid == senderDid &&
          message.isMine == isMine &&
          message.sendState == MessageSendState.sent &&
          (groupDid == null || message.groupId == groupDid) &&
          (attachmentId == null ||
              message.attachment?.attachmentId == attachmentId)) {
        return message;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 750));
  }
  final sync = container.read(messageSyncCoordinatorProvider);
  fail(
    'The content-sync message did not converge exactly '
    '(conversation=$conversationId, lastSync=${sync.lastReason ?? 'none'}, '
    'syncError=${_appPairErrorDiagnostic(sync.lastError)}).',
  );
}

Future<void> _assertContentPreJoinAbsent({
  required WidgetTester tester,
  required ProviderContainer container,
  required MessagingService messaging,
  required String peerDid,
  required String directConversationId,
  required String groupConversationId,
  required Map<String, String> forbidden,
  required String forbiddenAttachmentId,
  required String forbiddenAttachmentFilename,
}) async {
  if (messaging is! ConversationTimelineMessagingService) {
    fail('The content-sync suite requires canonical timeline reads.');
  }
  final direct = ConversationSummary(
    conversationId: directConversationId,
    threadId: peerDid,
    displayName: peerDid,
    lastMessagePreview: '',
    lastMessageAt: DateTime.fromMillisecondsSinceEpoch(0),
    unreadCount: 0,
    isGroup: false,
    targetDid: peerDid,
  );
  await container.read(chatThreadsProvider.notifier).openConversation(direct);
  await tester.pump(const Duration(seconds: 2));
  final timeline = messaging as ConversationTimelineMessagingService;
  for (final conversationId in <String>[
    directConversationId,
    groupConversationId,
  ]) {
    final messages = await timeline.loadConversationTimeline(
      AppConversationReadRef.fromConversationId(conversationId),
      limit: 50,
    );
    if (messages.any(
      (message) =>
          forbidden.containsKey(message.remoteId) ||
          forbidden.containsValue(message.content) ||
          message.attachment?.attachmentId == forbiddenAttachmentId ||
          message.attachment?.filename == forbiddenAttachmentFilename,
    )) {
      fail('The joining App hydrated content from before its Join boundary.');
    }
  }
  final rows = container
      .read(conversationListProvider)
      .conversations
      .where(
        (row) =>
            row.conversationId == directConversationId ||
            row.conversationId == groupConversationId,
      );
  if (rows.any((row) => row.unreadCount != 0) ||
      rows.any((row) => forbidden.values.contains(row.lastMessagePreview))) {
    fail('Pre-Join content leaked into the joining App list or unread state.');
  }
  await _openContentObserverPage(tester);
}

Future<void> _openContentObserverPage(WidgetTester tester) async {
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('e2e-contacts-tab'),
    failure: 'The content-sync observer page was unavailable.',
  );
  await tester.pump();
}

Future<void> _assertContentMessageCount({
  required MessagingService messaging,
  required String conversationId,
  required String messageId,
  required int expected,
}) async {
  if (messaging is! ConversationTimelineMessagingService) {
    fail('The content-sync suite requires canonical timeline reads.');
  }
  final messages = await (messaging as ConversationTimelineMessagingService)
      .loadConversationTimeline(
        AppConversationReadRef.fromConversationId(conversationId),
        limit: 50,
      );
  if (messages.where((message) => message.remoteId == messageId).length !=
      expected) {
    fail('Repeated sync changed the canonical message count.');
  }
}
