import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/domain/entities/agent/acp_session.dart';
import 'package:awiki_me/src/presentation/agents/acp_model_controller.dart';
import 'package:awiki_me/src/presentation/agents/acp_model_refresh_controller.dart';
import 'package:awiki_me/src/presentation/agents/acp_session_provider.dart';
import 'package:awiki_me/src/presentation/agents/acp_task_status.dart';
import 'acp_model_configuration_test.dart' show scope, config, result;
import 'acp_runtime_test.dart' show RecordingControl, control;

Map<String, Object?> catalog({
  int revision = 1,
  int? updated,
  String model = 'flash',
}) => {
  ...config(revision: revision, model: model),
  'model_refresh_supported': true,
  'model_catalog_updated_at_ms':
      updated ?? DateTime.now().millisecondsSinceEpoch,
};

class Harness extends AcpModelRefreshController {
  Harness(super.scope, super.send, super.projection);
  AcpModelRefreshState get current => state;
}

void main() {
  test(
    'catalog freshness distinguishes unknown, stale and future timestamps',
    () {
      final now = DateTime.fromMillisecondsSinceEpoch(1000000);
      for (final stamp in [null, 0, 1000001]) {
        final session = AcpSession.parse({
          ...config(),
          'model_catalog_updated_at_ms': stamp,
        })!;
        expect(session.modelCatalogIsFresh(now), isFalse);
      }
      expect(
        AcpSession.parse(catalog(updated: 999999))!.modelCatalogIsFresh(now),
        isTrue,
      );
    },
  );

  test(
    'refresh waits for committed projection and ignores stale or foreign routing',
    () async {
      final completion = Completer<Map<String, Object?>>();
      final controller = Harness(
        scope,
        (_, __) => completion.future,
        () => const AcpProjection(),
      );
      addTearDown(controller.dispose);
      final initial = AcpSession.parse(catalog())!;
      final pending = controller.refresh(initial);
      expect(controller.current.phase, AcpModelRefreshPhase.loading);
      final next = catalog(revision: 3, model: 'unlisted');
      completion.complete({
        ...result(next),
        'model_refresh': {'state': 'refreshed'},
      });
      await pending;
      expect(controller.current.phase, AcpModelRefreshPhase.synchronizing);
      for (final session in [
        initial,
        AcpSession.parse(next, localConversationId: 'foreign')!,
      ]) {
        controller.reconcile(AcpProjection(sessions: {initial.key: session}));
        expect(controller.current.phase, AcpModelRefreshPhase.synchronizing);
      }
      controller.reconcile(
        AcpProjection(sessions: {initial.key: AcpSession.parse(next)!}),
      );
      expect(controller.current.phase, AcpModelRefreshPhase.idle);
      expect(initial.data['model_id'], 'flash');
    },
  );

  test(
    'busy, old daemon and foreign scopes never issue catalog requests',
    () async {
      var requests = 0;
      final controller = Harness(scope, (_, __) async {
        requests++;
        return {};
      }, () => const AcpProjection());
      addTearDown(controller.dispose);
      for (final value in [
        config(),
        {
          ...catalog(),
          'active': {'run_id': 'a'},
        },
        {
          ...catalog(),
          'waiting': {'run_id': 'b'},
        },
        {...catalog(), 'group': true},
        {...catalog(), 'agent_did': 'foreign'},
      ]) {
        await controller.refresh(AcpSession.parse(value)!);
      }
      expect(requests, 0);
    },
  );

  test(
    'duplicate refresh coalesces and a disposed identity ignores its reply',
    () async {
      final completion = Completer<Map<String, Object?>>();
      var requests = 0;
      final controller = Harness(scope, (_, __) {
        requests++;
        return completion.future;
      }, () => const AcpProjection());
      final initial = AcpSession.parse(catalog())!;
      final pending = controller.refresh(initial);
      await controller.refresh(initial);
      expect(requests, 1);
      controller.dispose();
      completion.complete({
        ...result(catalog(revision: 2)),
        'model_refresh': {'state': 'refreshed'},
      });
      await expectLater(pending, completes);
    },
  );

  test(
    'deferred refresh carries a bounded retry and leaves selection untouched',
    () async {
      final controller = Harness(
        scope,
        (_, __) async => {
          'model_refresh': {'state': 'deferred', 'retry_after_ms': 100000},
        },
        () => const AcpProjection(),
      );
      addTearDown(controller.dispose);
      final initial = AcpSession.parse(catalog())!;
      await controller.refresh(initial);
      expect(controller.current.phase, AcpModelRefreshPhase.deferred);
      expect(controller.current.retryAfter, const Duration(seconds: 65));
      expect(controller.current.pending, isFalse);
      expect(initial.data['model_id'], 'flash');
    },
  );

  Future<void> open(
    WidgetTester tester,
    ProviderContainer container,
    AcpSession initial, {
    bool online = true,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: AcpSessionOptions(session: initial, online: online),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('acp-model-menu')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'unlisted current is read-only and empty catalogs remain accessible',
    (tester) async {
      final service = RecordingControl();
      final container = ProviderContainer(
        overrides: [acpControlServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      await open(
        tester,
        container,
        AcpSession.parse({...catalog(model: 'custom-model'), 'models': []})!,
      );
      expect(find.byKey(const Key('acp-current-model')), findsOneWidget);
      expect(
        find.text('Current configuration · not listed by the client'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('acp-model:custom-model')),
        findsNothing,
      );
      expect(
        find.text('The client did not provide selectable models'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('acp-model-refresh')), findsOneWidget);
      expect(service.requests, isEmpty);
    },
  );

  testWidgets(
    'stale list auto-refreshes once, failure keeps choices and never blocks sending',
    (tester) async {
      final service =
          RecordingControl(); // malformed response exercises failure
      final container = ProviderContainer(
        overrides: [acpControlServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      await open(tester, container, AcpSession.parse(catalog(updated: 0))!);
      expect(service.requests, hasLength(1));
      expect(
        (service.requests.single['args'] as Map)['action'],
        'refresh_models',
      );
      expect(
        container.read(acpModelControllerProvider(scope)).blocksSending,
        isFalse,
      );
      expect(find.byKey(const ValueKey('acp-model:pro')), findsOneWidget);
      expect(
        find.text('Refresh failed. The previous list is kept; please retry.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(minutes: 6));
      expect(service.requests, hasLength(1));
      await tester.tap(find.byKey(const Key('acp-model-refresh')));
      await tester.pumpAndSettle();
      expect(service.requests, hasLength(2));
    },
  );

  testWidgets('offline keeps cached choices and does not refresh or switch', (
    tester,
  ) async {
    final service = RecordingControl();
    final container = ProviderContainer(
      overrides: [acpControlServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    await open(
      tester,
      container,
      AcpSession.parse(catalog(updated: 0))!,
      online: false,
    );
    expect(service.requests, isEmpty);
    expect(
      tester
          .widget<CupertinoButton>(find.byKey(const Key('acp-model-refresh')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<CupertinoButton>(find.byKey(const ValueKey('acp-model:pro')))
          .onPressed,
      isNull,
    );
    expect(
      find.text('Device offline. Showing the last available list.'),
      findsOneWidget,
    );
  });

  testWidgets('pending stale refresh starts when projected task becomes idle', (
    tester,
  ) async {
    final service = RecordingControl();
    final container = ProviderContainer(
      overrides: [acpControlServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final busy = {
      ...catalog(updated: 0),
      'active': {'run_id': 'busy'},
    };
    container
        .read(acpSessionsProvider.notifier)
        .applyConversation(control(busy), scope.conversationId);
    await open(tester, container, AcpSession.parse(busy)!);
    expect(service.requests, isEmpty);
    container
        .read(acpSessionsProvider.notifier)
        .applyConversation(
          control(catalog(revision: 2, updated: 0)),
          scope.conversationId,
        );
    await tester.pumpAndSettle();
    expect(service.requests, hasLength(1));
  });

  testWidgets(
    'single current choice is checked and cannot trigger a fake switch',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await open(
        tester,
        container,
        AcpSession.parse({
          ...catalog(),
          'models': [
            {'id': 'flash', 'name': 'Flash'},
          ],
        })!,
      );
      expect(
        tester
            .widget<CupertinoButton>(
              find.byKey(const ValueKey('acp-model:flash')),
            )
            .onPressed,
        isNull,
      );
    },
  );
}
