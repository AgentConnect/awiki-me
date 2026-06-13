import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../e2e_test/scenarios/agent_im_delegated_message/app_bootstrap_scenario.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Agent IM App bootstrap scenario sends hidden control payload', (
    _,
  ) async {
    final result = await AgentImAppBootstrapScenario().run(
      runId: 'integration-agent-im-bootstrap',
    );

    expect(result.sentBootstrapPayload, isTrue);
    expect(result.sentIdempotencyKey, startsWith('message-agent-bootstrap:'));
    expect(result.runtimeTokenIssued, isTrue);
    expect(result.bootstrapHiddenFromChat, isTrue);
    expect(result.messageSyncDetected, isTrue);
    expect(result.actionResultDetected, isTrue);
    expect(result.privatePackageExcludedFromReport, isTrue);
    expect(jsonEncode(result.report), isNot(contains('fixture-runtime-token')));
  });
}
