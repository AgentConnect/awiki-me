import 'dart:async';
import 'dart:convert';
import 'package:awiki_me/src/application/agent/runtime_client_inspection_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/thread_message_patch.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/runtime_client_installation.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/agents_page.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/agents/runtime_client_inspection_provider.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../test_support.dart';

Map<String, Object?> installationJson({
  String ready = 'opencode',
  String? version = '1.2.3',
}) => {
  'schema_version': 1,
  'clients': [
    for (final kind in RuntimeAgentKind.values)
      {
        'kind': kind.runtime,
        'status': kind.runtime == ready ? 'ready' : 'missing',
        'version': kind.runtime == ready ? version : null,
        'reason_code': kind.runtime == ready ? null : 'not_found',
      },
  ],
};

class FakeClientInspection implements RuntimeClientInspectionService {
  int calls = 0;
  bool? lastRefresh;
  String? lastDaemon;
  Completer<RuntimeClientInstallationReport>? pending;
  RuntimeClientInstallationReport report =
      RuntimeClientInstallationReport.parse(installationJson());
  @override
  MessagingService get messages => throw UnimplementedError();
  @override
  Future<RuntimeClientInstallationReport> inspect(
    String daemonDid, {
    bool refresh = false,
  }) async {
    calls++;
    lastRefresh = refresh;
    lastDaemon = daemonDid;
    return pending == null ? report : pending!.future;
  }
}

const installationDaemon = AgentSummary(
  agentDid: 'did:agent:daemon',
  kind: AgentKind.daemon,
  displayName: 'Mac Studio',
  activeState: 'active',
  latest: AgentLatestStatus(
    status: 'ready',
    diagnosticsSummary: {
      'config_summary': {
        'runtime_client_detection': {'schema_version': 1},
        'acp': {
          'capability_schema_version': 1,
          'supported_drivers': [
            'hermes',
            'codex',
            'claude-code',
            'opencode',
            'gemini',
            'kimi',
            'deepseek-harness',
          ],
        },
      },
    },
  ),
);

Widget installationSurface(
  FakeClientInspection service, {
  FakeAgentControlService? control,
  double textScale = 1,
}) => buildLocalizedTestApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: const AgentsWorkspacePage(),
    ),
  ),
  session: const SessionIdentity(
    did: 'did:human:me',
    credentialName: 'default',
    displayName: 'Me',
  ),
  providerOverrides: [
    agentControlServiceProvider.overrideWithValue(
      control ?? (FakeAgentControlService()..agents = [installationDaemon]),
    ),
    runtimeClientInspectionServiceProvider.overrideWithValue(service),
  ],
);

Future<void> openInstallationDialog(
  WidgetTester tester,
  FakeClientInspection service, {
  FakeAgentControlService? control,
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(installationSurface(service, control: control));
  await tester.pumpAndSettle();
  await tester.tap(find.text('创建 Agent'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'missing host Node has one shared guide and leaves other clients usable',
    (tester) async {
      final json = installationJson(ready: 'hermes');
      for (final row
          in (json['clients'] as List).cast<Map<String, Object?>>()) {
        if (['codex', 'claude-code'].contains(row['kind'])) {
          row['status'] = 'unavailable';
          row['reason_code'] = 'node_missing';
        }
      }
      final service = FakeClientInspection()
        ..report = RuntimeClientInstallationReport.parse(json);
      await openInstallationDialog(tester, service);
      expect(find.byKey(const Key('agent-node-setup')), findsOneWidget);
      expect(find.byKey(const Key('agent-node-download')), findsOneWidget);
      expect(find.text('宿主机未检测到 Node.js。'), findsNWidgets(2));
      expect(find.text('Hermes'), findsWidgets);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('agent-node-download')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final closeEarly in [false, true]) {
    testWidgets(
      'slow creation stays single-flight with late confirmation; closed: $closeEarly',
      (tester) async {
        final service = FakeClientInspection();
        final control = DelayedCreationControl()..agents = [installationDaemon];
        await openInstallationDialog(tester, service, control: control);
        control.controller = ProviderScope.containerOf(
          tester.element(find.byType(AgentsWorkspacePage)),
        ).read(agentsProvider.notifier);
        await tester.enterText(
          find.byKey(const Key('agent-create-name-field')),
          'Later',
        );
        await tester.enterText(
          find.byKey(const Key('agent-create-handle-field')),
          'later',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('创建').last);
        await tester.pumpAndSettle();
        expect(find.text('创建中…'), findsOneWidget);
        await tester.pump(const Duration(seconds: 95));
        await tester.pumpAndSettle();
        expect(find.text('等待确认'), findsOneWidget);
        expect(find.text('创建中…'), findsNothing);
        expect(
          tester
              .widget<CupertinoTextField>(
                find.byKey(const Key('agent-create-handle-field')),
              )
              .readOnly,
          isTrue,
        );
        expect(control.creates, 1);
        if (closeEarly) {
          await tester.tap(find.text('关闭'));
          await tester.pumpAndSettle();
        }
        control.succeed();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('agent-create-name-field')), findsNothing);
        expect(control.creates, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test(
    'installation parser is forward compatible and rejects ambiguous records',
    () {
      final report = RuntimeClientInstallationReport.parse(installationJson());
      expect(report.clients.length, 7);
      expect(report.clients[RuntimeAgentKind.opencode]!.ready, isTrue);
      expect(report.clients[RuntimeAgentKind.hermes]!.ready, isFalse);
      final unknown = RuntimeClientInstallationReport.parse({
        'schema_version': 1,
        'clients': [
          {'kind': 'new-product', 'status': 'ready'},
          {'kind': 'kimi', 'status': 'future-state'},
        ],
      });
      expect(unknown.clients[RuntimeAgentKind.kimi]!.ready, isFalse);
      expect(
        () => RuntimeClientInstallationReport.parse({
          'schema_version': 9,
          'clients': [],
        }),
        throwsFormatException,
      );
      expect(
        () => RuntimeClientInstallationReport.parse({
          'schema_version': 1,
          'clients': [
            {'kind': 'kimi', 'status': 'ready'},
            {'kind': 'kimi', 'status': 'missing'},
          ],
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'controller coalesces clicks and ignores completion after disposal',
    () async {
      final service = FakeClientInspection()..pending = Completer();
      final controller = RuntimeClientInspectionController(
        service,
        'remote-linux',
      );
      final future = controller.inspect();
      await controller.inspect(refresh: true);
      expect(service.calls, 1);
      expect(service.lastDaemon, 'remote-linux');
      controller.dispose();
      service.pending!.complete(service.report);
      await future;
    },
  );

  test('inspection accepts only the matching committed daemon reply', () async {
    final messages = InspectionMessages();
    final report = await RuntimeClientInspectionService(
      messages,
    ).inspect('did:agent:daemon', refresh: true);
    expect(messages.sent?['args'], {'refresh': true});
    expect(report.clients[RuntimeAgentKind.opencode]!.ready, isTrue);
    expect(messages.patches.hasListener, isFalse);
    await messages.patches.close();
  });

  testWidgets(
    'host installation controls choices and refresh preserves edited fields',
    (tester) async {
      final service = FakeClientInspection();
      await openInstallationDialog(tester, service);
      expect(find.text('检测 Mac Studio 所在宿主机的客户端。'), findsOneWidget);
      expect(find.text('已检测到 · 1.2.3'), findsOneWidget);
      expect(find.text('未检测到'), findsNWidgets(6));
      await tester.tap(find.text('Hermes').last);
      final name = find.byKey(const Key('agent-create-name-field'));
      await tester.enterText(name, 'My helper');
      final handle = find.byKey(const Key('agent-create-handle-field'));
      await tester.enterText(handle, 'my-helper');
      await tester.pumpAndSettle();
      service.report = RuntimeClientInstallationReport.parse(
        installationJson(ready: 'kimi'),
      );
      await tester.tap(find.byKey(const Key('agent-clients-refresh')));
      await tester.pumpAndSettle();
      expect(service.calls, 2);
      expect(service.lastRefresh, isTrue);
      expect(find.text('My helper'), findsOneWidget);
      expect(find.text('my-helper'), findsOneWidget);
      final create = tester.widget<AppPrimaryButton>(
        find.widgetWithText(AppPrimaryButton, '创建'),
      );
      expect(create.onPressed, isNull);
      await tester.tap(find.text('Kimi Code CLI').last);
      await tester.pumpAndSettle();
      expect(find.text('My helper'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final version in <String?>['0.15.1rc2+local', null]) {
    testWidgets('Hermes remains selectable with optional version $version', (
      tester,
    ) async {
      final service = FakeClientInspection()
        ..report = RuntimeClientInstallationReport.parse(
          installationJson(ready: 'hermes', version: version),
        );
      await openInstallationDialog(tester, service);
      expect(
        find.text(version == null ? '已检测到' : '已检测到 · $version'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('agent-create-handle-field')),
        'hermes-version-test',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppPrimaryButton>(
              find.widgetWithText(AppPrimaryButton, '创建'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final scale in [1.0, 2.5]) {
    testWidgets('installation dialog fits narrow window at scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(installationSurface(FakeClientInspection()));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('agent-list-tile-did:agent:daemon')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建 Agent'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('agent-clients-refresh')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('failed refresh disables stale choices and retains draft', (
    tester,
  ) async {
    final service = FakeClientInspection();
    await openInstallationDialog(tester, service);
    await tester.enterText(
      find.byKey(const Key('agent-create-name-field')),
      'Keep draft',
    );
    service.pending = Completer();
    await tester.tap(find.byKey(const Key('agent-clients-refresh')));
    await tester.pump();
    expect(service.calls, 2);
    service.pending!.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('尚未确认'), findsNWidgets(7));
    expect(find.text('Keep draft'), findsOneWidget);
    expect(
      tester
          .widget<AppPrimaryButton>(find.widgetWithText(AppPrimaryButton, '创建'))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'removed host disables detection and creation in an open dialog',
    (tester) async {
      final service = FakeClientInspection();
      final control = FakeAgentControlService()..agents = [installationDaemon];
      await openInstallationDialog(tester, service, control: control);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AgentsWorkspacePage)),
      );
      control.agents = [];
      await container.read(agentsProvider.notifier).load();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppPrimaryButton>(
              find.widgetWithText(AppPrimaryButton, '创建'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('agent-clients-refresh')));
      await tester.pumpAndSettle();
      expect(service.calls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'identity change closes the dialog and ignores an old inspection',
    (tester) async {
      final service = FakeClientInspection();
      await openInstallationDialog(tester, service);
      service.pending = Completer();
      await tester.tap(find.byKey(const Key('agent-clients-refresh')));
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AgentsWorkspacePage)),
      );
      container.read(sessionProvider.notifier).clear();
      await tester.pump();
      service.pending!.complete(service.report);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('agent-clients-refresh')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed creation stays in the dialog without losing input', (
    tester,
  ) async {
    final service = FakeClientInspection();
    final control = FailedCreationControl()..agents = [installationDaemon];
    await openInstallationDialog(tester, service, control: control);
    control.controller = ProviderScope.containerOf(
      tester.element(find.byType(AgentsWorkspacePage)),
    ).read(agentsProvider.notifier);
    await tester.enterText(
      find.byKey(const Key('agent-create-name-field')),
      'Keep me',
    );
    await tester.enterText(
      find.byKey(const Key('agent-create-handle-field')),
      'keep-me',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建').last);
    await tester.pumpAndSettle();
    expect(find.text('Keep me'), findsOneWidget);
    expect(find.text('请在此 Daemon 的宿主机安装客户端，再重新检测。'), findsWidgets);
    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(AgentsWorkspacePage)),
      ).read(agentsProvider).pendingRuntimeCreations,
      isEmpty,
    );
    expect(control.creates, 1);
    await tester.pumpWidget(const SizedBox());
  });
}

class FailedCreationControl extends FakeAgentControlService {
  late AgentsController controller;
  int creates = 0;
  @override
  Future<void> createRuntimeAgent({
    required String daemonAgentDid,
    required String controllerDid,
    required RuntimeAgentCreateOptions options,
    String? clientRequestId,
  }) async {
    creates++;
    controller.applyControlPayload({
      'schema': 'awiki.agent.status.v1',
      'event_id': 'failed-create-$creates',
      'daemon_agent_did': daemonAgentDid,
      'state': 'failed',
      'result': {
        'command': 'runtime.agent.create',
        'client_request_id': clientRequestId,
        'error_code': 'runtime_client_not_found',
        'phase': 'client_readiness',
      },
    });
  }
}

class InspectionMessages extends FakeMessagingService
    implements CommittedControlMessagingService {
  InspectionMessages() : super(FakeAwikiGateway());
  final patches = StreamController<ThreadMessagePatch>.broadcast(sync: true);
  Map<String, Object?>? sent;
  @override
  Stream<ThreadMessagePatch> watchControlThreadPatches(
    AppThreadRef thread, {
    int limit = 100,
  }) => patches.stream;
  @override
  Future<ThreadMessagePatch> repairControlThreadStore(
    AppThreadRef thread, {
    int limit = 100,
  }) => throw UnimplementedError();
  @override
  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  }) async {
    sent = payload;
    ChatMessage reply(String sender, String command) => ChatMessage(
      localId: 'reply-$sender-$command',
      threadId: thread.stableId,
      senderDid: sender,
      content: '',
      createdAt: DateTime.utc(2026),
      isMine: false,
      sendState: MessageSendState.sent,
      payloadJson: jsonEncode({
        'schema': 'awiki.agent.status.v1',
        'daemon_agent_did': 'did:agent:daemon',
        'command_id': command,
        'state': 'ready',
        'result': {
          'command': 'runtime.clients.inspect',
          'installation': installationJson(),
        },
      }),
    );
    final correct = reply('did:agent:daemon', payload['command_id']! as String);
    patches.add(
      ThreadMessagePatch(
        kind: ThreadMessagePatchKind.reset,
        ownerDid: 'did:human:me',
        version: 1,
        threadKind: 'direct',
        threadId: thread.stableId,
        messages: [
          reply('did:attacker', payload['command_id']! as String),
          reply('did:agent:daemon', 'old'),
          correct,
        ],
      ),
    );
    return correct;
  }
}

class DelayedCreationControl extends FakeAgentControlService {
  late AgentsController controller;
  int creates = 0;
  String? request;
  RuntimeAgentCreateOptions? options;
  @override
  Future<void> createRuntimeAgent({
    required String daemonAgentDid,
    required String controllerDid,
    required RuntimeAgentCreateOptions options,
    String? clientRequestId,
  }) async {
    creates++;
    request = clientRequestId;
    this.options = options;
  }

  void succeed() => controller.applyControlPayload({
    'schema': 'awiki.agent.status.v1',
    'event_id': 'late-created',
    'daemon_agent_did': 'did:agent:daemon',
    'state': 'ready',
    'result': {
      'command': 'runtime.agent.create',
      'client_request_id': request,
      'runtime': options!.kind.runtime,
      'handle': options!.handle,
      'runtime_agent_did': 'did:agent:later',
    },
  });
}
