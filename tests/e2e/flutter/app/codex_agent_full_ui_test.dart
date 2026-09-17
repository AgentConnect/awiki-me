import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/e2e_semantics.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
import 'package:awiki_me/src/application/onboarding_support_service.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../case_attestation.dart';
import 'package:awiki_me/src/presentation/agents/acp_session_provider.dart';
import 'package:awiki_me/src/presentation/agents/acp_model_controller.dart';
import 'package:awiki_me/src/presentation/agents/acp_task_status.dart';
import 'package:awiki_me/src/domain/entities/agent/acp_session.dart';
import 'package:flutter/cupertino.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import '../support/protected_otp_config.dart';
import '../support/coding_agent_oracles.dart';
import '../support/coding_agent_diagnostics.dart';
import '../support/desktop_test_input.dart';

const String _codexAgentRunConfigPath =
    '.e2e/codex-agent/current/run_config.json';
const Duration _codexRuntimeFinalTimeout = Duration(minutes: 5);
const String _codexDaemonMaxRuntimeMs = '780000';
const String _daemonCliProxyPassthrough =
    'HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY '
    'http_proxy https_proxy all_proxy no_proxy';

const _codingCasePhases = <String, List<String>>{
  'HERMESAGENT-E2E-001': <String>[
    'daemon_selected',
    'runtime_agent_created',
    'runtime_creation_row_unique_throughout',
    'runtime_chat_opened',
  ],
  'HERMESAGENT-E2E-002': <String>[
    'prompt_entered_through_ui',
    'send_action_completed',
  ],
  'HERMESAGENT-E2E-003': <String>[
    'runtime_run_finished',
    'runtime_final_outbox_sent',
  ],
  'HERMESAGENT-E2E-004': <String>[
    'app_history_exact_reply_verified',
    'visible_reply_verified',
  ],
  'ACP-OPENCODE-E2E-009': <String>[
    'group_task_accepted',
    'busy_instruction_rejected',
    'ordinary_chat_continues',
    'requester_answers_in_group',
    'prior_group_context_returned',
  ],
  'ACP-GEMINI-E2E-009': <String>[
    'group_task_accepted',
    'busy_instruction_rejected',
    'ordinary_chat_continues',
    'requester_answers_in_group',
    'prior_group_context_returned',
  ],
  'ACP-KIMI-E2E-009': <String>[
    'group_task_accepted',
    'busy_instruction_rejected',
    'ordinary_chat_continues',
    'requester_answers_in_group',
    'prior_group_context_returned',
  ],
  'ACP-DEEPSEEK-HARNESS-E2E-009': <String>[
    'group_task_accepted',
    'busy_instruction_rejected',
    'ordinary_chat_continues',
    'requester_answers_in_group',
    'prior_group_context_returned',
  ],
  'CODEXAGENT-E2E-001': <String>[
    'daemon_selected',
    'runtime_agent_created',
    'runtime_creation_row_unique_throughout',
    'runtime_chat_opened',
  ],
  'CODEXAGENT-E2E-002': <String>[
    'prompt_entered_through_ui',
    'send_action_completed',
  ],
  'CODEXAGENT-E2E-003': <String>[
    'runtime_run_finished',
    'runtime_final_outbox_sent',
  ],
  'CODEXAGENT-E2E-004': <String>[
    'app_history_exact_reply_verified',
    'visible_reply_verified',
  ],
  'ACP-OPENCODE-E2E-001': <String>[
    'daemon_selected',
    'runtime_agent_created',
    'runtime_creation_row_unique_throughout',
    'runtime_chat_opened',
    'initial_model_visible_and_selectable',
  ],
  'ACP-OPENCODE-E2E-002': <String>[
    'prompt_entered_through_ui',
    'send_action_completed',
  ],
  'ACP-OPENCODE-E2E-003': <String>[
    'runtime_run_finished',
    'runtime_final_outbox_sent',
  ],
  'ACP-OPENCODE-E2E-004': <String>[
    'app_history_exact_reply_verified',
    'visible_reply_verified',
  ],
  'ACP-OPENCODE-E2E-005': <String>[
    'single_waiting_slot',
    'third_draft_retained',
    'stop_pauses_waiting',
    'manual_execute_finishes',
    'idle_model_selection_applied',
    'immediate_execution_stops_active',
    'idle_after_stop_then_completion',
  ],
  'ACP-OPENCODE-E2E-006': <String>[
    'waiting_cancelled',
    'message_retained',
    'active_stopped',
  ],
  'ACP-OPENCODE-E2E-007': <String>[
    'question_waited',
    'real_ui_answer',
    'answer_draft_independent',
    'answer_final_visible',
    'normal_completion_executes_waiting_once',
    'supplement_returned_without_changing_draft',
  ],
  'ACP-GEMINI-E2E-001': <String>[
    'daemon_selected',
    'runtime_agent_created',
    'runtime_creation_row_unique_throughout',
    'runtime_chat_opened',
    'initial_model_visible_and_selectable',
  ],
  'ACP-GEMINI-E2E-002': <String>[
    'prompt_entered_through_ui',
    'send_action_completed',
  ],
  'ACP-GEMINI-E2E-003': <String>[
    'runtime_run_finished',
    'runtime_final_outbox_sent',
  ],
  'ACP-GEMINI-E2E-004': <String>[
    'app_history_exact_reply_verified',
    'visible_reply_verified',
  ],
  'ACP-GEMINI-E2E-005': <String>[
    'single_waiting_slot',
    'third_draft_retained',
    'stop_pauses_waiting',
    'manual_execute_finishes',
    'idle_model_selection_applied',
    'immediate_execution_stops_active',
    'idle_after_stop_then_completion',
  ],
  'ACP-GEMINI-E2E-006': <String>[
    'waiting_cancelled',
    'message_retained',
    'active_stopped',
  ],
  'ACP-GEMINI-E2E-007': <String>[
    'question_waited',
    'real_ui_answer',
    'answer_draft_independent',
    'answer_final_visible',
    'normal_completion_executes_waiting_once',
    'supplement_returned_without_changing_draft',
  ],
  'ACP-KIMI-E2E-001': <String>[
    'daemon_selected',
    'runtime_agent_created',
    'runtime_creation_row_unique_throughout',
    'runtime_chat_opened',
    'initial_model_visible_and_selectable',
  ],
  'ACP-KIMI-E2E-002': <String>[
    'prompt_entered_through_ui',
    'send_action_completed',
  ],
  'ACP-KIMI-E2E-003': <String>[
    'runtime_run_finished',
    'runtime_final_outbox_sent',
  ],
  'ACP-KIMI-E2E-004': <String>[
    'app_history_exact_reply_verified',
    'visible_reply_verified',
  ],
  'ACP-KIMI-E2E-005': <String>[
    'single_waiting_slot',
    'third_draft_retained',
    'stop_pauses_waiting',
    'manual_execute_finishes',
    'idle_model_selection_applied',
    'immediate_execution_stops_active',
    'idle_after_stop_then_completion',
  ],
  'ACP-KIMI-E2E-006': <String>[
    'waiting_cancelled',
    'message_retained',
    'active_stopped',
  ],
  'ACP-KIMI-E2E-007': <String>[
    'question_waited',
    'real_ui_answer',
    'answer_draft_independent',
    'answer_final_visible',
    'normal_completion_executes_waiting_once',
    'supplement_returned_without_changing_draft',
  ],
  'ACP-DEEPSEEK-HARNESS-E2E-001': <String>[
    'daemon_selected',
    'runtime_agent_created',
    'runtime_creation_row_unique_throughout',
    'runtime_chat_opened',
    'initial_model_visible_and_selectable',
  ],
  'ACP-DEEPSEEK-HARNESS-E2E-002': <String>[
    'prompt_entered_through_ui',
    'send_action_completed',
  ],
  'ACP-DEEPSEEK-HARNESS-E2E-003': <String>[
    'runtime_run_finished',
    'runtime_final_outbox_sent',
  ],
  'ACP-DEEPSEEK-HARNESS-E2E-004': <String>[
    'app_history_exact_reply_verified',
    'visible_reply_verified',
  ],
  'ACP-DEEPSEEK-HARNESS-E2E-005': <String>[
    'single_waiting_slot',
    'third_draft_retained',
    'stop_pauses_waiting',
    'manual_execute_finishes',
    'idle_model_selection_applied',
    'immediate_execution_stops_active',
    'idle_after_stop_then_completion',
  ],
  'ACP-DEEPSEEK-HARNESS-E2E-006': <String>[
    'waiting_cancelled',
    'message_retained',
    'active_stopped',
  ],
  'ACP-DEEPSEEK-HARNESS-E2E-007': <String>[
    'question_waited',
    'real_ui_answer',
    'answer_draft_independent',
    'answer_final_visible',
    'normal_completion_executes_waiting_once',
    'supplement_returned_without_changing_draft',
  ],
  'ACP-OPENCODE-E2E-008': <String>[
    'attachment_staged_through_ui',
    'file_roundtrip_bytes_equal',
    'image_model_reply_verified',
    'attachment_replies_visible',
  ],
  'ACP-GEMINI-E2E-008': <String>[
    'attachment_staged_through_ui',
    'file_roundtrip_bytes_equal',
    'image_model_reply_verified',
    'attachment_replies_visible',
  ],
  'ACP-KIMI-E2E-008': <String>[
    'attachment_staged_through_ui',
    'file_roundtrip_bytes_equal',
    'image_model_reply_verified',
    'attachment_replies_visible',
  ],
  'ACP-DEEPSEEK-HARNESS-E2E-008': <String>[
    'attachment_staged_through_ui',
    'file_roundtrip_bytes_equal',
    'image_model_reply_verified',
    'attachment_replies_visible',
  ],
};
Future<void> _markCodingCase(String caseId) async {
  final entry = _codingCasePhases.entries.singleWhere(
    (entry) => entry.key == caseId,
  );
  await E2eCaseAttestationWriter.markPassed(entry.key, phases: entry.value);
  debugPrint('Coding Agent case passed: $caseId');
}

void main() => codingAgentAcceptance();

/// Shared real App/Daemon acceptance; ACP adds its controls to the same chat flow.
void codingAgentAcceptance({bool acp = false, bool hermes = false}) {
  final runChatCases =
      !acp ||
      codingAgentAcpCaseNumbers(
        const String.fromEnvironment('AWIKI_ACP_FOCUS_DRIVER'),
        groupOnly: const bool.fromEnvironment('AWIKI_ACP_FOCUS_GROUP_ONLY'),
      ).contains(2);
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(
    () => E2eInvocationCompletionWriter.markFinished(
      failedTestCount: binding.failureMethodsDetails.length,
    ),
  );

  testWidgets(
    acp
        ? 'Four ACP agents use the real App chat and task controls'
        : '${hermes ? 'Hermes' : 'Codex'} Agent full UI sends deterministic prompt and shows visible reply',
    (tester) async {
      final config = _CodexAgentRealBackendConfig.tryLoad(
        acp: acp,
        hermes: hermes,
      );
      if (config == null || !config.enabled || !config.realBackend) {
        fail(
          'Codex Agent full UI acceptance requires an enabled real-backend '
          'runner config and cannot pass as a skipped/no-op test.',
        );
      }
      if (!File(config.daemonBinary).existsSync()) {
        fail('daemon binary was not found: ${config.daemonBinary}');
      }
      if (acp) {
        addTearDown(disableDesktopPointerInspector(tester.binding));
      }
      debugDefaultTargetPlatformOverride = config.targetPlatform;
      await tester.binding.setSurfaceSize(const Size(1400, 900));

      final bootstrap = await AppBootstrap.create(
        environment: config.environment,
        appStateRoot: config.appStateRoot,
      );
      Process? daemon;
      try {
        final session = await prepareCodingAgentSession(
          reusePreparedIdentity: config.reusePreparedIdentity,
          expectedFullHandle:
              '${config.appHandle}.${config.environment.didDomain}',
          restore: () => restorePreparedCodingAccount(
            expectedFullHandle:
                '${config.appHandle}.${config.environment.didDomain}',
            list: bootstrap.appSessionService!.listLocalIdentities,
            login: bootstrap.appSessionService!.loginWithIdentity,
          ),
          register: () => _prepareRealAppIdentity(
            bootstrap.onboardingService!,
            bootstrap.onboardingSupportService!,
            config,
          ),
        );
        // Finish the Core identity transition before App initialization starts
        // its own restore. Both transitions own the same session lease.
        await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
        await _pumpFrame(tester);
        expect(find.byType(AppShell), findsOneWidget);

        final appContainer = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );
        await _pumpUntil(
          tester,
          () {
            final runtime = appContainer.read(appRuntimeProvider);
            if (!runtime.isInitialized || runtime.isBusy) return false;
            expect(runtime.activatedDid, session.did);
            expect(
              appContainer.read(sessionProvider).session?.did,
              session.did,
            );
            return find
                    .bySemanticsIdentifier('e2e-authenticated')
                    .evaluate()
                    .length ==
                1;
          },
          timeout: const Duration(seconds: 45),
          description: 'restored authenticated App shell',
        );
        final install = await _installRealDaemon(
          config: config,
          inventory: appContainer.read(agentInventoryPortProvider),
          controllerDid: session.did,
        );
        daemon = await _startRealDaemon(
          config: config,
          maxRuntimeMs: acp ? '2700000' : _codexDaemonMaxRuntimeMs,
        );
        await _waitForFile(config.daemonReadyFile);

        final agents = appContainer.read(agentsProvider.notifier);
        await _waitForAgentInventoryEntry(
          tester: tester,
          agents: agents,
          agentDid: install.daemonDid,
          handle: install.handle,
        );

        await _tapFirstFound(tester, <Finder>[
          find.bySemanticsIdentifier('e2e-agents-tab'),
          find.bySemanticsLabel('智能体'),
          find.bySemanticsLabel('Agents'),
          find.text('智能体'),
          find.text('Agents'),
        ]);
        agents.select(install.daemonDid);
        await _pumpFrame(tester);
        if (!hermes) {
          await _waitForDaemonGenericCliCapability(
            tester: tester,
            agents: agents,
            daemonDid: install.daemonDid,
            acp: acp,
          );
        }

        final kinds = acp
            ? codingAgentAcpKinds(
                const String.fromEnvironment('AWIKI_ACP_FOCUS_DRIVER'),
              )
            : [hermes ? RuntimeAgentKind.hermes : RuntimeAgentKind.codex];
        final independentFailures = <String>[];
        for (final kind in kinds) {
          final prefix = acp
              ? 'ACP-${kind.driverId!.toUpperCase()}-E2E'
              : hermes
              ? 'HERMESAGENT-E2E'
              : 'CODEXAGENT-E2E';
          final runtimeHandle = acp
              ? 'e2acp-${kind.name.toLowerCase()}-${config.runId.hashCode.abs()}'
              : hermes
              ? 'e2hermes-${config.runId.hashCode.abs()}'
              : _codexRuntimeHandle(config.runId);
          final createRuntimeFuture = agents.createRuntimeAgent(
            install.daemonDid,
            options: RuntimeAgentCreateOptions(
              kind: kind,
              handle: runtimeHandle,
              displayName: '${kind.displayLabel} E2E',
              workspaceMode: acp
                  ? runtimeWorkspaceModeSharedRoot
                  : runtimeWorkspaceModeRouteRoot,
            ),
          );
          await _pumpFrame(tester);
          final pendingCreateState = ProviderScope.containerOf(
            tester.element(find.byType(AppShell)),
          ).read(agentsProvider);
          expect(
            pendingCreateState.pendingRuntimeCreations.any(
              (pending) =>
                  pending.daemonAgentDid == install.daemonDid &&
                  pending.handle.trim().toLowerCase() ==
                      runtimeHandle.trim().toLowerCase(),
            ),
            isTrue,
            reason:
                'the real creation path must expose its optimistic pending row',
          );
          _expectSingleRuntimeAgentRowForHandle(runtimeHandle);
          await createRuntimeFuture;
          await _pumpUntil(
            tester,
            () => !ProviderScope.containerOf(
              tester.element(find.byType(AppShell)),
            ).read(agentsProvider).isActing,
            timeout: const Duration(seconds: 30),
            description: 'Codex runtime create action to finish',
          );
          final stateAfterCreate = ProviderScope.containerOf(
            tester.element(find.byType(AppShell)),
          ).read(agentsProvider);
          if (stateAfterCreate.error != null) {
            fail(
              'Codex runtime create failed: ${stateAfterCreate.error}. '
              'Raw error: ${stateAfterCreate.debugLastError}. '
              'Agents: ${_agentsDebugSummary(stateAfterCreate)}',
            );
          }

          if (acp) {
            debugPrint(
              'Coding Agent create delivery: ${jsonEncode(await codingAgentDeliveryDiagnostics(bootstrap.messagingService!, install.daemonDid))}',
            );
          }
          final runtime = await _waitForRuntimeAgentByHandle(
            tester: tester,
            daemonDid: install.daemonDid,
            handle: runtimeHandle,
            acp: acp,
            hermes: hermes,
          );
          await _expectSingleRuntimeAgentRow(tester: tester, runtime: runtime);
          agents.select(runtime.agentDid);
          await _pumpFrame(tester);
          await _tapFirstFound(tester, <Finder>[find.text('打开聊天')]);
          await _pumpFrame(tester);
          expect(find.text('${kind.displayLabel} E2E'), findsWidgets);
          if (acp) await _verifyAcpInitialModels(tester, appContainer, runtime);
          await _markCodingCase('$prefix-001');

          if (runChatCases) {
            await _sendPromptThroughUi(tester, config.prompt);
            await _markCodingCase('$prefix-002');
            await _waitForDaemonCodexFinalSent(
              daemonStateRoot: config.daemonStateRoot,
              runtimeAgentDid: runtime.agentDid,
              prompt: config.prompt,
              expectedReply: config.expectedReply,
              runtimePluginId: acp
                  ? 'acp'
                  : hermes
                  ? 'runtime.hermes'
                  : 'generic-cli',
            );
            await _markCodingCase('$prefix-003');
            await _waitForAppIncomingCodexReply(
              messaging: bootstrap.messagingService!,
              runtimeAgentDid: runtime.agentDid,
              expectedReply: config.expectedReply,
            );
            await _waitForVisibleCodexReply(
              tester: tester,
              expectedReply: config.expectedReply,
            );
            await _markCodingCase('$prefix-004');
            if (acp) {
              await _verifyAcpChatControls(
                tester,
                appContainer,
                runtime,
                prefix,
                config.daemonStateRoot,
              );
              try {
                await _verifyAcpAttachments(
                  tester,
                  bootstrap.messagingService!,
                  runtime,
                  prefix,
                  config.daemonStateRoot,
                );
              } catch (error) {
                // Preserve this case failure. Independent clients/group checks
                // still run; the invocation fails below.
                final detail = _sanitizeDiagnostic(error.toString(), config);
                independentFailures.add('$prefix-008: $detail');
                await E2eCaseAttestationWriter.markFailed(
                  '$prefix-008',
                  phase: 'attachment_acceptance_failed',
                );
                debugPrint('ACP attachment case failed: $prefix-008: $detail');
              }
            }
          }
          if (acp) {
            try {
              await _verifyAcpGroup(
                tester,
                appContainer,
                bootstrap,
                runtime,
                prefix,
                config.daemonStateRoot,
                config.appHandle,
              );
            } catch (error) {
              final detail = _sanitizeDiagnostic(error.toString(), config);
              independentFailures.add('$prefix-009: $detail');
              await E2eCaseAttestationWriter.markFailed(
                '$prefix-009',
                phase: 'group_acceptance_failed',
              );
              debugPrint('ACP group case failed: $prefix-009: $detail');
            }
          }
          if (acp) {
            await _tapFirstFound(tester, <Finder>[
              find.bySemanticsIdentifier('e2e-agents-tab'),
              find.text('智能体'),
              find.text('Agents'),
            ]);
            agents.select(install.daemonDid);
            await _pumpFrame(tester);
          }
        }
        if (independentFailures.isNotEmpty) {
          fail(independentFailures.join('\n'));
        }
      } finally {
        if (daemon != null) {
          _terminateProcess(daemon);
        }
        await bootstrap.appSessionService?.logout();
        debugDefaultTargetPlatformOverride = null;
        await tester.binding.setSurfaceSize(null);
      }
    },
    timeout: Timeout(Duration(minutes: acp ? 75 : 15)),
  );
}

Future<AcpSession> _waitAcp(
  WidgetTester tester,
  ProviderContainer container,
  String agent,
  bool Function(AcpSession) predicate,
) async {
  AcpSession? found;
  await _pumpUntil(
    tester,
    () {
      for (final session
          in container.read(acpSessionsProvider).sessions.values) {
        if (session.agentDid == agent && predicate(session)) {
          found = session;
          return true;
        }
      }
      return false;
    },
    timeout: const Duration(minutes: 3),
    description: 'committed ACP task state',
  );
  return found!;
}

Future<void> _tapAcpAction(
  WidgetTester tester,
  String action,
  Object? run,
) async {
  final button = find.byKey(ValueKey('acp-$action:$run'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _pumpFrame(tester);
}

Future<void> _verifyAcpInitialModels(
  WidgetTester tester,
  ProviderContainer container,
  AgentSummary agent,
) async {
  final initial = await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) => !s.group && !s.busy && s.data['model_configuration_ready'] == true,
  );
  // The configuration event can precede the correlated command response.
  // Until both have reconciled the product deliberately disables selection.
  await _pumpUntil(
    tester,
    () {
      final operation = container.read(
        acpModelControllerProvider((
          agentDid: agent.agentDid,
          conversationId: initial.conversationId,
        )),
      );
      if (operation.phase == AcpModelPhase.failed ||
          operation.phase == AcpModelPhase.uncertain) {
        fail(
          'Initial model preparation ${operation.phase.name}: '
          '${operation.errorCode ?? "response_not_confirmed"}',
        );
      }
      return !operation.blocksSending;
    },
    timeout: const Duration(minutes: 2),
    description: 'Initial model command response reconciled with Core state',
  );
  await _pumpFrame(tester);
  expect(
    initial.history,
    isEmpty,
    reason: 'Preparing models must not execute a task',
  );
  expect(initial.data['model_id'], isA<String>());
  final current = initial.data['model_id'];
  final model = initial.models.where((m) => m['id'] == current).firstOrNull;
  final menu = find.byKey(const Key('acp-model-menu'));
  expect(
    find.descendant(
      of: menu,
      matching: find.text('${model?['name'] ?? current}'),
    ),
    findsOneWidget,
  );
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await _pumpFrame(tester);
  // Gemini can report a configured proxy alias as current while advertising
  // only its native selectable models. Display that exact current value, then
  // exercise a genuinely advertised choice (the test relay maps gemini-*).
  final choice = model ?? initial.models.firstWhere((m) => m['id'] != 'auto');
  final selectedId = choice['id'];
  // Providers can advertise hundreds of models; off-screen sliver rows have
  // not been built. Use the product's search rather than assuming every row
  // already has an Element.
  final search = find.byKey(const Key('acp-model-search'));
  if (search.evaluate().isNotEmpty) {
    await tester.enterText(search, '$selectedId');
    await _pumpFrame(tester);
  }
  final row = find.byKey(ValueKey('acp-model:$selectedId'));
  await tester.ensureVisible(row);
  expect(tester.widget<CupertinoButton>(row).onPressed, isNotNull);
  await tester.tap(row);
  await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) => s.revision > initial.revision && s.data['model_id'] == selectedId,
  );
  await _pumpUntil(
    tester,
    () => find.byKey(const Key('acp-model-picker')).evaluate().isEmpty,
    timeout: const Duration(seconds: 30),
    description: 'Initial model choice committed',
  );
}

Future<void> _verifyAcpChatControls(
  WidgetTester tester,
  ProviderContainer container,
  AgentSummary agent,
  String prefix,
  String daemonStateRoot,
) async {
  const stopQuestion =
      'Use awiki_questions request_user_input to ask me a required stop_test_choice string with enum proceed_with_stop_test. Wait for my real answer. Do not answer for me.';
  const cancelWaitingQuestion =
      'This is a different task and question. Use awiki_questions request_user_input to ask me a required waiting_test_choice string with enum proceed_with_waiting_test. Wait for my real answer. Do not answer for me.';
  bool waitingForUser(AcpSession session) => hasAcpBlockingQuestion(
    session,
    nowMs: DateTime.now().millisecondsSinceEpoch,
  );
  await _sendPromptThroughUi(tester, stopQuestion);
  var session = await _waitAcp(
    tester,
    container,
    agent.agentDid,
    waitingForUser,
  );
  final active = session.active['run_id'];
  await _sendPromptThroughUi(tester, 'Reply exactly QUEUED_TASK_DONE.');
  session = await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) => s.waiting.isNotEmpty,
  );
  final waiting = session.waiting['run_id'];
  final input = find.bySemanticsIdentifier('e2e-chat-input');
  await _sendPromptThroughUi(tester, 'THIRD_MESSAGE_MUST_REMAIN_A_DRAFT');
  expect(find.byType(CupertinoAlertDialog), findsOneWidget);
  expect(
    tester
        .widget<EditableText>(
          find.descendant(
            of: input,
            matching: find.byType(EditableText),
            matchRoot: true,
          ),
        )
        .controller
        .text,
    'THIRD_MESSAGE_MUST_REMAIN_A_DRAFT',
  );
  await _tapFirstFound(tester, [find.text('知道了'), find.text('OK')]);
  await _tapAcpAction(tester, 'stop', active);
  session = await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) => !s.busy && s.waitingPaused,
  );
  expect(session.waiting['run_id'], waiting);
  await _tapAcpAction(tester, 'execute_waiting', waiting);
  await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) => s.history.any(
      (t) => t['run_id'] == waiting && t['state'] == 'finished',
    ),
  );
  await _waitForVisibleCodexReply(
    tester: tester,
    expectedReply: 'QUEUED_TASK_DONE',
  );
  const insertionQuestion =
      'This is a new insertion test. Use awiki_questions request_user_input to ask a required insertion_choice string with enum continue_insertion_test. Wait for my real answer. Do not answer for me.';
  await _sendPromptThroughUi(tester, insertionQuestion);
  session = await _waitAcp(tester, container, agent.agentDid, waitingForUser);
  final interruptedRun = session.active['run_id'];
  await _sendPromptThroughUi(tester, 'Reply exactly INSERTED_TASK_DONE.');
  session = await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) => s.waiting.isNotEmpty,
  );
  final insertedRun = session.waiting['run_id'];
  await _tapAcpAction(tester, 'execute_waiting', insertedRun);
  session = await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) => s.history.any(
      (t) => t['run_id'] == insertedRun && t['state'] == 'finished',
    ),
  );
  expect(
    session.history.where(
      (t) => t['run_id'] == interruptedRun && t['state'] == 'cancelled',
    ),
    hasLength(1),
  );
  expect(
    session.history.where((t) => t['run_id'] == insertedRun),
    hasLength(1),
  );
  await _waitForVisibleCodexReply(
    tester: tester,
    expectedReply: 'INSERTED_TASK_DONE',
  );
  expect(
    container.read(acpSessionsProvider).busyForAgent(agent.agentDid),
    isFalse,
    reason: 'Stopped A followed by completed B must return to idle',
  );
  await _markCodingCase('$prefix-005');

  await _sendPromptThroughUi(tester, cancelWaitingQuestion);
  session = await _waitAcp(tester, container, agent.agentDid, waitingForUser);
  final secondActive = session.active['run_id'];
  await _sendPromptThroughUi(tester, 'THIS_WAITING_TASK_WILL_BE_CANCELLED');
  session = await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) => s.waiting.isNotEmpty,
  );
  final cancelled = session.waiting['run_id'];
  await _tapAcpAction(tester, 'cancel_waiting', cancelled);
  await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) =>
        s.waiting.isEmpty &&
        s.history.any(
          (t) => t['run_id'] == cancelled && t['state'] == 'cancelled',
        ),
  );
  expect(find.text('THIS_WAITING_TASK_WILL_BE_CANCELLED'), findsWidgets);
  await _tapAcpAction(tester, 'stop', secondActive);
  await _waitAcp(tester, container, agent.agentDid, (s) => !s.busy);
  await _markCodingCase('$prefix-006');

  const questionPrompt =
      'Use awiki_questions request_user_input to ask me a required color string with enum red and blue. Wait for my real answer. If I choose blue, reply with exactly the additional text field returned by the tool. Do not answer for me.';
  await _sendPromptThroughUi(tester, questionPrompt);
  session = await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) => s.questions.isNotEmpty,
  );
  final questionRun = session.active['run_id'];
  expect(find.byType(AcpQuestionForm), findsOneWidget);
  expect(
    tester.widget<AcpQuestionForm>(find.byType(AcpQuestionForm)).canAnswer,
    isTrue,
    reason: 'The task requester must be allowed to answer the real question',
  );
  await _sendPromptThroughUi(
    tester,
    'Reply exactly AUTOMATIC_WAITING_TASK_DONE.',
  );
  session = await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) => s.waiting.isNotEmpty,
  );
  final automaticWaiting = session.waiting['run_id'];
  await tester.ensureVisible(input);
  await tester.tap(input);
  await _pumpFrame(tester);
  await tester.enterText(input, 'QUESTION_MUST_NOT_OVERWRITE_THIS_DRAFT');
  await _pumpFrame(tester);
  final blue = find.descendant(
    of: find.byType(AcpQuestionForm),
    matching: find.text('blue'),
  );
  await tester.ensureVisible(blue);
  await tester.tap(blue);
  await _pumpFrame(tester);
  expect(
    find.ancestor(
      of: blue,
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.checked == true,
      ),
    ),
    findsOneWidget,
  );
  await _tapFirstFound(tester, [
    find.byKey(const Key('acp-additional-toggle')),
  ]);
  final supplement = find.byKey(const Key('acp-additional-text'));
  await tester.ensureVisible(supplement);
  await tester.enterText(supplement, 'USER_CHOSE_BLUE');
  await _pumpFrame(tester);
  await _tapFirstFound(tester, [find.text('提交回答'), find.text('Submit answer')]);
  await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) => s.history.any(
      (t) => t['run_id'] == questionRun && t['state'] == 'finished',
    ),
  );
  final questionReply = await _waitForDaemonCodexFinalSent(
    daemonStateRoot: daemonStateRoot,
    runtimeAgentDid: agent.agentDid,
    prompt: questionPrompt,
    expectedReply: 'USER_CHOSE_BLUE',
    runtimePluginId: 'acp',
    allowProgressText: true,
  );
  await _waitForVisibleCodexReply(tester: tester, expectedReply: questionReply);
  session = await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) => s.history.any(
      (t) => t['run_id'] == automaticWaiting && t['state'] == 'finished',
    ),
  );
  expect(
    session.history.where((t) => t['run_id'] == automaticWaiting),
    hasLength(1),
  );
  await _waitForVisibleCodexReply(
    tester: tester,
    expectedReply: 'AUTOMATIC_WAITING_TASK_DONE',
  );
  expect(
    tester
        .widget<EditableText>(
          find.descendant(
            of: input,
            matching: find.byType(EditableText),
            matchRoot: true,
          ),
        )
        .controller
        .text,
    'QUESTION_MUST_NOT_OVERWRITE_THIS_DRAFT',
  );
  await _markCodingCase('$prefix-007');
}

Future<void> _verifyAcpGroup(
  WidgetTester tester,
  ProviderContainer container,
  AppBootstrap bootstrap,
  AgentSummary agent,
  String prefix,
  String daemonStateRoot,
  String requesterHandle,
) async {
  final groups = bootstrap.groupApplicationService!;
  final messages = bootstrap.messagingService!;
  final group = await groups.createGroup(
    name: 'ACP group ${DateTime.now().microsecondsSinceEpoch}',
    slug: 'acp-${DateTime.now().microsecondsSinceEpoch}',
    description: 'ACP isolated verification',
    goal: 'Verify group task admission and requester answers',
    rules: 'Verification participants only',
  );
  final groupDid = group.groupId;
  await groups.addMember(groupDid: groupDid, memberRef: agent.agentDid);
  final thread = AppThreadRef.group(groupDid);
  final contextProof = 'GROUP_CONTEXT_${DateTime.now().microsecondsSinceEpoch}';
  await messages.sendText(thread: thread, content: contextProof);
  await container.read(conversationListProvider.notifier).refresh();
  container
      .read(selectedConversationProvider.notifier)
      .selectConversationId('group:$groupDid');
  await _pumpFrame(tester);
  const surface = '@agent';
  final mention = ChatMentionDraft(
    localId: 'group-agent',
    surface: surface,
    start: 0,
    end: surface.length,
    target: ChatMentionTargetDraft.member(
      kind: ChatMentionTargetKind.agent,
      did: agent.agentDid,
    ),
  );
  const prompt =
      '$surface Use awiki_questions request_user_input to ask me a required color string with enum red and blue. Wait for my real answer. If I choose blue reply exactly GROUP_USER_CHOSE_BLUE. Do not answer for me.';
  await messages.sendMentionText(
    thread: thread,
    text: prompt,
    mentions: [mention],
  );
  var session = await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) => s.group && s.questions.isNotEmpty,
  );
  final run = session.active['run_id'];
  expect(session.waiting, isEmpty);
  expect(find.byKey(ValueKey('acp-stop:$run')), findsNothing);
  // A committed provider update can precede its next rendered frame.
  await _pumpUntil(
    tester,
    () => find.byType(AcpQuestionForm).evaluate().length == 1,
    timeout: const Duration(seconds: 30),
    description: 'live group question rendered after committed ACP state',
  );
  expect(find.byType(AcpQuestionForm), findsOneWidget);

  // A second device can race the UI's admission hint. Send via the existing
  // Core facade and require the authoritative Daemon rejection to converge.
  const competing = '$surface Reply GROUP_BUSY_MUST_NOT_RUN.';
  final rejected = await messages.sendMentionText(
    thread: thread,
    text: competing,
    mentions: [mention],
  );
  await _pumpUntil(
    tester,
    () => container
        .read(acpSessionsProvider)
        .rejections
        .values
        .any(
          (r) =>
              r['agent_did'] == agent.agentDid &&
              r['reason'] == 'group_busy' &&
              {
                rejected.localId,
                rejected.remoteId,
              }.contains(r['source_message_id']),
        ),
    timeout: const Duration(minutes: 2),
    description: 'committed group_busy rejection',
  );
  await _sendPromptThroughUi(tester, 'ORDINARY_GROUP_MESSAGE_WHILE_AGENT_BUSY');
  await _waitForVisibleCodexReply(
    tester: tester,
    expectedReply: 'ORDINARY_GROUP_MESSAGE_WHILE_AGENT_BUSY',
  );
  expect(
    tester.widget<AcpQuestionForm>(find.byType(AcpQuestionForm)).canAnswer,
    isTrue,
  );
  final blue = find.descendant(
    of: find.byType(AcpQuestionForm),
    matching: find.text('blue'),
  );
  await tester.ensureVisible(blue);
  await tester.tap(blue);
  await _pumpFrame(tester);
  await _tapFirstFound(tester, [find.text('提交回答'), find.text('Submit answer')]);
  session = await _waitAcp(
    tester,
    container,
    agent.agentDid,
    (s) =>
        s.group &&
        !s.busy &&
        s.history.any((t) => t['run_id'] == run && t['state'] == 'finished'),
  );
  expect(session.waiting, isEmpty);
  final groupReply = await _waitForDaemonCodexFinalSent(
    daemonStateRoot: daemonStateRoot,
    runtimeAgentDid: agent.agentDid,
    prompt: prompt,
    expectedReply: 'GROUP_USER_CHOSE_BLUE',
    runtimePluginId: 'acp',
    allowProgressText: true,
  );
  await _waitForVisibleCodexReply(
    tester: tester,
    expectedReply: '@$requesterHandle $groupReply',
  );
  expect(find.text('GROUP_BUSY_MUST_NOT_RUN'), findsNothing);
  const historyPrompt =
      '$surface From the earlier ordinary group chat, repeat exactly the GROUP_CONTEXT_ marker. Do not use tools or guess.';
  await messages.sendMentionText(
    thread: thread,
    text: historyPrompt,
    mentions: [mention],
  );
  final historyReply = await _waitForDaemonCodexFinalSent(
    daemonStateRoot: daemonStateRoot,
    runtimeAgentDid: agent.agentDid,
    prompt: historyPrompt,
    expectedReply: contextProof,
    runtimePluginId: 'acp',
    allowProgressText: true,
  );
  await _waitForVisibleCodexReply(
    tester: tester,
    expectedReply: '@$requesterHandle $historyReply',
  );
  await _markCodingCase('$prefix-009');
}

Future<void> _stageAcpFile(
  WidgetTester tester,
  String name,
  List<int> bytes,
) async {
  final target = find.byWidgetPredicate(
    (widget) => widget.key.toString().contains('chat-attachment-drop-target:'),
  );
  expect(target, findsOneWidget);
  Future<void> drop(String method, Object arguments) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'desktop_drop',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        );
    await _pumpFrame(tester);
  }

  final point = tester.getCenter(target);
  await drop('entered', [point.dx, point.dy]);
  await drop('updated', [point.dx, point.dy]);
  expect(find.byKey(const Key('chat-attachment-drop-overlay')), findsOneWidget);
  final directory = await Directory.systemTemp.createTemp('awiki-acp-ui-file-');
  try {
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await drop(
      Platform.isMacOS ? 'performOperation_macos' : 'performOperation',
      Platform.isMacOS
          ? [
              {'path': file.path, 'isDirectory': false, 'fromPromise': false},
            ]
          : [file.path],
    );
    await _pumpUntil(
      tester,
      () => find
          .byKey(const Key('chat-pending-attachment-preview'))
          .evaluate()
          .isNotEmpty,
      timeout: const Duration(seconds: 20),
      description: 'ACP attachment staged by desktop drop',
    );
    expect(find.text(name), findsWidgets);
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<void> _verifyAcpAttachments(
  WidgetTester tester,
  MessagingService messages,
  AgentSummary agent,
  String prefix,
  String daemonStateRoot,
) async {
  final proof = utf8.encode(
    'ACP_FILE_${DateTime.now().microsecondsSinceEpoch}\n中文内容与第二行必须保留。\n',
  );
  await _stageAcpFile(tester, 'acp-input.txt', proof);
  const filePrompt =
      'Read the attached file. Make an exact byte-for-byte copy named acp-roundtrip.txt and send that copy back using the AWiki file delivery wrapper. After successful delivery reply exactly FILE_ROUNDTRIP_DONE.';
  await _sendPromptThroughUi(tester, filePrompt);
  final fileReply = await _waitForDaemonCodexFinalSent(
    daemonStateRoot: daemonStateRoot,
    runtimeAgentDid: agent.agentDid,
    prompt: filePrompt,
    expectedReply: 'FILE_ROUNDTRIP_DONE',
    runtimePluginId: 'acp',
    allowProgressText: true,
  );
  ChatMessage? returned;
  await _poll(
    description: 'authorized ACP file round trip in App history',
    action: () async {
      final history = await messages.loadHistory(
        AppThreadRef.direct(agent.agentDid),
        limit: 50,
      );
      final files = history
          .where(
            (m) =>
                !m.isMine &&
                m.senderDid == agent.agentDid &&
                m.attachment?.filename == 'acp-roundtrip.txt',
          )
          .toList();
      expect(
        files.length,
        lessThanOrEqualTo(1),
        reason: 'The returned file must not be duplicated',
      );
      if (files.isEmpty) return false;
      returned = files.single;
      return true;
    },
  );
  final downloaded = await messages.downloadAttachment(
    thread: AppThreadRef.direct(agent.agentDid),
    messageId: returned!.remoteId ?? returned!.localId,
    attachmentId: returned!.attachment!.attachmentId,
  );
  final received =
      downloaded.bytes ?? await File(downloaded.localPath!).readAsBytes();
  expect(received, orderedEquals(proof));
  debugPrint('ACP authorized file byte roundtrip passed: $prefix');
  await _waitForVisibleCodexReply(tester: tester, expectedReply: fileReply);

  // The answer exists only in the pixels, never in the filename or prompt.
  // A flat-color fixture is sensitive to the model's color perception and
  // cannot reliably distinguish dropped images from semantic errors.
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  final visualCode = List.generate(
    8,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
  canvas.drawRect(
    const ui.Rect.fromLTWH(10, 10, 700, 220),
    ui.Paint()
      ..color = const ui.Color(0xff000000)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 4,
  );
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(fontFamily: 'monospace', fontSize: 70),
        )
        ..pushStyle(ui.TextStyle(color: const ui.Color(0xff000000)))
        ..addText(visualCode);
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: 620));
  canvas.drawParagraph(paragraph, const ui.Offset(50, 75));
  final picture = recorder.endRecording();
  final image = await picture.toImage(720, 240);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  paragraph.dispose();
  await _stageAcpFile(tester, 'acp-image.png', data!.buffer.asUint8List());
  const imagePrompt =
      'Read the eight-character code printed inside the rectangular frame in the attached image. Reply with only the code exactly as shown. Do not use tools.';
  await _sendPromptThroughUi(tester, imagePrompt);
  await _waitForDaemonCodexFinalSent(
    daemonStateRoot: daemonStateRoot,
    runtimeAgentDid: agent.agentDid,
    prompt: imagePrompt,
    expectedReply: visualCode,
    runtimePluginId: 'acp',
  );
  await _waitForAppIncomingCodexReply(
    messaging: messages,
    runtimeAgentDid: agent.agentDid,
    expectedReply: visualCode,
  );
  await _waitForVisibleCodexReply(tester: tester, expectedReply: visualCode);
  await _markCodingCase('$prefix-008');
}

Future<AppSession> _prepareRealAppIdentity(
  OnboardingService onboarding,
  OnboardingSupportService onboardingSupport,
  _CodexAgentRealBackendConfig config,
) async {
  await onboardingSupport.sendRegistrationOtp(
    phone: config.otpPhone,
    handle: config.appHandle,
    domain: config.environment.didDomain,
    fullHandle: '${config.appHandle}.${config.environment.didDomain}',
  );
  final register = await _tryAppIdentityAction(
    () => onboarding.registerHandleWithPhone(
      phone: config.otpPhone,
      otp: config.otpCode,
      handle: config.appHandle,
      nickName: 'Codex Agent E2E ${config.runId}',
    ),
  );
  if (register.session != null) {
    return register.session!;
  }
  throw StateError(
    'App register failed: ${_sanitizeDiagnostic(register.errorText, config)}',
  );
}

Future<_AppIdentityAttempt> _tryAppIdentityAction(
  Future<IdentityRegistrationResult> Function() action,
) async {
  try {
    final result = await action();
    final session = result.identity;
    if (result.status == IdentityRegistrationStatus.registered &&
        session != null) {
      return _AppIdentityAttempt.session(session);
    }
    return _AppIdentityAttempt.error('join_required');
  } on Object catch (error) {
    return _AppIdentityAttempt.error(error.toString());
  }
}

Future<_DaemonInstallResult> _installRealDaemon({
  required _CodexAgentRealBackendConfig config,
  required AgentInventoryPort inventory,
  required String controllerDid,
}) async {
  final token = await inventory.issueDaemonToken(
    controllerDid: controllerDid,
    clientPlatform: 'linux',
    controllerHandle: config.appHandle,
  );
  final result = await _runProcess(
    config.daemonBinary,
    <String>[
      'install',
      '--base-url',
      config.environment.baseUrl,
      '--no-service',
      '--print-json',
      '--state-root',
      config.daemonStateRoot,
    ],
    environment: {
      ..._daemonEnvironment(config),
      'AWIKI_DAEMON_INSTALL_TOKEN': token.token,
    },
    timeout: const Duration(minutes: 2),
    secrets: <String>[token.token, ...config.secrets],
  );
  if (result.exitCode != 0) {
    throw StateError(
      'daemon install failed: ${result.sanitizedSummary(config)}',
    );
  }
  final json = jsonDecode(result.stdout);
  if (json is! Map) {
    throw StateError('daemon install did not return a JSON object.');
  }
  return _DaemonInstallResult(
    daemonDid: json['daemon_agent_did']?.toString() ?? '',
    handle: json['handle']?.toString() ?? config.daemonHandle,
  );
}

Future<Process> _startRealDaemon({
  required _CodexAgentRealBackendConfig config,
  String maxRuntimeMs = _codexDaemonMaxRuntimeMs,
}) async {
  final readyFile = File(config.daemonReadyFile);
  if (readyFile.existsSync()) {
    readyFile.deleteSync();
  }
  final process = await Process.start(
    config.daemonBinary,
    <String>[
      'foreground',
      '--state-root',
      config.daemonStateRoot,
      '--ready-file',
      config.daemonReadyFile,
      '--max-runtime-ms',
      maxRuntimeMs,
      '--poll-interval-ms',
      '100',
    ],
    environment: _daemonEnvironment(config),
    includeParentEnvironment: true,
    runInShell: false,
  );
  process.stdout.transform(utf8.decoder).listen((_) {}, onError: (_) {});
  process.stderr.transform(utf8.decoder).listen((_) {}, onError: (_) {});
  return process;
}

Map<String, String> _daemonEnvironment(_CodexAgentRealBackendConfig config) {
  final environment = _loadDaemonEnvFile(config);
  final parentPassthrough = Platform
      .environment['AWIKI_DAEMON_CLI_ENV_PASSTHROUGH']
      ?.trim();
  environment.putIfAbsent(
    'AWIKI_DAEMON_CLI_ENV_PASSTHROUGH',
    () => parentPassthrough?.isNotEmpty == true
        ? parentPassthrough!
        : _daemonCliProxyPassthrough,
  );
  environment.addAll(<String, String>{
    'AWIKI_DAEMON_SERVICE_BASE_URL': config.environment.baseUrl,
    'AWIKI_DAEMON_USER_SERVICE_BASE_URL': config.environment.userServiceUrl,
    'AWIKI_DAEMON_MESSAGE_SERVICE_BASE_URL':
        config.environment.messageServiceUrl,
    'AWIKI_DAEMON_DID_DOMAIN': config.environment.didDomain,
    'AWIKI_DAEMON_ALLOW_PLAIN_CONTROL': '1',
  });
  return environment;
}

Map<String, String> _loadDaemonEnvFile(_CodexAgentRealBackendConfig config) {
  final path = config.daemonEnvFile;
  if (path == null || path.trim().isEmpty) {
    return <String, String>{};
  }
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError(
      'daemon env file was configured but not found: '
      '${_sanitizeDiagnostic(path, config)}',
    );
  }
  return _parseDaemonEnvFile(file.readAsLinesSync(), path);
}

List<String> _daemonEnvFileSecretValues(String? path) {
  if (path == null || path.trim().isEmpty) {
    return const <String>[];
  }
  final file = File(path);
  if (!file.existsSync()) {
    return const <String>[];
  }
  return _parseDaemonEnvFile(
    file.readAsLinesSync(),
    path,
  ).values.where((value) => value.trim().isNotEmpty).toList(growable: false);
}

Map<String, String> _parseDaemonEnvFile(List<String> lines, String path) {
  final values = <String, String>{};
  for (var index = 0; index < lines.length; index += 1) {
    var line = lines[index].trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    if (line.startsWith('export ')) {
      line = line.substring('export '.length).trimLeft();
    }
    final equals = line.indexOf('=');
    if (equals <= 0) {
      throw StateError('Invalid daemon env file line ${index + 1} in $path.');
    }
    final key = line.substring(0, equals).trim();
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
      throw StateError(
        'Invalid daemon env variable name on line ${index + 1} in $path.',
      );
    }
    values[key] = _decodeEnvValue(line.substring(equals + 1).trim());
  }
  return values;
}

String _decodeEnvValue(String value) {
  if (value.length >= 2) {
    final quote = value.codeUnitAt(0);
    final last = value.codeUnitAt(value.length - 1);
    if ((quote == 0x22 && last == 0x22) || (quote == 0x27 && last == 0x27)) {
      final inner = value.substring(1, value.length - 1);
      if (quote == 0x22) {
        return inner
            .replaceAll(r'\"', '"')
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\t', '\t')
            .replaceAll(r'\\', '\\');
      }
      return inner.replaceAll(r"'\''", "'");
    }
  }
  return value;
}

Future<void> _waitForAgentInventoryEntry({
  required WidgetTester tester,
  required AgentsController agents,
  required String agentDid,
  required String handle,
}) async {
  Object? lastState;
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    await agents.load();
    await _pumpFrame(tester);
    final state = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    ).read(agentsProvider);
    lastState = _agentsDebugSummary(state);
    final agent = _agentByDid(state, agentDid);
    if (agent != null && agent.handle == handle) {
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail(
    'Timed out waiting for agent inventory entry $agentDid/$handle. '
    'Last agents: ${lastState ?? '<none>'}',
  );
}

Future<void> _waitForDaemonGenericCliCapability({
  required WidgetTester tester,
  required AgentsController agents,
  required String daemonDid,
  bool acp = false,
}) async {
  Object? lastState;
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    await agents.load();
    agents.select(daemonDid);
    await _pumpFrame(tester);
    final state = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    ).read(agentsProvider);
    lastState = _agentsDebugSummary(state);
    final daemon = _agentByDid(state, daemonDid);
    if (daemon != null && _daemonSupportsCodex(daemon, acp: acp)) {
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail(
    'Timed out waiting for daemon generic-cli capability for $daemonDid. '
    'Last agents: ${lastState ?? '<none>'}',
  );
}

Future<AgentSummary> _waitForRuntimeAgentByHandle({
  required WidgetTester tester,
  required String daemonDid,
  required String handle,
  bool acp = false,
  bool hermes = false,
}) async {
  Object? lastState;
  final deadline = DateTime.now().add(Duration(seconds: acp ? 150 : 60));
  while (DateTime.now().isBefore(deadline)) {
    await _pumpFrame(tester);
    final state = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    ).read(agentsProvider);
    lastState = _agentsDebugSummary(state);
    final matchingRuntimes = state.agents
        .where(
          (agent) =>
              agent.isRuntime &&
              agent.daemonAgentDid == daemonDid &&
              agent.handle?.trim().toLowerCase() ==
                  handle.trim().toLowerCase() &&
              (acp
                  ? (agent.runtime == 'acp' ||
                        RuntimeAgentKind.values.any(
                          (kind) => kind.isAcp && kind.runtime == agent.runtime,
                        ))
                  : hermes
                  ? agent.runtime == 'hermes'
                  : (agent.runtime == 'codex' ||
                        agent.runtime == 'generic-cli')),
        )
        .toList(growable: false);
    final hasMatchingPending = state.pendingRuntimeCreations.any(
      (pending) =>
          pending.daemonAgentDid == daemonDid &&
          pending.handle.trim().toLowerCase() == handle.trim().toLowerCase(),
    );
    if (hasMatchingPending || matchingRuntimes.isNotEmpty) {
      _expectSingleRuntimeAgentRowForHandle(handle);
    }
    if (matchingRuntimes.length > 1) {
      fail(
        'Expected one canonical Codex runtime for handle=$handle, found '
        '${matchingRuntimes.length}. Last agents: $lastState',
      );
    }
    if (matchingRuntimes.length == 1 && !hasMatchingPending) {
      return matchingRuntimes.single;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  Object? routeDiagnostic;
  if (acp) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final candidates = container
        .read(agentsProvider)
        .agents
        .where((agent) => agent.handle == handle);
    if (candidates.isNotEmpty) {
      final started = Stopwatch()..start();
      try {
        final route = await container
            .read(directoryApplicationServiceProvider)
            .resolvePeer(candidates.first.agentDid)
            .timeout(const Duration(seconds: 25));
        routeDiagnostic = {
          'elapsedMs': started.elapsedMilliseconds,
          'didMatches': route.did == candidates.first.agentDid,
          'conversationId': route.conversationId,
          'warnings': route.warnings,
        };
      } catch (error) {
        routeDiagnostic = {
          'elapsedMs': started.elapsedMilliseconds,
          'error': error.toString(),
        };
      }
    }
  }
  fail(
    'Timed out waiting for Codex runtime handle=$handle. '
    'Last agents: ${lastState ?? '<none>'}. Route diagnostic: $routeDiagnostic',
  );
}

Future<void> _expectSingleRuntimeAgentRow({
  required WidgetTester tester,
  required AgentSummary runtime,
}) async {
  final runtimeTile = find.byKey(Key('agent-list-tile-${runtime.agentDid}'));
  await _pumpUntil(
    tester,
    () => runtimeTile.evaluate().length == 1,
    timeout: const Duration(seconds: 10),
    description: 'canonical Codex runtime row to become visible',
  );
  expect(runtimeTile, findsOneWidget);
  _expectSingleRuntimeAgentRowForHandle(runtime.handle!);
}

void _expectSingleRuntimeAgentRowForHandle(String handle) {
  expect(
    find.bySemanticsIdentifier(
      'e2e-agent-runtime-row-${handle.trim().toLowerCase()}',
    ),
    findsOneWidget,
  );
}

Future<void> _sendPromptThroughUi(WidgetTester tester, String prompt) async {
  final input = find.bySemanticsIdentifier('e2e-chat-input');
  await _pumpUntil(
    tester,
    () => input.evaluate().isNotEmpty,
    timeout: const Duration(seconds: 15),
    description: 'Codex chat input to become visible',
  );
  await tester.ensureVisible(input);
  await enterStableCodingAgentText(
    expected: prompt,
    read: () => tester
        .widget<EditableText>(
          find.descendant(
            of: input,
            matching: find.byType(EditableText),
            matchRoot: true,
          ),
        )
        .controller
        .text,
    enter: () async {
      await tester.tap(input);
      await tester.pump();
      await tester.showKeyboard(input);
      tester.testTextInput.enterText(prompt);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    },
  );
  await _pumpUntil(
    tester,
    () => find
        .bySemanticsIdentifier('e2e-chat-send-button')
        .evaluate()
        .isNotEmpty,
    timeout: const Duration(seconds: 60),
    description: 'chat send button enabled after the previous send completes',
    lastError: () {
      final field = tester.widget<EditableText>(
        find.descendant(
          of: input,
          matching: find.byType(EditableText),
          matchRoot: true,
        ),
      );
      final buttons = find.byKey(const Key('chat-send-button'));
      final button = buttons.evaluate().isEmpty
          ? null
          : tester.widget(buttons.first);
      return {
        'textLength': field.controller.text.length,
        'expectedLength': prompt.length,
        'composing': field.controller.value.composing.toString(),
        'focused': field.focusNode.hasFocus,
        'buttonType': button.runtimeType.toString(),
        'enabled': button is AppPressable ? button.enabled : null,
        'dialogs': find.byType(CupertinoAlertDialog).evaluate().length,
      };
    },
  );
  await _tapFirstFound(tester, <Finder>[
    find.bySemanticsIdentifier('e2e-chat-send-button'),
  ]);
  await _pumpFrame(tester);
}

Future<String> _waitForDaemonCodexFinalSent({
  required String daemonStateRoot,
  required String runtimeAgentDid,
  required String prompt,
  required String expectedReply,
  String runtimePluginId = 'generic-cli',
  bool allowProgressText = false,
}) async {
  final dbPath = '${daemonStateRoot.replaceAll(RegExp(r'/+$'), '')}/daemon.db';
  String lastState = 'daemon.db not found';
  String finalText = '';
  await _poll(
    description: 'daemon sent Codex runtime final reply "$expectedReply"',
    action: () async {
      final dbFile = File(dbPath);
      if (!dbFile.existsSync()) {
        lastState = 'daemon.db not found at $dbPath';
        return false;
      }
      final db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        final rows = await db.rawQuery(
          '''
          SELECT t.task_id, t.status AS task_status,
                 r.run_id, r.runtime_plugin_id, r.status AS run_status,
                 f.status AS final_status, f.final_text AS final_text,
                 f.message_id AS final_message_id,
                 f.recipient_did AS recipient_did,
                 f.final_source AS final_source,
                 c.driver_id AS driver_id,
                 c.status AS driver_run_status,
                 c.final_output_path AS driver_final_output_path
          FROM runtime_task t
          LEFT JOIN runtime_run r ON r.task_id = t.task_id
          LEFT JOIN runtime_final_outbox f ON f.run_id = r.run_id
          LEFT JOIN cli_driver_run c ON c.run_id = r.run_id
          WHERE t.agent_did = ? AND ($codingAgentCurrentPromptSql) = ?
          ORDER BY t.created_at_ms DESC
          LIMIT 1
          ''',
          <Object?>[runtimeAgentDid, prompt],
        );
        if (rows.isEmpty) {
          lastState = 'no runtime task for runtime=$runtimeAgentDid prompt';
          return false;
        }
        final row = rows.first;
        lastState = _runtimeRowDebugState(row);
        if (_runtimeRowFailed(row)) {
          fail(
            'Codex runtime finished with failure before expected reply. '
            'Last state: $lastState',
          );
        }
        final matches = matchesCodingAgentFinal(
          row['final_text'],
          expectedReply,
          allowProgressText: allowProgressText,
        );
        if (row['run_status'] == 'finished' &&
            row['final_status'] == 'sent' &&
            !matches) {
          fail(
            'Runtime delivered a different final reply. Last state: $lastState',
          );
        }
        finalText = row['final_text']?.toString() ?? '';
        return row['runtime_plugin_id'] == runtimePluginId &&
            row['run_status'] == 'finished' &&
            row['final_status'] == 'sent' &&
            row['final_message_id'] != null &&
            matches;
      } finally {
        await db.close();
      }
    },
    timeout: _codexRuntimeFinalTimeout,
    interval: const Duration(seconds: 1),
    lastError: () => lastState,
  );
  return finalText;
}

Future<ChatMessage> _waitForAppIncomingCodexReply({
  required MessagingService messaging,
  required String runtimeAgentDid,
  required String expectedReply,
}) async {
  ChatMessage? matched;
  Object? lastState;
  await _poll(
    description: 'App local history contains incoming Codex reply',
    action: () async {
      final messages = await messaging.loadHistory(
        AppThreadRef.direct(runtimeAgentDid),
        limit: 50,
      );
      lastState = _chatHistoryDebugSummary(messages);
      for (final message in messages) {
        if (!message.isMine &&
            message.senderDid == runtimeAgentDid &&
            message.content == expectedReply) {
          matched = message;
          return true;
        }
      }
      return false;
    },
    timeout: const Duration(seconds: 90),
    interval: const Duration(seconds: 2),
    lastError: () => lastState,
  );
  return matched!;
}

String _runtimeRowDebugState(Map<String, Object?> row) {
  final debug = Map<String, Object?>.from(row);
  final finalOutputPath = row['driver_final_output_path']?.toString();
  if (finalOutputPath != null && finalOutputPath.trim().isNotEmpty) {
    final file = File(finalOutputPath);
    if (file.existsSync()) {
      final text = file.readAsStringSync();
      debug['driver_final_output_tail'] = text.length <= 600
          ? text
          : text.substring(text.length - 600);
    }
  }
  return jsonEncode(debug);
}

bool _runtimeRowFailed(Map<String, Object?> row) {
  final runStatus = row['run_status']?.toString();
  final finalStatus = row['final_status']?.toString();
  final driverRunStatus = row['driver_run_status']?.toString();
  return runStatus == 'failed' ||
      finalStatus == 'failed' ||
      finalStatus == 'dead_letter' ||
      driverRunStatus == 'failed';
}

Future<void> _waitForVisibleCodexReply({
  required WidgetTester tester,
  required String expectedReply,
}) async {
  final replyBubble = find.bySemanticsIdentifier(
    e2eMessageIdentifier(expectedReply),
  );
  await _pumpUntil(
    tester,
    () {
      return replyBubble.evaluate().isNotEmpty;
    },
    timeout: const Duration(seconds: 90),
    description: 'Codex reply bubble visible in App UI',
    lastError: () => 'The expected reply bubble did not render in time.',
  );
  expect(replyBubble, findsOneWidget);
}

String _chatHistoryDebugSummary(List<ChatMessage> messages) {
  return jsonEncode(
    messages
        .map(
          (message) => <String, Object?>{
            'remoteId': message.remoteId,
            'senderDid': _shortDid(message.senderDid),
            'isMine': message.isMine,
            'content': message.content,
            'sendState': message.sendState.name,
          },
        )
        .toList(),
  );
}

Future<void> _tapFirstFound(WidgetTester tester, List<Finder> finders) async {
  for (final finder in finders) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder.first);
      await tester.tap(finder.first);
      await _pumpFrame(tester);
      return;
    }
  }
  fail('None of the expected UI targets were found: $finders');
}

Future<void> _pumpFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _waitForFile(String path) async {
  await _poll(
    description: 'file exists: $path',
    action: () async => File(path).existsSync(),
    timeout: const Duration(seconds: 30),
    interval: const Duration(milliseconds: 250),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required Duration timeout,
  String description = 'UI condition',
  Object? Function()? lastError,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
  final detail = lastError == null ? null : lastError();
  fail(
    'Timed out waiting for $description.'
    '${detail == null ? '' : ' Last error: $detail'}',
  );
}

Future<void> _poll({
  required String description,
  required Future<bool> Function() action,
  Duration timeout = const Duration(seconds: 90),
  Duration interval = const Duration(seconds: 2),
  Object? Function()? lastError,
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? caughtError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await action()) {
        return;
      }
    } on TestFailure {
      rethrow;
    } on Object catch (error) {
      caughtError = error;
    }
    await Future<void>.delayed(interval);
  }
  final detail = lastError == null ? caughtError : lastError() ?? caughtError;
  fail(
    'Timed out waiting for $description.'
    '${detail == null ? '' : ' Last error: $detail'}',
  );
}

AgentSummary? _agentByDid(AgentsState state, String agentDid) {
  final normalized = agentDid.trim();
  for (final agent in state.agents) {
    if (agent.agentDid == normalized) {
      return agent;
    }
  }
  return null;
}

String _agentsDebugSummary(AgentsState state) {
  return jsonEncode(
    state.agents.map((agent) {
      final diagnostics = agent.latest.diagnosticsSummary;
      final configSummary = diagnostics['config_summary'];
      return <String, Object?>{
        'did': _shortDid(agent.agentDid),
        'kind': agent.kind.name,
        'daemon': _shortDid(agent.daemonAgentDid),
        'runtime': agent.runtime,
        'handle': agent.handle,
        'displayName': agent.displayName,
        'status': agent.latest.status,
        'activeState': agent.activeState,
        'diagnosticsKeys': diagnostics.keys.toList()..sort(),
        'configSummaryKeys': configSummary is Map
            ? (configSummary.keys.map((key) => key.toString()).toList()..sort())
            : const <String>[],
      };
    }).toList(),
  );
}

String? _shortDid(String? did) {
  if (did == null || did.length <= 32) {
    return did;
  }
  return '${did.substring(0, 24)}...${did.substring(did.length - 6)}';
}

bool _daemonSupportsCodex(AgentSummary daemon, {bool acp = false}) {
  final config = _objectMap(daemon.latest.diagnosticsSummary['config_summary']);
  final genericCli = _objectMap(config[acp ? 'acp' : 'generic_cli']);
  final schemaVersion = _intValue(genericCli['capability_schema_version']);
  final drivers = _stringSet(genericCli['supported_drivers']);
  return schemaVersion == 1 &&
      (acp
          ? drivers.containsAll([
              'opencode',
              'gemini',
              'kimi',
              'deepseek-harness',
            ])
          : drivers.contains('codex'));
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return value.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
}

Set<String> _stringSet(Object? value) {
  if (value is! Iterable) {
    return const <String>{};
  }
  return value.map((item) => item.toString()).toSet();
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '');
}

String _codexRuntimeHandle(String runId) {
  final suffix = runId
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  final nonce = DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(36);
  final handle = 'codex-e2e-${suffix.isEmpty ? 'run' : suffix}-$nonce';
  if (handle.length <= 63) {
    return handle;
  }
  return handle.substring(0, 63).replaceAll(RegExp(r'-$'), 'x');
}

String _defaultCodexExpectedReply(String runId) {
  final suffix = runId
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return 'OK-CODEX-${suffix.isEmpty ? 'E2E' : suffix}';
}

String _defaultCodexPrompt(String runId) {
  return 'Reply exactly ${_defaultCodexExpectedReply(runId)} and nothing else';
}

String _sanitizeDiagnostic(String input, _CodexAgentRealBackendConfig config) {
  var output = input;
  for (final secret in config.secrets) {
    final trimmed = secret.trim();
    if (trimmed.isNotEmpty) {
      output = output.replaceAll(trimmed, '<redacted>');
    }
  }
  return output.replaceAll(
    RegExp(
      r'(otp|token|jwt|private[_-]?key|secret|authorization)=([^\s]+)',
      caseSensitive: false,
    ),
    '<redacted-key>=<redacted>',
  );
}

void _terminateProcess(Process process) {
  if (process.kill(ProcessSignal.sigterm)) {
    return;
  }
  process.kill(ProcessSignal.sigkill);
}

class _CodexAgentRealBackendConfig {
  const _CodexAgentRealBackendConfig({
    required this.runId,
    required this.platform,
    required this.environment,
    required this.appHandle,
    required this.otpPhone,
    required this.otpCode,
    required this.appStateRoot,
    required this.reusePreparedIdentity,
    required this.daemonBinary,
    required this.daemonStateRoot,
    required this.daemonReadyFile,
    required this.daemonHandle,
    required this.daemonEnvFile,
    required this.enabled,
    required this.realBackend,
    required this.prompt,
    required this.expectedReply,
  });

  static _CodexAgentRealBackendConfig? tryLoad({
    bool acp = false,
    bool hermes = false,
  }) {
    const focusConfig = String.fromEnvironment('AWIKI_ACP_FOCUS_CONFIG');
    final file = File(
      acp
          ? (focusConfig.isEmpty
                ? '.e2e/acp-agent/current/run_config.json'
                : focusConfig)
          : hermes
          ? '.e2e/hermes-agent/current/run_config.json'
          : _codexAgentRunConfigPath,
    );
    if (!file.existsSync()) {
      return null;
    }
    final raw = jsonDecode(file.readAsStringSync());
    if (raw is! Map) {
      throw StateError('$_codexAgentRunConfigPath must be a JSON object.');
    }
    final map = _stringKeyMap(raw, path: _codexAgentRunConfigPath);
    final codexAgent = _optionalMapAt(
      map,
      acp
          ? 'acpAgent'
          : hermes
          ? 'hermesAgent'
          : 'codexAgent',
    );
    final enabled = _boolConfig(codexAgent, 'enabled');
    final realBackend = _boolConfig(codexAgent, 'realBackend');
    if (!enabled || !realBackend) {
      return null;
    }
    final service = _mapAt(map, 'service');
    final otp = _mapAt(map, 'otp');
    final protectedOtp = ProtectedOtpConfig.load(
      _requiredConfig(otp, 'localConfigPath', 'otp.localConfigPath'),
    );
    final accounts = _mapAt(map, 'accounts');
    final appUser = _mapAt(accounts, 'appUser');
    final app = _mapAt(map, 'app');
    final daemon = _mapAt(map, 'daemon');
    final baseUrl = _requiredConfig(service, 'baseUrl', 'service.baseUrl');
    final didDomain = _requiredConfig(
      service,
      'didDomain',
      'service.didDomain',
    );
    final runId = _requiredConfig(map, 'runId', 'runId');
    final expectedReply =
        _optionalConfig(codexAgent, 'expectedReply') ??
        _defaultCodexExpectedReply(runId);
    return _CodexAgentRealBackendConfig(
      runId: runId,
      platform: _requiredConfig(map, 'platform', 'platform'),
      environment: AwikiEnvironmentConfig(
        baseUrl: baseUrl,
        userServiceUrl: _optionalConfig(service, 'userServiceUrl') ?? baseUrl,
        messageServiceUrl:
            _optionalConfig(service, 'messageServiceUrl') ?? baseUrl,
        mailServiceUrl: _optionalConfig(service, 'mailServiceUrl') ?? baseUrl,
        didDomain: didDomain,
        anpServiceUrl:
            _optionalConfig(service, 'anpServiceUrl') ?? '$baseUrl/anp-im/rpc',
        anpServiceDid:
            _optionalConfig(service, 'anpServiceDid') ?? 'did:wba:$didDomain',
        agentImEnabled: true,
      ),
      appHandle: _requiredConfig(appUser, 'handle', 'accounts.appUser.handle'),
      otpPhone: protectedOtp.phone,
      otpCode: protectedOtp.code,
      appStateRoot: _requiredConfig(app, 'stateRoot', 'app.stateRoot'),
      reusePreparedIdentity: acp && app['reusePreparedIdentity'] == true,
      daemonBinary: _requiredConfig(daemon, 'binary', 'daemon.binary'),
      daemonStateRoot: _requiredConfig(daemon, 'stateRoot', 'daemon.stateRoot'),
      daemonReadyFile: _requiredConfig(daemon, 'readyFile', 'daemon.readyFile'),
      daemonHandle:
          _optionalConfig(daemon, 'handle') ??
          'codex-agent-daemon-${DateTime.now().millisecondsSinceEpoch}',
      daemonEnvFile: _optionalConfig(daemon, 'envFile'),
      enabled: enabled,
      realBackend: realBackend,
      prompt:
          _optionalConfig(codexAgent, 'prompt') ?? _defaultCodexPrompt(runId),
      expectedReply: expectedReply,
    );
  }

  final String runId;
  final String platform;
  final AwikiEnvironmentConfig environment;
  final String appHandle;
  final String otpPhone;
  final String otpCode;
  final String appStateRoot;
  final bool reusePreparedIdentity;
  final String daemonBinary;
  final String daemonStateRoot;
  final String daemonReadyFile;
  final String daemonHandle;
  final String? daemonEnvFile;
  final bool enabled;
  final bool realBackend;
  final String prompt;
  final String expectedReply;

  TargetPlatform get targetPlatform {
    return platform == 'linux' ? TargetPlatform.linux : TargetPlatform.macOS;
  }

  List<String> get secrets => <String>[
    otpPhone,
    otpCode,
    appStateRoot,
    daemonStateRoot,
    daemonReadyFile,
    if (daemonEnvFile != null) daemonEnvFile!,
    ..._daemonEnvFileSecretValues(daemonEnvFile),
  ].where((value) => value.trim().isNotEmpty).toList(growable: false);
}

class _DaemonInstallResult {
  const _DaemonInstallResult({required this.daemonDid, required this.handle});

  final String daemonDid;
  final String handle;
}

class _AppIdentityAttempt {
  const _AppIdentityAttempt._({this.session, required this.errorText});

  factory _AppIdentityAttempt.session(AppSession session) {
    return _AppIdentityAttempt._(session: session, errorText: '');
  }

  factory _AppIdentityAttempt.error(String errorText) {
    return _AppIdentityAttempt._(errorText: errorText);
  }

  final AppSession? session;
  final String errorText;
}

class _ProcessResult {
  const _ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.secrets = const <String>[],
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final List<String> secrets;

  String sanitizedSummary(_CodexAgentRealBackendConfig config) {
    return _sanitizeDiagnostic(
      'exit=$exitCode stdout=$stdout stderr=$stderr',
      config,
    );
  }
}

Future<_ProcessResult> _runProcess(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  Duration timeout = const Duration(seconds: 45),
  List<String> secrets = const <String>[],
}) async {
  final result = await Process.run(
    executable,
    args,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell: false,
  ).timeout(timeout);
  return _ProcessResult(
    exitCode: result.exitCode,
    stdout: ((result.stdout as String?) ?? '').trim(),
    stderr: ((result.stderr as String?) ?? '').trim(),
    secrets: secrets,
  );
}

Map<String, Object?> _stringKeyMap(Object? value, {required String path}) {
  if (value is! Map) {
    throw StateError('$path must be a JSON object.');
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

Map<String, Object?> _mapAt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is Map) {
    return _stringKeyMap(value, path: key);
  }
  throw StateError('$key must be configured as an object.');
}

Map<String, Object?> _optionalMapAt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return const <String, Object?>{};
  }
  if (value is Map) {
    return _stringKeyMap(value, path: key);
  }
  throw StateError('$key must be configured as an object.');
}

String _requiredConfig(Map<String, Object?> map, String key, String name) {
  final value = _optionalConfig(map, key);
  if (value == null) {
    throw StateError('$name is required in $_codexAgentRunConfigPath.');
  }
  return value;
}

String? _optionalConfig(Map<String, Object?> map, String key) {
  final raw = map[key];
  final value = raw?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

bool _boolConfig(Map<String, Object?> map, String key) {
  final raw = map[key];
  return raw == true || raw?.toString().toLowerCase() == 'true';
}
