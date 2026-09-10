import 'dart:async';
import '../e2e/flutter/support/confirm_local_credential_deletion.dart';
import 'package:awiki_me/l10n/app_localizations.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/shared/local_credential_delete_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

const identity = SessionIdentity(
  did: 'did:wba:example.test:user:alice:e1_test',
  credentialName: 'alice',
  displayName: 'Alice',
  localIdentityId: 'owner-alice',
  handle: 'alice.example.test',
);
const hint = '同时会清除本机尚未完成的恢复进度。';
const confirm = Key('local-credential-delete-confirm:owner-alice');

Future<void> pumpDialog(
  WidgetTester tester,
  Future<bool> Function() query,
  VoidCallback onConfirm, {
  bool signsOut = false,
}) async {
  await tester.pumpWidget(
    CupertinoApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CupertinoPageScaffold(
        child: LocalCredentialDeleteDialog(
          identity: identity,
          signsOut: signsOut,
          loadRecoveryImpact: query,
          onConfirm: onConfirm,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'E2E confirmation waits for delayed impact query and clicks once',
    (tester) async {
      final query = Completer<bool>();
      var deleted = 0;
      await pumpDialog(tester, () => query.future, () {
        deleted++;
      });
      final timer = Timer(const Duration(milliseconds: 200), () {
        expectSync(deleted, 0);
        query.complete(false);
      });
      addTearDown(timer.cancel);
      await confirmLocalCredentialDeletion(tester);
      expect(deleted, 1);
    },
  );

  testWidgets('E2E confirmation reports failed impact query without deleting', (
    tester,
  ) async {
    var deleted = 0;
    await pumpDialog(tester, () async => throw StateError('unavailable'), () {
      deleted++;
    });
    await expectLater(
      confirmLocalCredentialDeletion(tester),
      throwsA(
        isA<TestFailure>().having(
          (error) => error.message,
          'message',
          contains('deletion-impact query failed'),
        ),
      ),
    );
    expect(deleted, 0);
  });

  testWidgets('E2E confirmation bounds unresolved query without deleting', (
    tester,
  ) async {
    final query = Completer<bool>();
    var deleted = 0;
    await pumpDialog(tester, () => query.future, () {
      deleted++;
    });
    Object? failure;
    try {
      await confirmLocalCredentialDeletion(
        tester,
        timeout: const Duration(milliseconds: 200),
      );
    } catch (error) {
      failure = error;
    }
    expect(
      failure,
      isA<TestFailure>().having(
        (error) => error.message,
        'message',
        contains('did not become enabled'),
      ),
    );
    expect(deleted, 0);
    query.complete(false);
    await tester.pump();
  });

  for (final signsOut in [false, true]) {
    for (final pending in [false, true]) {
      testWidgets(
        'actual pending=$pending controls notice; signsOut=$signsOut',
        (tester) async {
          var deleted = 0;
          var queried = 0;
          await pumpDialog(
            tester,
            () async {
              queried++;
              return pending;
            },
            () {
              deleted++;
            },
            signsOut: signsOut,
          );
          await tester.pumpAndSettle();
          expect(find.text(hint), pending ? findsOneWidget : findsNothing);
          expect(queried, 1);
          expect(deleted, 0);
          await tester.tap(find.byKey(confirm));
          expect(deleted, 1);
        },
      );
    }
  }

  testWidgets(
    'query in progress cannot confirm; resolved state enables deletion',
    (tester) async {
      final query = Completer<bool>();
      var deleted = 0;
      await pumpDialog(tester, () => query.future, () {
        deleted++;
      });
      await tester.tap(find.byKey(confirm));
      expect(deleted, 0);
      expect(find.text(hint), findsNothing);
      query.complete(true);
      await tester.pumpAndSettle();
      expect(find.text(hint), findsOneWidget);
      await tester.tap(find.byKey(confirm));
      expect(deleted, 1);
    },
  );

  testWidgets('failed query stays in dialog and retries without deleting', (
    tester,
  ) async {
    var calls = 0;
    var deleted = 0;
    await pumpDialog(
      tester,
      () async {
        if (++calls == 1) throw StateError('unavailable');
        return true;
      },
      () {
        deleted++;
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法确认本机身份状态，请重试。'), findsOneWidget);
    await tester.tap(find.byKey(confirm));
    expect(deleted, 0);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text(hint), findsOneWidget);
    expect(calls, 2);
    await tester.tap(find.byKey(confirm));
    expect(deleted, 1);
  });
  testWidgets('cancel closes an unresolved query without deleting', (
    tester,
  ) async {
    final query = Completer<bool>();
    var deleted = 0;
    await tester.pumpWidget(
      CupertinoApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showCupertinoDialog<void>(
              context: context,
              builder: (_) => LocalCredentialDeleteDialog(
                identity: identity,
                signsOut: false,
                loadRecoveryImpact: () => query.future,
                onConfirm: () {
                  deleted++;
                },
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 300));
    query.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(LocalCredentialDeleteDialog), findsNothing);
    expect(deleted, 0);
    expect(tester.takeException(), isNull);
  });
}
