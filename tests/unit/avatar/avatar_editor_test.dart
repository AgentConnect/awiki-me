import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/profile/avatar_edit_dialog.dart';
import '../test_support.dart';
import 'avatar_profile_controller_test.dart' as fixture;

void main() {
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
