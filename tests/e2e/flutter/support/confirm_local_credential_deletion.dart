import 'package:awiki_me/src/l10n/l10n.dart';
import 'package:awiki_me/src/presentation/shared/local_credential_delete_dialog.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// A visible dialog is not permission to click: the local recovery-impact query
/// must have completed and enabled the destructive action first.
Future<void> confirmLocalCredentialDeletion(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = tester.binding.clock.now().add(timeout);
  while (tester.binding.clock.now().isBefore(deadline)) {
    final dialog = find.byType(LocalCredentialDeleteDialog);
    if (dialog.evaluate().length == 1) {
      final context = tester.element(dialog);
      if (find
          .descendant(
            of: dialog,
            matching: find.text(
              context.l10n.localCredentialDeleteInspectFailed,
            ),
          )
          .evaluate()
          .isNotEmpty) {
        fail(
          'The joined App deletion-impact query failed before confirmation.',
        );
      }
      final identity = tester
          .widget<LocalCredentialDeleteDialog>(dialog)
          .identity;
      final confirm = find.descendant(
        of: dialog,
        matching: find.byKey(
          Key(
            'local-credential-delete-confirm:${identity.localIdentitySelector}',
          ),
        ),
      );
      if (confirm.evaluate().length == 1 &&
          tester.widget<AppDangerButton>(confirm).onPressed != null) {
        await tester.ensureVisible(confirm);
        await tester.tap(confirm.hitTestable());
        await tester.pump();
        return;
      }
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('The joined App delete confirmation did not become enabled.');
}
