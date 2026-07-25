import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const alice = SessionIdentity(
    did: 'did:test:alice',
    credentialName: 'alice',
    displayName: 'Alice',
    jwtToken: 'token-a',
  );
  const bob = SessionIdentity(
    did: 'did:test:bob',
    credentialName: 'bob',
    displayName: 'Bob',
  );

  test('session epoch advances on clear and identity replacement', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(sessionProvider.notifier);

    controller.setSession(alice);
    final aliceEpoch = container.read(sessionProvider).activeEpoch;
    expect(aliceEpoch, isNotNull);

    controller.clear();
    expect(container.read(sessionProvider).activeEpoch, isNull);
    expect(
      container.read(sessionProvider).generation,
      aliceEpoch!.generation + 1,
    );

    controller.clear();
    expect(
      container.read(sessionProvider).generation,
      aliceEpoch.generation + 2,
    );

    controller.setSession(bob);
    final bobEpoch = container.read(sessionProvider).activeEpoch;
    expect(bobEpoch, isNotNull);
    expect(bobEpoch!.generation, aliceEpoch.generation + 3);
    expect(bobEpoch.ownerDid, bob.did);
    expect(bobEpoch.identityKey, bob.credentialName);
    expect(aliceEpoch.matches(container.read(sessionProvider)), isFalse);
  });

  test('same identity auth refresh preserves the active epoch', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(sessionProvider.notifier)
      ..setSession(alice);
    final before = container.read(sessionProvider).activeEpoch;

    controller.setSession(
      const SessionIdentity(
        did: 'did:test:alice',
        credentialName: 'alice',
        displayName: 'Alice Renamed',
        jwtToken: 'token-b',
      ),
    );

    expect(container.read(sessionProvider).activeEpoch, before);
    expect(container.read(sessionProvider).session?.jwtToken, 'token-b');
  });

  test('same identity activation always starts a new session epoch', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(sessionProvider.notifier)
      ..activateSession(alice);
    final before = container.read(sessionProvider).activeEpoch!;

    controller.activateSession(
      const SessionIdentity(
        did: 'did:test:alice',
        credentialName: 'alice',
        displayName: 'Alice',
        jwtToken: 'replacement-token',
      ),
    );

    final after = container.read(sessionProvider).activeEpoch!;
    expect(after.ownerDid, before.ownerDid);
    expect(after.identityKey, before.identityKey);
    expect(after.generation, before.generation + 1);
  });

  test('session metadata refresh cannot restore a stale identity', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(sessionProvider.notifier)
      ..setSession(alice);
    final aliceEpoch = container.read(sessionProvider).activeEpoch;

    expect(
      controller.updateSessionMetadataIfCurrent(
        const SessionIdentity(
          did: 'did:test:alice',
          credentialName: 'alice',
          displayName: 'Alice Refreshed',
          jwtToken: 'token-b',
        ),
      ),
      isTrue,
    );
    expect(container.read(sessionProvider).activeEpoch, aliceEpoch);
    expect(
      container.read(sessionProvider).session?.displayName,
      'Alice Refreshed',
    );

    controller.setSession(bob);
    final bobEpoch = container.read(sessionProvider).activeEpoch;
    expect(controller.updateSessionMetadataIfCurrent(alice), isFalse);
    expect(container.read(sessionProvider).session, bob);
    expect(container.read(sessionProvider).activeEpoch, bobEpoch);

    controller.clear();
    expect(controller.updateSessionMetadataIfCurrent(bob), isFalse);
    expect(container.read(sessionProvider).session, isNull);
  });

  test('direct identity replacement advances the active epoch', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(sessionProvider.notifier)
      ..setSession(alice);
    final aliceEpoch = container.read(sessionProvider).activeEpoch!;

    controller.setSession(bob);

    final bobEpoch = container.read(sessionProvider).activeEpoch!;
    expect(bobEpoch.generation, aliceEpoch.generation + 1);
    expect(bobEpoch, isNot(aliceEpoch));
  });
}
