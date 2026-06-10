import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
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

  test('runtime create command carries token in args only', () {
    final payload = runtimeAgentCreatePayload(
      controllerDid: 'did:human:alice',
      registrationToken: 'runtime-token',
      clientRequestId: 'app_req_1',
    );

    expect(payload['schema'], AgentControlPayloads.commandSchema);
    expect(payload['command'], 'runtime.agent.create');
    expect(payload['target_agent_kind'], 'runtime');
    final args = payload['args'] as Map<String, Object?>;
    expect(args['runtime'], 'hermes');
    expect(args['controller_did'], 'did:human:alice');
    expect(args['registration_token'], 'runtime-token');
    expect(args['client_request_id'], 'app_req_1');
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
}
