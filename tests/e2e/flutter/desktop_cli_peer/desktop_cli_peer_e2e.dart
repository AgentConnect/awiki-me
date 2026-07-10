library desktop_cli_peer_e2e;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/attachment_open_service.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/group_application_service.dart';
import 'package:awiki_me/src/application/message_sync_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/app_conversation_read_ref.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_read_watermark.dart';
import 'package:awiki_me/src/application/models/conversation_patch.dart';
import 'package:awiki_me/src/application/models/thread_message_patch.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
import 'package:awiki_me/src/application/ports/relationship_core_port.dart';
import 'package:awiki_me/src/application/relationship_application_service.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, Key, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import '../../case_attestation.dart';
import 'support/ui_oracles.dart';

part 'flows/attachment_flow.dart';
part 'flows/contact_flow.dart';
part 'flows/direct_message_flow.dart';
part 'flows/group_message_flow.dart';
part 'flows/performance_flow.dart';
part 'support/cli_peer_process.dart';
part 'support/config.dart';
part 'support/polling.dart';
part 'support/ui_robot.dart';

const String _desktopCliPeerRunConfigPath =
    '.e2e/desktop-cli-peer/current/run_config.json';

enum DesktopCliPeerIntegrationCase {
  full,
  direct,
  group,
  attachment,
  contacts,
  performance;

  static DesktopCliPeerIntegrationCase parse(String value) {
    return switch (value.trim().toLowerCase()) {
      '' || 'full' => DesktopCliPeerIntegrationCase.full,
      'direct' ||
      'dm' ||
      'message' ||
      'messages' ||
      'direct-only' => DesktopCliPeerIntegrationCase.direct,
      'group' ||
      'groups' ||
      'group-only' => DesktopCliPeerIntegrationCase.group,
      'attachment' ||
      'attachments' ||
      'file' ||
      'files' ||
      'attachment-only' => DesktopCliPeerIntegrationCase.attachment,
      'contact' ||
      'contacts' ||
      'people' ||
      'follow' ||
      'contact-only' => DesktopCliPeerIntegrationCase.contacts,
      'performance' ||
      'perf' ||
      'startup-performance' ||
      'startup_performance' ||
      'conversation-performance' ||
      'conversation_performance' => DesktopCliPeerIntegrationCase.performance,
      _ => throw StateError(
        'Unsupported Desktop CLI peer E2E case "$value". '
        'Use full, performance, direct, group, attachment, or contacts.',
      ),
    };
  }

  bool get runsDirectText =>
      this == DesktopCliPeerIntegrationCase.full ||
      this == DesktopCliPeerIntegrationCase.direct;

  bool get runsGroup =>
      this == DesktopCliPeerIntegrationCase.full ||
      this == DesktopCliPeerIntegrationCase.group;

  bool get runsAttachment =>
      this == DesktopCliPeerIntegrationCase.full ||
      this == DesktopCliPeerIntegrationCase.attachment;

  bool get runsContacts =>
      this == DesktopCliPeerIntegrationCase.full ||
      this == DesktopCliPeerIntegrationCase.contacts;

  bool get runsPerformance => this == DesktopCliPeerIntegrationCase.performance;
}

DesktopCliPeerIntegrationCase desktopCliPeerCaseFromRunConfig() =>
    _DesktopCliPeerSmokeConfig.tryLoad()?.e2eCase ??
    DesktopCliPeerIntegrationCase.full;

void runDesktopCliPeerE2e({
  required DesktopCliPeerIntegrationCase selectedCase,
  String description =
      'Desktop App and CLI peer cover direct, group, and attachment basics',
}) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    description,
    (tester) async {
      final config = _DesktopCliPeerSmokeConfig.load();
      final performanceWarmup = config.e2eCase.runsPerformance
          ? await _warmPerformanceLocalConversationState(config)
          : null;
      final appCreateWatch = Stopwatch()..start();
      final bootstrap = await AppBootstrap.create(
        environment: config.environment,
        appStateRoot: config.appStateRoot,
      );
      appCreateWatch.stop();
      final preparedSession = selectedCase.runsPerformance
          ? null
          : await _prepareAppIdentity(bootstrap.onboardingService!, config);
      final countingConversations = config.e2eCase.runsPerformance
          ? _CountingConversationService(bootstrap.conversationService!)
          : null;
      final faultMessaging = preparedSession == null
          ? null
          : _FailOnceMessagingService(
              delegate: bootstrap.messagingService!,
              ownerDid: preparedSession.did,
            );
      final attachmentOpenRecorder = _RecordingAttachmentOpenService();
      final appProviderOverrides = <Override>[
        if (countingConversations != null)
          conversationServiceProvider.overrideWithValue(countingConversations),
        if (faultMessaging != null)
          messagingServiceProvider.overrideWithValue(faultMessaging),
        attachmentOpenServiceProvider.overrideWithValue(attachmentOpenRecorder),
      ];
      addTearDown(() async {
        await bootstrap.appSessionService?.logout();
      });

      final shellWatch = Stopwatch()..start();
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: appProviderOverrides,
        ),
      );
      await tester.pumpAndSettle();
      shellWatch.stop();
      expect(find.byType(AppShell), findsOneWidget);

      final session = selectedCase.runsPerformance
          ? await _preparePerformanceAppIdentity(
              bootstrap: bootstrap,
              config: config,
              warmup: performanceWarmup!,
            )
          : preparedSession!;
      expect(session.authenticated, isTrue);
      final robot = _DesktopAppRobot(tester);
      await robot.activate(session);
      if (!selectedCase.runsPerformance) {
        await E2eCaseAttestationWriter.markPassed(
          'AUTH-E2E-001',
          phases: const <String>[
            'app_identity_prepared',
            'authenticated_app_shell_visible',
          ],
        );
      }

      final messaging = bootstrap.messagingService!;
      final messageNonce = _messageNonce();
      final directThread = AppThreadRef.direct(config.cliHandle);

      if (selectedCase.runsPerformance) {
        await _verifyPerformanceRegression(
          tester: tester,
          bootstrapCreateElapsed: appCreateWatch.elapsed,
          shellVisibleElapsed: shellWatch.elapsed,
          warmup: performanceWarmup!,
          messaging: messaging,
          messageSync: bootstrap.messageSyncService!,
          conversations: countingConversations!,
          thread: directThread,
          ownerDid: session.did,
          config: config,
          nonce: messageNonce,
        );
        await _attestPassedCases(<String, List<String>>{
          'PERF-E2E-001': const <String>['real_backend_flow_completed'],
          'PERF-E2E-002': const <String>['multi_conversation_dataset_verified'],
          'PERF-E2E-003': const <String>['cold_shell_visibility_measured'],
          'PERF-E2E-004': const <String>[
            'snapshot_and_hydration_timings_verified',
          ],
          'PERF-E2E-005': const <String>['app_to_cli_latency_measured'],
          'PERF-E2E-006': const <String>['cli_to_app_latency_measured'],
          'PERF-E2E-007': const <String>['full_refresh_regression_checked'],
          'PERF-E2E-008': const <String>['long_thread_open_timing_measured'],
          'PERF-E2E-009': const <String>['product_timing_schema_written'],
          'PERF-E2E-010': const <String>['hard_budget_semantics_checked'],
          'PERF-E2E-011': const <String>['soft_budget_semantics_checked'],
          'PERF-E2E-012': const <String>['failure_diagnostics_retained'],
        });
        return;
      }

      if (selectedCase.runsDirectText) {
        final conversations = bootstrap.conversationService!;
        await _verifyDirectTextRegression(
          robot: robot,
          messaging: faultMessaging!,
          conversations: conversations,
          thread: directThread,
          ownerDid: session.did,
          session: session,
          bootstrap: bootstrap,
          providerOverrides: appProviderOverrides,
          config: config,
          nonce: messageNonce,
        );
        await _attestPassedCases(<String, List<String>>{
          'MSG-E2E-001': const <String>[
            'app_ui_send_terminal_sent',
            'cli_inbox_canonical_exact_one_verified',
          ],
          'MSG-E2E-002': const <String>[
            'cli_send_accepted',
            'app_ui_unread_exact_increment_and_read_clear',
          ],
          'MSG-REG-001': const <String>[
            'failure_retry_ui_verified',
            'reconnect_restart_exact_one_verified',
          ],
        });
      }

      if (selectedCase.runsContacts) {
        final relationships = bootstrap.relationshipApplicationService!;
        await _verifyContactRegression(
          robot: robot,
          relationships: relationships,
          config: config,
        );
        await _attestPassedCases(<String, List<String>>{
          'CONTACT-E2E-001': const <String>[
            'app_ui_follow_clicked',
            'exact_following_state_observed',
          ],
          'CONTACT-E2E-002': const <String>[
            'cli_follow_completed',
            'app_ui_unfollow_confirmed',
          ],
          'CONTACT-REG-001': const <String>[
            'exact_friend_follower_none_transitions_checked',
          ],
        });
      }

      if (selectedCase.runsGroup) {
        final groups = bootstrap.groupApplicationService!;
        await _verifyGroupTextRegression(
          robot: robot,
          groups: groups,
          messaging: faultMessaging!,
          ownerDid: session.did,
          config: config,
          nonce: messageNonce,
        );
        await _attestPassedCases(<String, List<String>>{
          'GROUP-E2E-001': const <String>[
            'group_created_and_member_added_through_ui',
            'app_group_ui_send_exact_one_verified',
          ],
          'GROUP-E2E-002': const <String>['cli_group_send_verified_in_app_ui'],
          'GROUP-P9-001': const <String>[
            'app_ui_structured_group_mention_verified',
          ],
          'GROUP-P9-002': const <String>[
            'cli_structured_group_mention_verified_in_app_ui',
          ],
          'GROUP-REG-001': const <String>['group_history_regression_checked'],
        });
      }

      if (selectedCase.runsAttachment) {
        await _verifyAttachmentRegression(
          robot: robot,
          messaging: faultMessaging!,
          attachmentOpenRecorder: attachmentOpenRecorder,
          ownerDid: session.did,
          thread: directThread,
          config: config,
          nonce: messageNonce,
        );
        await _attestPassedCases(<String, List<String>>{
          'ATTACH-E2E-001': const <String>[
            'app_attachment_staged_and_sent_through_drop_ui',
            'cli_attachment_bytes_verified',
          ],
          'ATTACH-E2E-002': const <String>[
            'cli_attachment_sent',
            'app_attachment_bytes_verified',
          ],
          'ATTACH-REG-001': const <String>[
            'attachment_digest_regression_checked',
          ],
        });
      }
    },
    skip: !_DesktopCliPeerSmokeConfig.exists(),
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _attestPassedCases(Map<String, List<String>> cases) async {
  for (final entry in cases.entries) {
    await E2eCaseAttestationWriter.markPassed(entry.key, phases: entry.value);
  }
}

Future<AppSession> _prepareAppIdentity(
  OnboardingService onboarding,
  _DesktopCliPeerSmokeConfig config,
) async {
  final recover = await _tryAppIdentityAction(
    () => onboarding.recoverHandle(
      phone: config.otpPhone,
      otp: config.otpCode,
      handle: config.appHandle,
    ),
  );
  if (recover.session != null) {
    return recover.session!;
  }
  if (!_looksRecoverableForRegister(recover.errorText)) {
    throw StateError(
      'App recover failed and did not look like a missing-handle error: '
      '${_sanitizeDiagnostic(recover.errorText, secrets: config.secrets)}',
    );
  }

  final register = await _tryAppIdentityAction(
    () => onboarding.registerHandleWithPhone(
      phone: config.otpPhone,
      otp: config.otpCode,
      handle: config.appHandle,
      nickName: 'AWiki E2E ${config.runId}',
    ),
  );
  if (register.session != null) {
    return register.session!;
  }
  throw StateError(
    'App register failed: '
    '${_sanitizeDiagnostic(register.errorText, secrets: config.secrets)}',
  );
}

Future<AppSession> _preparePerformanceAppIdentity({
  required AppBootstrap bootstrap,
  required _DesktopCliPeerSmokeConfig config,
  required _PerformanceWarmupResult warmup,
}) async {
  final restored = await bootstrap.appSessionService!.restoreSession();
  if (restored != null && restored.did == warmup.ownerDid) {
    return restored;
  }
  final identities = await bootstrap.appSessionService!.listLocalIdentities();
  for (final identity in identities) {
    if (identity.did == warmup.ownerDid) {
      return bootstrap.appSessionService!.activateIdentity(identity);
    }
  }
  fail(
    'Performance warmup identity ${warmup.ownerDid} was not available during '
    'the measured App launch.',
  );
}

Future<_PerformanceWarmupResult> _warmPerformanceLocalConversationState(
  _DesktopCliPeerSmokeConfig config,
) async {
  final bootstrap = await AppBootstrap.create(
    environment: config.environment,
    appStateRoot: config.appStateRoot,
  );
  try {
    final session = await _prepareAppIdentity(
      bootstrap.onboardingService!,
      config,
    );
    final datasetWatch = Stopwatch()..start();
    final dataset = await _preparePerformanceDatasetForAppSession(
      config: config,
      appDid: session.did,
    );
    final longThreadWatch = Stopwatch()..start();
    final longThread = await _ensureLongThreadDataset(
      messaging: bootstrap.messagingService!,
      thread: AppThreadRef.direct(config.cliHandle),
      config: config,
      nonce: config.runId,
    );
    longThreadWatch.stop();
    datasetWatch.stop();
    final syncWatch = Stopwatch()..start();
    final syncResult = await bootstrap.messageSyncService!.syncNow(
      reason: 'performance-warmup',
      limit: _performanceWarmupSyncLimit(
        config.performance.datasetConversationCount,
      ),
    );
    syncWatch.stop();
    final summaryWatch = Stopwatch()..start();
    final summaries = await bootstrap.conversationService!
        .listConversationSummariesFast(
          ownerDid: session.did,
          limit: config.performance.datasetConversationCount,
        );
    summaryWatch.stop();
    return _PerformanceWarmupResult(
      ownerDid: session.did,
      datasetElapsed: datasetWatch.elapsed,
      datasetExistingCount: dataset.existingCount,
      datasetCreatedCount: dataset.createdCount,
      longThreadElapsed: longThreadWatch.elapsed,
      longThreadInitialCount: longThread.initialCount,
      longThreadCreatedCount: longThread.createdCount,
      longThreadObservedCount: longThread.observedCount,
      syncElapsed: syncWatch.elapsed,
      summaryElapsed: summaryWatch.elapsed,
      eventsApplied: syncResult.eventsApplied,
      pagesFetched: syncResult.pagesFetched,
      snapshotRequired: syncResult.snapshotRequired,
      hasMore: syncResult.hasMore,
      localConversationCount: summaries.length,
      warnings: syncResult.warnings,
    );
  } finally {
    await bootstrap.appSessionService?.logout();
  }
}

int _performanceWarmupSyncLimit(int datasetConversationCount) {
  return datasetConversationCount.clamp(100, 500).toInt();
}

class _PerformanceWarmupResult {
  const _PerformanceWarmupResult({
    required this.ownerDid,
    required this.datasetElapsed,
    required this.datasetExistingCount,
    required this.datasetCreatedCount,
    required this.longThreadElapsed,
    required this.longThreadInitialCount,
    required this.longThreadCreatedCount,
    required this.longThreadObservedCount,
    required this.syncElapsed,
    required this.summaryElapsed,
    required this.eventsApplied,
    required this.pagesFetched,
    required this.snapshotRequired,
    required this.hasMore,
    required this.localConversationCount,
    required this.warnings,
  });

  final String ownerDid;
  final Duration datasetElapsed;
  final int datasetExistingCount;
  final int datasetCreatedCount;
  final Duration longThreadElapsed;
  final int longThreadInitialCount;
  final int longThreadCreatedCount;
  final int longThreadObservedCount;
  final Duration syncElapsed;
  final Duration summaryElapsed;
  final int eventsApplied;
  final int pagesFetched;
  final bool snapshotRequired;
  final bool hasMore;
  final int localConversationCount;
  final List<String> warnings;
}

Future<_PerformanceDatasetPrepareResult>
_preparePerformanceDatasetForAppSession({
  required _DesktopCliPeerSmokeConfig config,
  required String appDid,
}) async {
  final target = config.performance.datasetConversationCount;
  if (target <= 1) {
    return const _PerformanceDatasetPrepareResult(
      existingCount: 0,
      createdCount: 0,
    );
  }
  final existing = await _runCli(config, <String>[
    '--format',
    'json',
    'group',
    'list',
    '--limit',
    target.toString(),
  ]);
  if (existing.exitCode != 0) {
    fail(
      'Performance dataset group list failed: '
      '${_summarizeCliResult(existing)}',
    );
  }
  final existingGroups = _performanceDatasetGroupsFromCliOutput(
    existing.stdout,
    runId: config.runId,
  );
  final existingCount = existingGroups.length;
  final missing = target - existingCount;
  if (missing <= 0) {
    return _PerformanceDatasetPrepareResult(
      existingCount: existingCount,
      createdCount: 0,
    );
  }
  for (var index = 0; index < missing; index += 1) {
    final groupNumber = existingCount + index + 1;
    final groupName = 'AWiki Perf ${config.runId} $groupNumber';
    final create = await _runCli(config, <String>[
      '--format',
      'json',
      'group',
      'create',
      '--name',
      groupName,
      '--description',
      'AWiki performance E2E dataset conversation '
          '${config.runId} $groupNumber',
      '--discoverability',
      'private',
    ]);
    if (create.exitCode != 0) {
      fail(
        'Performance dataset group create failed: '
        '${_summarizeCliResult(create)}',
      );
    }
    final groupDid = _firstNonEmptyCliStringAtAnyPath(create.stdout, const [
      <Object>['data', 'group', 'group_did'],
      <Object>['data', 'group', 'group_id'],
      <Object>['data', 'group_did'],
      <Object>['data', 'group_id'],
    ]);
    if (groupDid == null) {
      fail(
        'Performance dataset group create did not return group id: '
        '${_summarizeCliResult(create)}',
      );
    }
    final addMember = await _runCli(config, <String>[
      '--format',
      'json',
      'group',
      'add',
      '--group',
      groupDid,
      '--member',
      appDid,
    ]);
    if (addMember.exitCode != 0) {
      fail(
        'Performance dataset group add failed: '
        '${_summarizeCliResult(addMember)}',
      );
    }
    final send = await _runCli(config, <String>[
      '--format',
      'json',
      'msg',
      'send',
      '--group',
      groupDid,
      '--text',
      'perf dataset ${config.runId} $groupNumber',
    ]);
    if (send.exitCode != 0) {
      fail(
        'Performance dataset group send failed: '
        '${_summarizeCliResult(send)}',
      );
    }
  }
  return _PerformanceDatasetPrepareResult(
    existingCount: existingCount,
    createdCount: missing,
  );
}

class _PerformanceDatasetPrepareResult {
  const _PerformanceDatasetPrepareResult({
    required this.existingCount,
    required this.createdCount,
  });

  final int existingCount;
  final int createdCount;
}

Future<_AppIdentityAttempt> _tryAppIdentityAction(
  Future<AppSession> Function() action,
) async {
  try {
    return _AppIdentityAttempt.session(await action());
  } on Object catch (error) {
    return _AppIdentityAttempt.error(error.toString());
  }
}
