part of 'multi_device_join_ui_test.dart';

Future<void> _prepareAppPairPagingPeer({
  required _AppPairRunConfig config,
  required _DedicatedAccount account,
  required AppBootstrap bootstrap,
  required _AppPairContentAdminResources resources,
}) async {
  final peer = _JoinCli.peer(config);
  resources.peer = peer;
  await peer.initialize();
  final peerHandle = _uniqueHandle(config.handlePrefix);
  final peerOtp = await _requestAppRegistrationOtp(
    bootstrap: bootstrap,
    config: config,
    account: account,
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
  final conversationId = resolution.conversationId?.trim() ?? '';
  if (resolution.did != peerDid ||
      !conversationId.startsWith('dm:peer-scope:v1:')) {
    fail('The paging-recovery peer was not resolved canonically.');
  }
  resources
    ..peerDid = peerDid
    ..directConversationId = conversationId;
}

Future<void> _runAppPairAdminPagingRecovery({
  required WidgetTester tester,
  required _AppPairRunConfig config,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String adminDid,
  required String joinedDeviceId,
  required _AppPairContentAdminResources resources,
}) async {
  await _leaveCompletedAppPairApproval(tester);
  final peer = resources.peer;
  final peerDid = resources.peerDid;
  final conversationId = resources.directConversationId;
  if (peer == null || peerDid == null || conversationId == null) {
    fail('The paging-recovery peer fixture was not prepared.');
  }
  await config.coordinator.publish(
    'admin',
    'paging_peer_ready',
    data: <String, Object?>{
      'peerDid': peerDid,
      'conversationId': conversationId,
    },
  );
  await config.coordinator.waitFor(
    'joiner',
    'paging_joiner_ready',
    timeout: const Duration(minutes: 2),
  );

  final baselineText = _appPairMessage(config.runId, 'paging-baseline');
  final baselineId = await peer.sendDirectText(
    to: adminDid,
    text: baselineText,
  );
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: baselineText,
    messageId: baselineId,
    senderDid: peerDid,
    receiverDid: adminDid,
    isMine: false,
  );
  await config.coordinator.publish(
    'admin',
    'paging_baseline_sent',
    data: <String, Object?>{'messageId': baselineId},
  );
  await config.coordinator.waitFor(
    'joiner',
    'paging_baseline_visible',
    timeout: const Duration(minutes: 2),
  );
  await config.coordinator.waitFor(
    'joiner',
    'paging_offline_ready',
    timeout: const Duration(minutes: 2),
  );

  await _prepareAppPairPagingMessages(joinedDeviceId);
  await config.coordinator.publish('admin', 'paging_fixture_ready');
  await config.coordinator.waitFor(
    'joiner',
    'paging_recovery_completed',
    timeout: const Duration(minutes: 3),
  );

  final postRecoveryText = _appPairMessage(
    config.runId,
    'paging-post-recovery',
  );
  final postRecoveryId = await peer.sendDirectText(
    to: adminDid,
    text: postRecoveryText,
  );
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: postRecoveryText,
    messageId: postRecoveryId,
    senderDid: peerDid,
    receiverDid: adminDid,
    isMine: false,
  );
  await config.coordinator.publish(
    'admin',
    'paging_post_recovery_sent',
    data: <String, Object?>{'messageId': postRecoveryId},
  );
  await config.coordinator.waitFor(
    'joiner',
    'paging_post_recovery_visible',
    timeout: const Duration(minutes: 2),
  );
}

Future<void> _runAppPairJoinerPagingRecovery({
  required WidgetTester tester,
  required _AppPairRunConfig config,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String accountDid,
}) async {
  await _leaveCompletedAppPairJoin(tester);
  final peer = await config.coordinator.waitFor(
    'admin',
    'paging_peer_ready',
    timeout: const Duration(minutes: 2),
  );
  final peerDid = _required(peer, 'peerDid');
  final conversationId = _required(peer, 'conversationId');
  await config.coordinator.publish('joiner', 'paging_joiner_ready');

  final baseline = await config.coordinator.waitFor(
    'admin',
    'paging_baseline_sent',
    timeout: const Duration(minutes: 2),
  );
  final baselineId = _required(baseline, 'messageId');
  final baselineText = _appPairMessage(config.runId, 'paging-baseline');
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: baselineText,
    messageId: baselineId,
    senderDid: peerDid,
    receiverDid: accountDid,
    isMine: false,
  );
  await config.coordinator.publish('joiner', 'paging_baseline_visible');

  await _pumpUntil(
    tester,
    () {
      final sync = container.read(messageSyncCoordinatorProvider);
      return !sync.isSyncing && sync.pendingReason == null;
    },
    timeout: const Duration(seconds: 30),
    failure: 'The paging-recovery sync queue did not quiesce before offline.',
  );
  container
      .read(appLifecycleProvider.notifier)
      .setLifecycle(AppLifecycleState.paused);
  await container.read(realtimeApplicationServiceProvider).stop();
  if (container.read(realtimeApplicationServiceProvider).isRunning) {
    fail('The paging-recovery joining App remained online.');
  }
  await config.coordinator.publish('joiner', 'paging_offline_ready');
  await config.coordinator.waitFor(
    'admin',
    'paging_fixture_ready',
    timeout: const Duration(minutes: 2),
  );

  final successSequence = container
      .read(messageSyncCoordinatorProvider)
      .safeDiagnostics
      .refreshSuccessSequence;
  await _resumeAppPairAndWaitForSync(
    tester: tester,
    container: container,
    timeout: const Duration(minutes: 2),
    failure: 'The joining App did not finish 501-message paged recovery.',
  );
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: baselineText,
    messageId: baselineId,
    senderDid: peerDid,
    receiverDid: accountDid,
    isMine: false,
  );
  final recovered = container.read(messageSyncCoordinatorProvider);
  if (recovered.olderHistoryExcluded ||
      recovered.status == MessageSyncCoordinatorStatus.capacityExceeded ||
      recovered.lastError != null ||
      recovered.isAuthRevoked) {
    fail(
      'The 501-message App recovery did not finish as an unbounded success.',
    );
  }
  await _waitForSafeAppPairSyncDiagnostics(
    tester: tester,
    container: container,
    priorSuccessSequence: successSequence,
  );
  await config.coordinator.publish('joiner', 'paging_recovery_completed');

  final postRecovery = await config.coordinator.waitFor(
    'admin',
    'paging_post_recovery_sent',
    timeout: const Duration(minutes: 2),
  );
  final postRecoveryId = _required(postRecovery, 'messageId');
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: _appPairMessage(config.runId, 'paging-post-recovery'),
    messageId: postRecoveryId,
    senderDid: peerDid,
    receiverDid: accountDid,
    isMine: false,
  );
  await config.coordinator.publish('joiner', 'paging_post_recovery_visible');
  await E2eCaseAttestationWriter.markPassed(
    _appPairPagingRecoveryCaseId,
    phases: const <String>[
      'joined_replica_committed_ordinary_baseline',
      'exact_device_messages_501_fixture_prepared',
      'core_owned_schema3_paged_recovery_completed',
      'pre_recovery_projection_preserved_exactly_once',
      'capacity_and_bounded_history_remained_false',
      'post_recovery_delta_converged_exactly_once',
      'diagnostics_remained_secret_free',
    ],
  );
}
