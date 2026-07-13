import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AgentRunStatus preserves structured runtime progress', () {
    final status = AgentRunStatus.fromJson(<String, Object?>{
      'run_id': 'run_1',
      'message_id': 'message_1',
      'runtime_agent_did': 'did:agent:runtime',
      'status': 'running',
      'progress': <String, Object?>{
        'code': 'external_service_delayed',
        'phase': 'external_tool',
        'state': 'delayed',
        'tool': 'web_search',
        'retryable': true,
      },
    });

    expect(status.progress?.code, 'external_service_delayed');
    expect(status.progress?.phase, 'external_tool');
    expect(status.progress?.state, 'delayed');
    expect(status.progress?.tool, 'web_search');
    expect(status.progress?.retryable, isTrue);
    expect(status.toJson()['progress'], <String, Object?>{
      'code': 'external_service_delayed',
      'phase': 'external_tool',
      'state': 'delayed',
      'tool': 'web_search',
      'retryable': true,
    });
  });

  test('AgentRunStatus ignores incomplete progress metadata', () {
    final status = AgentRunStatus.fromJson(<String, Object?>{
      'run_id': 'run_1',
      'message_id': 'message_1',
      'runtime_agent_did': 'did:agent:runtime',
      'status': 'running',
      'progress': <String, Object?>{
        'code': 'external_service_delayed',
        'state': 'delayed',
      },
    });

    expect(status.progress, isNull);
  });
}
