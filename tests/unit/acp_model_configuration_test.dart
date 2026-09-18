import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/domain/entities/agent/acp_session.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/acp_model_controller.dart';
import 'package:awiki_me/src/presentation/agents/acp_session_provider.dart';
import 'package:awiki_me/src/presentation/agents/acp_task_status.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'acp_runtime_test.dart' show RecordingControl, snapshot, control;

const scope = (agentDid: 'did:agent:runtime', conversationId: 'conversation-1');
Map<String, Object?> config({int revision = 1, String model = 'flash'}) => {
  ...snapshot(revision: revision),
  'active': null,
  'waiting': null,
  'model_id': model,
  'model_configuration_ready': true,
  'models': [
    {'id': 'flash', 'name': 'Flash'},
    {'id': 'pro', 'name': 'Pro'},
  ],
};
Map<String, Object?> result(Map<String, Object?> value) => {
  'prepared_session_key': value['session_key'],
  'sessions': [value],
};

void main() {
  test(
    'confirmation waits for Core routing and revision before releasing send',
    () async {
      var projection = const AcpProjection();
      final value = config(revision: 4, model: 'pro');
      final controller = _ModelHarness(
        scope,
        (_, __) async => result(value),
        () => projection,
      );
      addTearDown(controller.dispose);
      expect(
        await controller.select(AcpSession.parse(config())!, 'pro'),
        isTrue,
      );
      expect(controller.operation.phase, AcpModelPhase.synchronizing);
      for (final session in [
        AcpSession.parse(config(revision: 3))!,
        AcpSession.parse(value, localConversationId: 'foreign')!,
      ]) {
        controller.reconcile(AcpProjection(sessions: {session.key: session}));
        expect(controller.operation.blocksSending, isTrue);
      }
      final session = AcpSession.parse(value)!;
      projection = AcpProjection(sessions: {session.key: session});
      controller.reconcile(projection);
      expect(controller.operation.blocksSending, isFalse);
    },
  );

  test('a missing projection can retry the same confirmed command', () async {
    var projection = const AcpProjection();
    final calls = <(String, Map<String, Object?>)>[];
    final value = config(revision: 2);
    final controller = _ModelHarness(scope, (id, args) async {
      calls.add((id, args));
      return result(value);
    }, () => projection);
    addTearDown(controller.dispose);
    await controller.prepare();
    expect(controller.operation.phase, AcpModelPhase.synchronizing);
    final session = AcpSession.parse(value)!;
    projection = AcpProjection(sessions: {session.key: session});
    await controller.retry();
    expect(calls[0], calls[1]);
    expect(controller.operation.blocksSending, isFalse);
  });

  test(
    'timeout preserves command and original revision and prevents competing selection',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      final value = config(revision: 2, model: 'pro');
      final session = AcpSession.parse(value)!;
      final controller = _ModelHarness(scope, (id, args) async {
        calls.add((id, args));
        if (calls.length == 1) throw TimeoutException('network');
        return result(value);
      }, () => AcpProjection(sessions: {session.key: session}));
      addTearDown(controller.dispose);
      await controller.select(AcpSession.parse(config())!, 'pro');
      expect(controller.operation.phase, AcpModelPhase.uncertain);
      expect(await controller.select(session, 'flash'), isFalse);
      expect(await controller.prepare(), isFalse);
      expect(calls, hasLength(1));
      expect(await controller.retry(), isTrue);
      expect(calls[0].$1, calls[1].$1);
      expect(calls[0].$2, calls[1].$2);
      expect(calls[1].$2['revision'], 1);
      expect(controller.operation.blocksSending, isFalse);
    },
  );

  test(
    'explicit rejection retains effective model and recovery queries fresh configuration',
    () async {
      final calls = <Map<String, Object?>>[];
      final initial = AcpSession.parse(config())!;
      final controller = _ModelHarness(scope, (_, args) async {
        calls.add(args);
        if (calls.length == 1) throw StateError('stale_revision');
        return result(config());
      }, () => AcpProjection(sessions: {initial.key: initial}));
      addTearDown(controller.dispose);
      await controller.select(initial, 'pro');
      expect(controller.operation.phase, AcpModelPhase.failed);
      expect(initial.data['model_id'], 'flash');
      expect(controller.operation.blocksSending, isFalse);
      await controller.retry();
      expect(calls.last, {'action': 'prepare_session'});
      expect(controller.operation.phase, AcpModelPhase.idle);
    },
  );

  testWidgets(
    'first open prepares without prompt, displays actual default, keeps it while busy',
    (tester) async {
      final service = RecordingControl()..completion = Completer();
      final container = ProviderContainer(
        overrides: [acpControlServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: Consumer(
                builder: (context, ref, _) {
                  final session = ref
                      .watch(acpSessionsProvider)
                      .forConversation(scope.conversationId)
                      .firstOrNull;
                  return AcpModelBar(scope: scope, session: session);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(service.requests, hasLength(1));
      expect(service.requests.single['args'], {'action': 'prepare_session'});
      expect(
        container.read(acpModelControllerProvider(scope)).blocksSending,
        isTrue,
      );
      final value = config();
      container
          .read(acpSessionsProvider.notifier)
          .applyConversation(control(value), scope.conversationId);
      await tester.pump();
      await tester.tap(find.byKey(const Key('acp-model-menu')));
      await tester.pump(const Duration(seconds: 1));
      final choice = find.byKey(const ValueKey('acp-model:pro'));
      expect(tester.widget<CupertinoButton>(choice).onPressed, isNull);
      // A snapshot alone does not confirm the in-flight prepare command.
      expect(service.requests, hasLength(1));
      service.completion!.complete(result(value));
      await tester.pumpAndSettle();
      expect(tester.widget<CupertinoButton>(choice).onPressed, isNotNull);
      Navigator.of(
        tester.element(find.byKey(const Key('acp-model-picker'))),
      ).pop();
      await tester.pumpAndSettle();
      expect(find.text('Flash'), findsOneWidget);
      expect(
        container.read(acpModelControllerProvider(scope)).blocksSending,
        isFalse,
      );
      container
          .read(acpSessionsProvider.notifier)
          .applyConversation(
            control({
              ...value,
              'revision': 2,
              'active': {'run_id': 'new'},
            }),
            scope.conversationId,
          );
      await tester.pumpAndSettle();
      expect(find.text('Flash'), findsOneWidget);
      expect(service.requests, hasLength(1));
    },
  );

  testWidgets(
    'closing picker preserves pending operation and identity switch discards late response',
    (tester) async {
      final service = RecordingControl()..completion = Completer();
      final container = ProviderContainer(
        overrides: [acpControlServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: AcpSessionOptions(session: AcpSession.parse(config())!),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('acp-model-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('acp-model:pro')));
      await tester.pump();
      Navigator.of(
        tester.element(find.byKey(const Key('acp-model-picker'))),
      ).pop();
      await tester.pump(const Duration(seconds: 1));
      expect(
        container.read(acpModelControllerProvider(scope)).blocksSending,
        isTrue,
      );
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:bob',
              credentialName: 'bob',
              displayName: 'Bob',
            ),
          );
      service.completion!.complete(result(config(revision: 2, model: 'pro')));
      await tester.pump();
      expect(
        container.read(acpModelControllerProvider(scope)).blocksSending,
        isFalse,
      );
      expect(container.read(acpSessionsProvider).sessions, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _ModelHarness extends AcpModelController {
  _ModelHarness(super.scope, super.send, super.projection);
  AcpModelOperation get operation => state;
}
