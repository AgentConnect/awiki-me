import 'dart:io';

import '../../harness/src/agent_im_config.dart';
import '../../harness/src/cli_peer_adapter.dart';
import '../../harness/src/redaction_scan.dart';
import '../../harness/src/remote_adapter.dart';
import '../../harness/src/secret_redactor.dart';
import 'app_bootstrap_scenario.dart';

typedef AgentImCliPeerFlow = Future<AgentImCliPeerFlowResult> Function();

final class AgentImDelegatedMessageScenario {
  AgentImDelegatedMessageScenario({
    required this.config,
    AgentImAppBootstrapScenario? appBootstrapScenario,
    this.scanner = const AgentImRedactionScanner(),
    this.redactor = const SecretRedactor(),
  }) : appBootstrapScenario =
           appBootstrapScenario ?? AgentImAppBootstrapScenario();

  final AgentImDelegatedConfig config;
  final AgentImAppBootstrapScenario appBootstrapScenario;
  final AgentImRedactionScanner scanner;
  final SecretRedactor redactor;

  Future<AgentImDelegatedMessageScenarioResult> run({
    required String runId,
    required String platform,
    required bool dryRun,
    required Directory reportDir,
    required Directory cliWorkspaceDir,
    required List<RemoteEvidenceCommand> remoteCommands,
    AgentImCliPeerFlow? cliPeerFlow,
  }) async {
    AgentImAppBootstrapScenarioResult? bootstrapResult;
    AgentImCliPeerFlowResult? cliResult;
    Object? appError;
    Object? cliError;

    if (!dryRun) {
      try {
        bootstrapResult = await appBootstrapScenario.run(
          runId: runId,
          userHandle: config.accounts.appUser.handle,
        );
      } catch (error) {
        appError = error;
      }
      if (cliPeerFlow == null) {
        cliError = StateError('CLI peer flow was not configured.');
      } else {
        try {
          cliResult = await cliPeerFlow();
        } catch (error) {
          cliError = error;
        }
      }
    }

    final scanResult = scanner.scanReportAndLogs(
      reportDir: reportDir,
      cliWorkspaceDir: cliWorkspaceDir,
    );
    final cases = _cases(
      dryRun: dryRun,
      bootstrapResult: bootstrapResult,
      cliResult: cliResult,
      appError: appError,
      cliError: cliError,
      scanResult: scanResult,
      remoteCommands: remoteCommands,
    );

    return AgentImDelegatedMessageScenarioResult(
      runId: runId,
      platform: platform,
      dryRun: dryRun,
      appBootstrapReport: bootstrapResult?.report,
      cliPeerResult: cliResult?.toJson(),
      remoteCommands: [for (final command in remoteCommands) command.toJson()],
      redactionScan: scanResult,
      cases: cases,
      redactor: redactor,
    );
  }

  List<AgentImScenarioCaseResult> _cases({
    required bool dryRun,
    required AgentImAppBootstrapScenarioResult? bootstrapResult,
    required AgentImCliPeerFlowResult? cliResult,
    required Object? appError,
    required Object? cliError,
    required AgentImRedactionScanResult scanResult,
    required List<RemoteEvidenceCommand> remoteCommands,
  }) {
    final cases = <AgentImScenarioCaseResult>[];
    if (dryRun) {
      cases.addAll(<AgentImScenarioCaseResult>[
        AgentImScenarioCaseResult.skipped(
          id: 'AIM-E2E-001',
          priority: 'P0',
          title: 'Happy Path 普通消息委托处理',
          reason:
              'dry-run 只生成 App bootstrap、CLI peer 和 remote evidence 计划，不执行真实 App/CLI/Daemon/Hermes 链路。',
          evidence: <String>['scenario-plan.json', 'cli-peer-plan.json'],
        ),
        AgentImScenarioCaseResult.skipped(
          id: 'AIM-E2E-002',
          priority: 'P0',
          title: 'Bootstrap 幂等',
          reason: 'dry-run 未向 Daemon 重发 bootstrap，幂等证据留给真实 E2E / Step 06。',
        ),
      ]);
    } else {
      final appOk =
          bootstrapResult?.sentBootstrapPayload == true &&
          bootstrapResult?.bootstrapHiddenFromChat == true;
      final cliOk = cliResult != null;
      if (appError != null || cliError != null) {
        cases.add(
          AgentImScenarioCaseResult.failed(
            id: 'AIM-E2E-001',
            priority: 'P0',
            title: 'Happy Path 普通消息委托处理',
            reason: _joinReasons(<Object?>[
              if (appError != null) 'App bootstrap failed: $appError',
              if (cliError != null) 'CLI peer send failed: $cliError',
            ]),
            evidence: <String>[
              if (bootstrapResult != null) 'app bootstrap payload sent',
              if (cliResult != null) 'cli-peer-result.json',
            ],
          ),
        );
      } else if (appOk && cliOk) {
        cases.add(
          AgentImScenarioCaseResult.skipped(
            id: 'AIM-E2E-001',
            priority: 'P0',
            title: 'Happy Path 普通消息委托处理',
            reason:
                'App bootstrap smoke 与 CLI ordinary send 已执行；Daemon/Hermes 处理和 App summary/status 远端证据需 Step 06 通过 ssh ali 收口后才能判定 full pass。',
            evidence: <String>[
              'App bootstrap sent hidden awiki.daemon.bootstrap.v1 payload',
              'cli-peer-result.json',
              if (remoteCommands.isNotEmpty) 'remote evidence commands planned',
            ],
          ),
        );
      } else {
        cases.add(
          AgentImScenarioCaseResult.failed(
            id: 'AIM-E2E-001',
            priority: 'P0',
            title: 'Happy Path 普通消息委托处理',
            reason:
                'App bootstrap or CLI send did not produce the expected local evidence.',
          ),
        );
      }

      final idempotencyKey = bootstrapResult?.sentIdempotencyKey;
      cases.add(
        idempotencyKey == null
            ? AgentImScenarioCaseResult.failed(
                id: 'AIM-E2E-002',
                priority: 'P0',
                title: 'Bootstrap 幂等',
                reason: 'App bootstrap did not expose an idempotency key.',
              )
            : AgentImScenarioCaseResult.skipped(
                id: 'AIM-E2E-002',
                priority: 'P0',
                title: 'Bootstrap 幂等',
                reason:
                    'App 侧已生成稳定 message-agent-bootstrap idempotency key；Daemon runtime/message agent 去重证据需 Step 06 远端 agent registry/log 验证。',
                evidence: <String>['idempotencyKey=$idempotencyKey'],
              ),
      );
    }

    cases.add(
      scanResult.passed
          ? AgentImScenarioCaseResult.passed(
              id: 'AIM-E2E-006',
              priority: 'P1',
              title: '私钥与 token 泄漏检查',
              evidence: <String>[
                'redaction scan passed for ${scanResult.scannedFiles} report/log files',
              ],
            )
          : AgentImScenarioCaseResult.failed(
              id: 'AIM-E2E-006',
              priority: 'P1',
              title: '私钥与 token 泄漏检查',
              reason:
                  'redaction scan found ${scanResult.findings.length} sensitive matches',
              evidence: <String>[
                for (final finding in scanResult.findings)
                  '${finding.type}: ${finding.path}',
              ],
            ),
    );

    cases.addAll(<AgentImScenarioCaseResult>[
      AgentImScenarioCaseResult.skipped(
        id: 'AIM-E2E-003',
        priority: 'P0',
        title: 'Daemon 重启恢复',
        reason: '本步骤只建立首批场景骨架；Daemon restart/cursor 验证需要可控远端窗口或独立测试环境。',
      ),
      AgentImScenarioCaseResult.skipped(
        id: 'AIM-E2E-004',
        priority: 'P1',
        title: 'E2EE opaque 不进入 Agent',
        reason: 'MVP 只验证普通非 E2EE 消息进入 Agent；E2EE opaque 作为后续扩展入口保留。',
      ),
      AgentImScenarioCaseResult.skipped(
        id: 'AIM-E2E-005',
        priority: 'P1',
        title: 'Delegated key 撤销',
        reason:
            '需要 User Service DID Document 更新/撤销和 Message Service delegated proof 远端证据，留给后续服务侧联调。',
      ),
      AgentImScenarioCaseResult.skipped(
        id: 'AIM-E2E-007',
        priority: 'P1',
        title: '未知 awiki.* payload 可见性',
        reason: '未知 payload 注入与 App reducer/Daemon dispatch 组合验证不阻塞首批普通消息路径。',
      ),
    ]);
    return cases;
  }
}

final class AgentImDelegatedMessageScenarioResult {
  const AgentImDelegatedMessageScenarioResult({
    required this.runId,
    required this.platform,
    required this.dryRun,
    required this.appBootstrapReport,
    required this.cliPeerResult,
    required this.remoteCommands,
    required this.redactionScan,
    required this.cases,
    required this.redactor,
  });

  final String runId;
  final String platform;
  final bool dryRun;
  final Map<String, Object?>? appBootstrapReport;
  final Map<String, Object?>? cliPeerResult;
  final List<Map<String, Object?>> remoteCommands;
  final AgentImRedactionScanResult redactionScan;
  final List<AgentImScenarioCaseResult> cases;
  final SecretRedactor redactor;

  bool get hasBlockingFailure => cases.any((item) => item.status == 'fail');

  Map<String, int> get counts {
    final result = <String, int>{'pass': 0, 'fail': 0, 'skipped': 0};
    for (final item in cases) {
      result[item.status] = (result[item.status] ?? 0) + 1;
    }
    return result;
  }

  Map<String, Object?> toJson() {
    return redactor.redactJson(<String, Object?>{
          'runId': runId,
          'platform': platform,
          'dryRun': dryRun,
          'counts': counts,
          'appBootstrapReport': appBootstrapReport,
          'cliPeerResult': cliPeerResult,
          'remoteCommands': remoteCommands,
          'redactionScan': redactionScan.toJson(),
          'cases': [for (final item in cases) item.toJson()],
        })
        as Map<String, Object?>;
  }
}

final class AgentImScenarioCaseResult {
  const AgentImScenarioCaseResult({
    required this.id,
    required this.priority,
    required this.title,
    required this.status,
    this.evidence = const <String>[],
    this.reason,
  });

  factory AgentImScenarioCaseResult.passed({
    required String id,
    required String priority,
    required String title,
    List<String> evidence = const <String>[],
  }) => AgentImScenarioCaseResult(
    id: id,
    priority: priority,
    title: title,
    status: 'pass',
    evidence: evidence,
  );

  factory AgentImScenarioCaseResult.failed({
    required String id,
    required String priority,
    required String title,
    required String reason,
    List<String> evidence = const <String>[],
  }) => AgentImScenarioCaseResult(
    id: id,
    priority: priority,
    title: title,
    status: 'fail',
    reason: reason,
    evidence: evidence,
  );

  factory AgentImScenarioCaseResult.skipped({
    required String id,
    required String priority,
    required String title,
    required String reason,
    List<String> evidence = const <String>[],
  }) => AgentImScenarioCaseResult(
    id: id,
    priority: priority,
    title: title,
    status: 'skipped',
    reason: reason,
    evidence: evidence,
  );

  final String id;
  final String priority;
  final String title;
  final String status;
  final List<String> evidence;
  final String? reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'priority': priority,
    'title': title,
    'status': status,
    'evidence': evidence,
    if (reason != null) 'reason': reason,
  };
}

String _joinReasons(List<Object?> values) => values
    .whereType<String>()
    .where((value) => value.trim().isNotEmpty)
    .join('; ');
