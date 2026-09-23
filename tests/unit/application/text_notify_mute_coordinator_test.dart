import 'dart:async';
import 'package:awiki_me/src/application/ports/remote_push_sync_port.dart';
import 'package:awiki_me/src/application/remote_push_message_reference.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/application/text_notify_mute_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RemotePushSessionContext current;
  late TextNotifyMuteCoordinator coordinator;
  late List<String> operations;
  late Set<String> canonical;
  late List<String> mirrored;
  late bool ready;
  late bool failReplace;
  late Future<Set<String>> Function() read;
  late int revision;
  final alice = RemotePushSessionContext(
    storageScopeId: StorageScopeId.parse(
      '11111111-1111-4111-8111-111111111111',
    ),
    ownerDid: 'did:alice',
    generation: 1,
  );
  final bob = RemotePushSessionContext(
    storageScopeId: StorageScopeId.parse(
      '11111111-1111-4111-8111-111111111111',
    ),
    ownerDid: 'did:bob',
    generation: 2,
  );

  setUp(() {
    current = alice;
    canonical = {'did:historically-muted'};
    mirrored = [];
    operations = [];
    ready = false;
    failReplace = false;
    revision = 0;
    read = () async => canonical;
    coordinator = TextNotifyMuteCoordinator(
      isCurrent: (context) => context.matches(current),
      begin: (target) async {
        operations.add('invalidate');
        ready = false;
        return ++revision;
      },
      loadMutedPeers: (_) async {
        operations.add('read');
        return read();
      },
      replace: (target, expectedRevision, identities) async {
        operations.add('replace');
        expect(target, remotePushOpaqueTargetReference(current.ownerDid));
        expect(expectedRevision, revision);
        if (failReplace) return false;
        mirrored = identities;
        ready = true;
        return true;
      },
    );
  });

  test(
    'initial activation hydrates pre-feature canonical mutes before readiness',
    () async {
      await coordinator.ensureReady(alice);
      expect(operations, ['invalidate', 'read', 'replace']);
      expect(mirrored, [
        remotePushOpaqueIdentityReference('did:historically-muted'),
      ]);
      expect(ready, isTrue);
      await coordinator.ensureReady(alice);
      expect(
        operations.length,
        3,
      ); // Normal resume does not disrupt an active cue.
    },
  );

  test(
    'mute update invalidates before saving and survives failed mirror with retry',
    () async {
      await coordinator.ensureReady(alice);
      operations.clear();
      failReplace = true;
      await expectLater(
        coordinator.update(alice, () async {
          expect(ready, isFalse);
          operations.add('save');
          canonical = {'did:newly-muted'};
        }),
        throwsStateError,
      );
      expect(operations, ['invalidate', 'save', 'read', 'replace']);
      expect(canonical, {'did:newly-muted'});
      expect(ready, isFalse);
      failReplace = false;
      await coordinator.ensureReady(alice);
      expect(ready, isTrue);
      expect(mirrored, [remotePushOpaqueIdentityReference('did:newly-muted')]);
    },
  );

  test(
    'failed canonical save never reopens stale mirror; next resume restores truth',
    () async {
      await coordinator.ensureReady(alice);
      await expectLater(
        coordinator.update(alice, () async {
          throw StateError('store unavailable');
        }),
        throwsStateError,
      );
      expect(ready, isFalse);
      await coordinator.ensureReady(alice);
      expect(mirrored, [
        remotePushOpaqueIdentityReference('did:historically-muted'),
      ]);
    },
  );

  test(
    'account switch while reading cannot install old snapshot into new session',
    () async {
      final pending = Completer<Set<String>>();
      read = () => pending.future;
      final old = coordinator.ensureReady(alice);
      await Future<void>.delayed(Duration.zero);
      current = bob;
      read = () async => {};
      final next = coordinator.ensureReady(bob);
      pending.complete({'did:alice-peer'});
      await expectLater(old, throwsStateError);
      await next;
      expect(mirrored, isEmpty);
      expect(operations.where((v) => v == 'replace').length, 1);
    },
  );

  test(
    'queued mute change cannot be overwritten by earlier hydration',
    () async {
      final pending = Completer<Set<String>>();
      read = () => pending.future;
      final hydration = coordinator.ensureReady(alice);
      await Future<void>.delayed(Duration.zero);
      final change = coordinator.update(alice, () async {
        canonical = {'did:latest'};
        read = () async => canonical;
      });
      pending.complete({'did:old'});
      await hydration;
      await change;
      expect(mirrored, [remotePushOpaqueIdentityReference('did:latest')]);
    },
  );
}
