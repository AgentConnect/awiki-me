import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:image/image.dart' as img;
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/profile/avatar_edit_dialog.dart';
import '../test_support.dart';
import 'avatar_profile_controller_test.dart' as fixture;

class _StaticAvatarChooser extends FileSelectorPlatform {
  _StaticAvatarChooser(this.file);
  final XFile file;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => file;
}

void main() {
  testWidgets(
    'desktop PNG preparation reaches a ready real crop before save',
    (tester) async {
      final originalChooser = FileSelectorPlatform.instance;
      addTearDown(() {
        FileSelectorPlatform.instance = originalChooser;
      });
      final source = img.Image(width: 1200, height: 800);
      img.fill(source, color: img.ColorRgb8(40, 90, 160));
      FileSelectorPlatform.instance = _StaticAvatarChooser(
        XFile.fromData(img.encodePng(source), name: 'source.png'),
      );
      final avatars = fixture.Avatars();
      await tester.pumpWidget(
        buildLocalizedTestApp(
          session: const SessionIdentity(
            did: 'did:example:alice',
            credentialName: 'alice',
            displayName: 'Alice',
          ),
          profile: avatars.current,
          providerOverrides: [
            profileApplicationServiceProvider.overrideWithValue(avatars),
          ],
          home: Builder(
            builder: (context) => CupertinoButton(
              onPressed: () => showAvatarEditor(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('avatar-pick')));
      final watch = Stopwatch()..start();
      var ready = false;
      while (!ready && watch.elapsed < const Duration(seconds: 5)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        final save = find.byKey(const Key('avatar-save'));
        ready =
            save.evaluate().length == 1 &&
            tester.widget<CupertinoButton>(save).onPressed != null;
      }
      expect(find.byKey(const Key('avatar-error')), findsNothing);
      expect(find.byKey(const Key('avatar-new-preview')), findsOneWidget);
      expect(ready, isTrue);
      expect(avatars.requests, isEmpty);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets('clear requires confirmation and cancel preserves the profile', (
    tester,
  ) async {
    final avatars = fixture.Avatars();
    avatars.mutation = Completer()..complete(fixture.profile('2', uri: null));
    await tester.pumpWidget(
      buildLocalizedTestApp(
        session: const SessionIdentity(
          did: 'did:example:alice',
          credentialName: 'alice',
          displayName: 'Alice',
        ),
        profile: avatars.current,
        providerOverrides: [
          profileApplicationServiceProvider.overrideWithValue(avatars),
        ],
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showAvatarEditor(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('avatar-clear')));
    await tester.pumpAndSettle();
    expect(avatars.requests, isEmpty);
    await tester.tap(find.byKey(const Key('avatar-clear-cancel')));
    await tester.pumpAndSettle();
    expect(avatars.requests, isEmpty);
    await tester.tap(find.byKey(const Key('avatar-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('avatar-clear-confirm')));
    await tester.pumpAndSettle();
    expect(avatars.requests, hasLength(1));
    expect(avatars.requests.single.$3, isNull);
    expect(find.byType(AvatarEditDialog), findsNothing);
  });
}
