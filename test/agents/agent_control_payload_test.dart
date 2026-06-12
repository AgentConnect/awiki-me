import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('status payload schema is decoded and recognized as control', () {
    const payload =
        '{"schema":"awiki.agent.status.v1","status_scope":"daemon","daemon":{"status":"ready"}}';

    final decoded = AgentControlPayloads.decode(payload);

    expect(decoded?['schema'], AgentControlPayloads.statusSchema);
    expect(decoded?['status_scope'], 'daemon');
    expect(AgentControlPayloads.isStatus(payload), isTrue);
    expect(AgentControlPayloads.isControl(payload), isTrue);
  });

  test('malformed and non-control payloads are ignored', () {
    expect(AgentControlPayloads.decode('not-json'), isNull);
    expect(AgentControlPayloads.decode('["not","a","map"]'), isNull);
    expect(
      AgentControlPayloads.isControl('{"schema":"text.message"}'),
      isFalse,
    );
  });

  test('daemon bootstrap and app action schemas are hidden controls', () {
    const schemas = <String>[
      AgentControlPayloads.daemonBootstrapSchema,
      AgentControlPayloads.messageSyncSchema,
      AgentControlPayloads.appCapabilitiesSchema,
      AgentControlPayloads.appActionSchema,
      AgentControlPayloads.appActionResultSchema,
      AgentControlPayloads.notificationSchema,
      'awiki.future.system.v1',
    ];

    for (final schema in schemas) {
      final payload = '{"schema":"$schema"}';
      expect(AgentControlPayloads.isControl(payload), isTrue, reason: schema);
    }
  });

  test('app action capabilities expose MVP allowlist only', () {
    const payload =
        '{"schema":"awiki.app.capabilities.v1","capabilities":["message.summarize_plain","contact.update_note","message.send","message.e2ee_forward"],"require_confirmation_for_write_actions":true}';

    final capabilities = AgentControlPayloads.decodeAppCapabilities(payload);

    expect(capabilities, isNotNull);
    expect(capabilities!.allowedMvpCapabilities, <String>[
      'message.summarize_plain',
      'contact.update_note',
    ]);
    expect(AgentControlPayloads.isAllowedAppAction('message.send'), isFalse);
    expect(
      AgentControlPayloads.isAllowedAppAction('message.e2ee_forward'),
      isFalse,
    );
  });

  test('app action request parses contact write confirmation state', () {
    const payload =
        '{"schema":"awiki.app.action.v1","action_id":"act_1","action":"contact.update_note","state":"requires_confirmation","requires_confirmation":true,"args":{"contact_did":"did:human:bob","note":"Follow up"}}';

    final request = AgentControlPayloads.decodeAppAction(payload);

    expect(request, isNotNull);
    expect(request!.actionId, 'act_1');
    expect(request.action, 'contact.update_note');
    expect(request.isAllowedInMvp, isTrue);
    expect(request.needsUserConfirmation, isTrue);
    expect(
      AgentControlPayloads.requiresAppActionConfirmation(request.action),
      isTrue,
    );
    expect(request.args['contact_did'], 'did:human:bob');
  });

  test('app action parser rejects private state payloads', () {
    const payload =
        '{"schema":"awiki.app.action.v1","action_id":"act_secret","action":"message.create_draft","args":{"private_key":"secret"}}';

    expect(AgentControlPayloads.decodeAppAction(payload), isNull);
  });

  test('app action result reducer updates terminal state', () {
    const request =
        '{"schema":"awiki.app.action.v1","action_id":"act_draft","action":"message.create_draft","state":"requested","args":{"source_message_id":"msg_1"}}';
    const result =
        '{"schema":"awiki.app.action.result.v1","action_id":"act_draft","action":"message.create_draft","state":"succeeded","result":{"draft_text":"Looks good"}}';

    final afterRequest = AppActionReducer.reducePayloadJson(
      const <String, AppActionRecord>{},
      request,
    );
    final afterResult = AppActionReducer.reducePayloadJson(
      afterRequest,
      result,
    );

    expect(afterRequest['act_draft']?.state, appActionStateRequested);
    expect(afterResult['act_draft']?.state, appActionStateSucceeded);
    expect(afterResult['act_draft']?.isTerminal, isTrue);
    expect(
      afterResult['act_draft']?.result?.result['draft_text'],
      'Looks good',
    );
  });

  test('message sync schema decodes as hidden system payload', () {
    const payload =
        '{"schema":"awiki.message.sync.v1","kind":"runtime_final","message_id":"msg_1"}';

    final sync = AgentControlPayloads.decodeMessageSync(payload);

    expect(sync, isNotNull);
    expect(sync!.payload['kind'], 'runtime_final');
    expect(AgentControlPayloads.isControl(payload), isTrue);
  });

  test('runtime create command carries token in args only', () {
    final payload = runtimeAgentCreatePayload(
      controllerDid: 'did:human:alice',
      registrationToken: 'runtime-token',
      clientRequestId: 'app_req_1',
      handle: 'alice-hermes',
      displayName: 'Alice Hermes',
    );

    expect(payload['schema'], AgentControlPayloads.commandSchema);
    expect(payload['command'], 'runtime.agent.create');
    expect(payload['target_agent_kind'], 'runtime');
    final args = payload['args'] as Map<String, Object?>;
    expect(args['runtime'], 'hermes');
    expect(args['controller_did'], 'did:human:alice');
    expect(args['registration_token'], 'runtime-token');
    expect(args['handle'], 'alice-hermes');
    expect(args['display_name'], 'Alice Hermes');
    expect(args['client_request_id'], 'app_req_1');
  });

  test('runtime create command allows explicit test runtime', () {
    final payload = runtimeAgentCreatePayload(
      controllerDid: 'did:human:alice',
      registrationToken: 'runtime-token',
      clientRequestId: 'app_req_1',
      runtime: 'test-runtime-uds',
      displayName: 'System Test',
      handle: 'alice-runtime',
      workspace: '/tmp/awiki-runtime',
    );

    final args = payload['args'] as Map<String, Object?>;
    expect(args['runtime'], 'test-runtime-uds');
    expect(args['display_name'], 'System Test');
    expect(args['handle'], 'alice-runtime');
    expect(args['workspace'], '/tmp/awiki-runtime');
  });

  test('runtime task submit command carries target runtime and text', () {
    final payload = runtimeTaskSubmitPayload(
      runtimeAgentDid: 'did:agent:runtime',
      text: 'run the system test runtime',
      commandId: 'cmd_task',
      taskId: 'task_1',
      conversationId: 'conv_1',
    );

    expect(payload['schema'], AgentControlPayloads.commandSchema);
    expect(payload['command'], 'runtime.task.submit');
    expect(payload['target_agent_did'], 'did:agent:runtime');
    expect(payload['command_id'], 'cmd_task');
    expect(payload['task_id'], 'task_1');
    expect(payload['conversation_id'], 'conv_1');
    final args = payload['args'] as Map<String, Object?>;
    expect(args['text'], 'run the system test runtime');
    expect(args.containsKey('prompt'), isFalse);
  });

  test('runtime retry command references a run id without prompt text', () {
    final payload = runtimeRunRetryPayload(
      runtimeAgentDid: 'did:agent:runtime',
      runId: 'run_123',
    );

    expect(payload['schema'], AgentControlPayloads.commandSchema);
    expect(payload['command'], 'runtime.run.retry');
    final args = payload['args'] as Map<String, Object?>;
    expect(args['runtime_agent_did'], 'did:agent:runtime');
    expect(args['run_id'], 'run_123');
    expect(args.containsKey('prompt'), isFalse);
    expect(args.containsKey('text'), isFalse);
  });

  test('runtime inbox commands target daemon and carry pagination fields', () {
    final listPayload = runtimeInboxQueryPayload(
      runtimeAgentDid: 'did:agent:runtime',
      scope: 'group',
      limit: 20,
      cursor: '40',
      commandId: 'cmd_inbox',
    );
    expect(listPayload['command'], 'runtime.inbox.query');
    expect(listPayload['target_agent_kind'], 'daemon');
    expect(listPayload['command_id'], 'cmd_inbox');
    final listArgs = listPayload['args'] as Map<String, Object?>;
    expect(listArgs['runtime_agent_did'], 'did:agent:runtime');
    expect(listArgs['scope'], 'group');
    expect(listArgs['limit'], 20);
    expect(listArgs['cursor'], '40');

    final threadPayload = runtimeInboxThreadQueryPayload(
      runtimeAgentDid: 'did:agent:runtime',
      threadId: 'group:did:group:team',
      kind: 'group',
      groupDid: 'did:group:team',
      commandId: 'cmd_thread',
    );
    expect(threadPayload['command'], 'runtime.inbox.thread.query');
    expect(threadPayload['target_agent_kind'], 'daemon');
    final threadArgs = threadPayload['args'] as Map<String, Object?>;
    expect(threadArgs['thread_id'], 'group:did:group:team');
    expect(threadArgs['kind'], 'group');
    expect(threadArgs['group_did'], 'did:group:team');

    final directThreadPayload = runtimeInboxThreadQueryPayload(
      runtimeAgentDid: 'did:agent:runtime',
      threadId: 'dm:peer-scope:v1:bob',
      kind: 'direct',
      peerDid: 'did:human:bob-current',
      peerHandle: 'bob.anpclaw.com',
      commandId: 'cmd_direct_thread',
    );
    final directThreadArgs =
        directThreadPayload['args'] as Map<String, Object?>;
    expect(directThreadArgs['thread_id'], 'dm:peer-scope:v1:bob');
    expect(directThreadArgs['peer_did'], 'did:human:bob-current');
    expect(directThreadArgs['peer_handle'], 'bob.anpclaw.com');
  });

  test('agent inventory summary maps daemon install inventory fields', () {
    final summary = AgentSummary.fromJson(<String, Object?>{
      'agent_did': 'did:wba:agent.example:agent:daemon:e1_daemon',
      'agent_kind': 'daemon',
      'handle': 'alice-daemon',
      'display_name': 'Alice Daemon',
      'active_state': 'active',
      'status': <String, Object?>{
        'status': 'ready',
        'service': 'foreground',
        'diagnostics_summary': <String, Object?>{
          'installation_status': 'not_installed',
          'runner_status': 'not_running',
          'config_summary': <String, Object?>{'service_installed': false},
        },
      },
    });

    expect(summary.isDaemon, isTrue);
    expect(summary.agentDid, 'did:wba:agent.example:agent:daemon:e1_daemon');
    expect(summary.handle, 'alice-daemon');
    expect(summary.displayName, 'Alice Daemon');
    expect(summary.activeState, 'active');
    expect(summary.latest.status, 'ready');
    expect(summary.latest.service, 'foreground');
    expect(
      summary.latest.diagnosticsSummary['installation_status'],
      'not_installed',
    );
    expect(
      (summary.latest.diagnosticsSummary['config_summary']
          as Map<String, Object?>)['service_installed'],
      isFalse,
    );
  });
}
