import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e_test/scenarios/agent_im_delegated_message/app_bootstrap_scenario.dart';

void main() {
  test(
    'Agent IM app bootstrap scenario uses production service and safe report',
    () async {
      final result = await AgentImAppBootstrapScenario().run(
        runId: 'unit-agent-im-bootstrap',
      );

      expect(result.sentBootstrapPayload, isTrue);
      expect(result.sentIdempotencyKey, startsWith('message-agent-bootstrap:'));
      expect(result.runtimeTokenIssued, isTrue);
      expect(result.bootstrapHiddenFromChat, isTrue);
      expect(result.messageSyncDetected, isTrue);
      expect(result.actionResultDetected, isTrue);
      expect(result.privatePackageExcludedFromReport, isTrue);

      final reportJson = jsonEncode(result.report);
      expect(reportJson, contains('<REDACTED_PRIVATE_PACKAGE>'));
      expect(
        reportJson,
        isNot(contains('fixture-private-daemon-key-do-not-log')),
      );
      expect(reportJson, isNot(contains('fixture-runtime-token')));
    },
  );
}
