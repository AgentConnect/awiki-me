part of 'multi_device_join_ui_test.dart';

Future<void> _runAppPairAcp({
  required WidgetTester tester,
  required _AppPairRunConfig config,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String accountDid,
  required String handle,
  required bool admin,
  _AppPairFunctionalAdminResources? resources,
}) async {
  if (admin) {
    await _leaveCompletedAppPairApproval(tester);
  } else {
    await _leaveCompletedAppPairJoin(tester);
  }
  final role = admin ? 'admin' : 'joiner';
  final peer = admin ? 'joiner' : 'admin';
  final coordinator = config.coordinator;
  String agentDid;
  if (admin) {
    final installed = await _installAppPairDaemon(
      config: config,
      inventory: container.read(agentInventoryPortProvider),
      controllerDid: accountDid,
      controllerHandle: handle,
    );
    resources!.daemon = await _startAppPairDaemon(config);
    await _waitForAppPairDaemonReady(config.daemonReadyFile, resources.daemon!);
    await _openAppPairAgentsPage(tester);
    await _waitForAppPairAgent(
      tester: tester,
      container: container,
      agentDid: installed.daemonDid,
      handle: installed.handle,
      activelyLoad: true,
    );
    final agents = container.read(agentsProvider.notifier);
    await agents.refreshDaemonStatus(installed.daemonDid);
    await _pumpUntil(
      tester,
      () {
        final daemon = container
            .read(agentsProvider)
            .agents
            .where((a) => a.agentDid == installed.daemonDid)
            .single;
        final summary = acpMap(
          daemon.latest.diagnosticsSummary['config_summary'],
        );
        final capabilities = acpMap(summary['acp']);
        return capabilities['capability_schema_version'] == 1 &&
            capabilities['supported_drivers'] is List &&
            (capabilities['supported_drivers'] as List).contains('opencode');
      },
      timeout: const Duration(seconds: 45),
      failure: 'ACP capability was not advertised.',
    );
    final runtimeHandle = _appPairRuntimeHandle(config.runId, 'opencode');
    await agents.createRuntimeAgent(
      installed.daemonDid,
      options: RuntimeAgentCreateOptions(
        kind: RuntimeAgentKind.opencode,
        handle: runtimeHandle,
        displayName: 'Pair ACP',
        workspaceMode: runtimeWorkspaceModeSharedRoot,
      ),
    );
    debugPrint(
      'ACP pair create delivery: ${jsonEncode(await codingAgentDeliveryDiagnostics(bootstrap.messagingService!, installed.daemonDid))}',
    );
    final runtime = await _waitForAppPairRuntime(
      tester: tester,
      container: container,
      daemon: resources.daemon!,
      daemonDid: installed.daemonDid,
      handle: runtimeHandle,
      runtime: RuntimeAgentKind.opencode.runtime,
    );
    agentDid = runtime.agentDid;
    await coordinator.publish(
      role,
      'acp_runtime',
      data: {'agentDid': agentDid, 'handle': runtimeHandle},
    );
  } else {
    final runtime = await coordinator.waitFor(
      'admin',
      'acp_runtime',
      timeout: const Duration(minutes: 4),
    );
    agentDid = _required(runtime, 'agentDid');
    await _openAppPairAgentsPage(tester);
    await _waitForAppPairAgent(
      tester: tester,
      container: container,
      agentDid: agentDid,
      handle: _required(runtime, 'handle'),
      activelyLoad: false,
    );
  }
  container.read(agentsProvider.notifier).select(agentDid);
  await tester.pump(const Duration(milliseconds: 200));
  final workspace = find.byType(AgentsWorkspacePage);
  await _tapOne(
    tester,
    find.text(tester.element(workspace).l10n.agentOpenChat),
    failure: 'ACP chat was unavailable on a real App.',
  );
  await _pumpUntil(
    tester,
    () => find.bySemanticsIdentifier('e2e-chat-input').evaluate().length == 1,
    timeout: const Duration(seconds: 30),
    failure: 'ACP composer was unavailable.',
  );
  await coordinator.publish(role, 'acp_chat_ready');
  await coordinator.waitFor(peer, 'acp_chat_ready');
  if (admin) {
    const prompt =
        'Use awiki_questions request_user_input to ask a required pair_answer string with enum first and second. Wait for my real answer. If first reply exactly PAIR_ANSWER_FIRST; if second reply exactly PAIR_ANSWER_SECOND. Do not answer for me.';
    await _pairAcpSend(tester, prompt);
    await _pairAcpWaitSent(
      tester,
      bootstrap.messagingService!,
      agentDid,
      prompt,
    );
  }
  var session = await _pairAcpWait(
    tester,
    container,
    agentDid,
    (s) =>
        hasAcpBlockingQuestion(s, nowMs: DateTime.now().millisecondsSinceEpoch),
  );
  final questionId = session.questions.single['id'];
  final questionRun = session.active['run_id'];
  final draft = 'UNSENT_${role.toUpperCase()}_DRAFT';
  await _pairAcpEnter(tester, draft);
  expect(find.byType(AcpQuestionForm), findsOneWidget);
  expect(
    tester.widget<AcpQuestionForm>(find.byType(AcpQuestionForm)).canAnswer,
    isTrue,
  );
  await _tapOne(
    tester,
    find.descendant(
      of: find.byType(AcpQuestionForm),
      matching: find.text(admin ? 'first' : 'second'),
    ),
    failure: 'ACP answer option missing.',
  );
  await coordinator.publish(
    role,
    'acp_answer_ready',
    data: {'questionId': questionId, 'runId': questionRun},
  );
  final otherQuestion = await coordinator.waitFor(
    peer,
    'acp_answer_ready',
    timeout: const Duration(minutes: 4),
  );
  expect(otherQuestion['questionId'], questionId);
  expect(otherQuestion['runId'], questionRun);
  if (admin) {
    await coordinator.publish(
      role,
      'acp_answer_go',
      data: {
        'at': DateTime.now()
            .add(const Duration(seconds: 2))
            .millisecondsSinceEpoch,
      },
    );
  }
  final go = await coordinator.waitFor('admin', 'acp_answer_go');
  await _pumpUntil(
    tester,
    () => DateTime.now().millisecondsSinceEpoch >= (go['at'] as int),
    timeout: const Duration(seconds: 5),
    failure: 'Answer race did not start.',
  );
  final submit = find.text('提交回答').evaluate().isNotEmpty
      ? find.text('提交回答')
      : find.text('Submit answer');
  await _tapOne(
    tester,
    submit,
    failure: 'Prepared live answer disappeared before concurrent submission.',
  );
  session = await _pairAcpWait(
    tester,
    container,
    agentDid,
    (s) => s.history.any(
      (t) => t['run_id'] == questionRun && t['state'] == 'finished',
    ),
  );
  expect(session.questions, isEmpty);
  expect(
    session.history.where((t) => t['run_id'] == questionRun),
    hasLength(1),
  );
  final answer = await _pairAcpFinal(
    tester,
    bootstrap.messagingService!,
    agentDid,
    const ['PAIR_ANSWER_FIRST', 'PAIR_ANSWER_SECOND'],
  );
  expect(_pairAcpDraft(tester), draft);
  await coordinator.publish(
    role,
    'acp_answer_done',
    data: {'reply': answer.content, 'remoteId': answer.remoteId},
  );
  final peerAnswer = await coordinator.waitFor(peer, 'acp_answer_done');
  expect(peerAnswer['reply'], answer.content);
  expect(peerAnswer['remoteId'], answer.remoteId);
  if (admin) {
    await E2eCaseAttestationWriter.markPassed(
      'DEVICE-ACP-SYNC-E2E-001',
      phases: const [
        'two_real_apps_same_live_question',
        'concurrent_ui_answers_one_result',
        'both_drafts_retained',
        'same_final_message_exact_once',
      ],
    );
    await _pairAcpSend(
      tester,
      'This is a new restart test. Use awiki_questions request_user_input to ask a required restart_answer string with enum keep_waiting. Wait for my real answer. Do not answer for me.',
    );
  }
  session = await _pairAcpWait(
    tester,
    container,
    agentDid,
    (s) =>
        hasAcpBlockingQuestion(s, nowMs: DateTime.now().millisecondsSinceEpoch),
  );
  final interrupted = session.active['run_id'];
  await coordinator.publish(role, 'acp_queue_ready');
  await coordinator.waitFor(peer, 'acp_queue_ready');
  await _pairAcpSend(
    tester,
    admin
        ? 'Reply exactly PAIR_QUEUE_ADMIN.'
        : 'Reply exactly PAIR_QUEUE_JOINER.',
  );
  // A device which sees the committed waiting slot before send retains its
  // draft; a simultaneous delivered submission receives a committed rejection.
  if (find.byType(CupertinoAlertDialog).evaluate().isNotEmpty) {
    final ok = find.text('知道了').evaluate().isNotEmpty
        ? find.text('知道了')
        : find.text('OK');
    await _tapOne(tester, ok, failure: 'Queue rejection had no exit action.');
  }
  session = await _pairAcpWait(
    tester,
    container,
    agentDid,
    (s) => s.waiting.isNotEmpty,
  );
  final waiting = session.waiting['run_id'];
  await _pairAcpEnter(tester, draft);
  await coordinator.publish(role, 'acp_waiting', data: {'runId': waiting});
  final peerWaiting = await coordinator.waitFor(peer, 'acp_waiting');
  expect(peerWaiting['runId'], waiting);
  if (admin) {
    resources!.daemon!.process.kill(ProcessSignal.sigkill);
    await resources.daemon!.process.exitCode.timeout(
      const Duration(seconds: 20),
    );
    resources.daemon = await _startAppPairDaemon(config);
    await _waitForAppPairDaemonReady(config.daemonReadyFile, resources.daemon!);
  }
  session = await _pairAcpWait(
    tester,
    container,
    agentDid,
    (s) =>
        !s.busy &&
        s.waitingPaused &&
        s.history.any(
          (t) => t['run_id'] == interrupted && t['state'] == 'interrupted',
        ),
  );
  expect(session.waiting['run_id'], waiting);
  expect(_pairAcpDraft(tester), draft);
  await coordinator.publish(role, 'acp_restart_paused');
  await coordinator.waitFor(peer, 'acp_restart_paused');
  if (!admin) {
    await _tapOne(
      tester,
      find.byKey(ValueKey('acp-execute_waiting:$waiting')),
      failure: 'The second App could not manually execute the paused task.',
    );
  }
  session = await _pairAcpWait(
    tester,
    container,
    agentDid,
    (s) => s.history.any(
      (t) => t['run_id'] == waiting && t['state'] == 'finished',
    ),
  );
  expect(session.history.where((t) => t['run_id'] == waiting), hasLength(1));
  final queued = await _pairAcpFinal(
    tester,
    bootstrap.messagingService!,
    agentDid,
    const ['PAIR_QUEUE_ADMIN', 'PAIR_QUEUE_JOINER'],
  );
  expect(_pairAcpDraft(tester), draft);
  await coordinator.publish(
    role,
    'acp_queue_done',
    data: {'reply': queued.content, 'remoteId': queued.remoteId},
  );
  final peerQueued = await coordinator.waitFor(peer, 'acp_queue_done');
  expect(peerQueued['reply'], queued.content);
  expect(peerQueued['remoteId'], queued.remoteId);
  if (admin) {
    await E2eCaseAttestationWriter.markPassed(
      'DEVICE-ACP-SYNC-E2E-002',
      phases: const [
        'one_waiting_task_on_both_apps',
        'daemon_restart_interrupts_active',
        'waiting_remains_paused_and_drafts_retained',
        'second_device_executes_once',
      ],
    );
  }
}

Future<AcpSession> _pairAcpWait(
  WidgetTester tester,
  ProviderContainer container,
  String agentDid,
  bool Function(AcpSession) predicate,
) async {
  AcpSession? found;
  try {
    await _pumpUntil(
      tester,
      () {
        for (final s in container.read(acpSessionsProvider).sessions.values) {
          if (s.agentDid == agentDid && !s.group && predicate(s)) {
            found = s;
            return true;
          }
        }
        return false;
      },
      timeout: const Duration(minutes: 3),
      failure: 'ACP committed state did not converge on a real App.',
    );
  } on TestFailure {
    final sessions = container
        .read(acpSessionsProvider)
        .sessions
        .values
        .where((s) => s.agentDid == agentDid && !s.group)
        .toList();
    final delivery = await codingAgentDeliveryDiagnostics(
      container.read(messagingServiceProvider),
      agentDid,
    );
    final messages = container.read(messagingServiceProvider);
    final controls = await (messages as CommittedControlMessagingService)
        .repairControlThreadStore(AppThreadRef.direct(agentDid));
    final conversations = container
        .read(conversationListProvider)
        .conversations
        .where((c) => c.targetDid == agentDid)
        .toList();
    fail(
      'ACP committed state did not converge: ${jsonEncode({
        'lifecycle': tester.binding.lifecycleState?.name,
        'sessions': [
          for (final s in sessions) {'revision': s.revision, 'busy': s.busy, 'waiting': s.waiting.isNotEmpty, 'question_count': s.questions.length, 'history_states': s.history.map((t) => t['state']).toList(), 'error_code': s.data['error_code']},
        ],
        'delivery': delivery,
        'conversation_count': conversations.length,
        'acp_projection_inputs': codingAgentAcpProjectionSummary([...controls.messages, if (controls.message != null) controls.message!], conversations.map((c) => c.conversationId).toSet()),
      })}',
    );
  }
  return found!;
}

Future<void> _pairAcpWaitSent(
  WidgetTester tester,
  MessagingService messages,
  String agentDid,
  String prompt,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final history = await messages.loadHistory(
      AppThreadRef.direct(agentDid),
      limit: 60,
    );
    final matches = history
        .where((m) => m.isMine && m.content == prompt)
        .toList();
    expect(matches.length, lessThanOrEqualTo(1));
    if (matches.length == 1 &&
        matches.single.sendState == MessageSendState.sent &&
        matches.single.remoteId?.isNotEmpty == true) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
  fail(
    'ACP question prompt was not committed exactly once by the sending App.',
  );
}

String _pairAcpDraft(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.bySemanticsIdentifier('e2e-chat-input'),
        matching: find.byType(EditableText),
        matchRoot: true,
      ),
    )
    .controller
    .text;
Future<void> _pairAcpEnter(WidgetTester tester, String content) async {
  expect(
    tester.binding.lifecycleState,
    isNot(AppLifecycleState.hidden),
    reason: 'Keep both real App windows visible while driving their UI.',
  );
  final input = find.bySemanticsIdentifier('e2e-chat-input');
  await tester.ensureVisible(input);
  await tester.tap(input);
  await enterStableCodingAgentText(
    expected: content,
    enter: () async {
      await tester.enterText(input, content);
      await tester.pump(const Duration(milliseconds: 200));
    },
    read: () => _pairAcpDraft(tester),
  );
}

Future<void> _pairAcpSend(WidgetTester tester, String content) async {
  await _pairAcpEnter(tester, content);
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('e2e-chat-send-button'),
    failure: 'ACP send unavailable.',
  );
}

Future<ChatMessage> _pairAcpFinal(
  WidgetTester tester,
  MessagingService messaging,
  String agentDid,
  List<String> endings,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(deadline)) {
    final messages = await messaging.loadHistory(
      AppThreadRef.direct(agentDid),
      limit: 60,
    );
    final matches = messages
        .where(
          (m) =>
              !m.isMine &&
              m.senderDid == agentDid &&
              endings.any((ending) => m.content.trimRight().endsWith(ending)),
        )
        .toList();
    expect(matches.length, lessThanOrEqualTo(1));
    if (matches.length == 1) {
      final result = matches.single;
      expect(result.remoteId?.trim().isNotEmpty, isTrue);
      expect(result.sendState, MessageSendState.sent);
      await _pumpUntil(
        tester,
        () => find
            .bySemanticsIdentifier(e2eMessageIdentifier(result.content))
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 45),
        failure: 'ACP final was absent from the visible chat.',
      );
      return result;
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
  throw StateError('No exact ACP final message reached this App.');
}
