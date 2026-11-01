// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/presentation/chat/local_message_deletions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

ChatMessage message(String id) => ChatMessage(
  localId: 'local-$id',
  remoteId: 'remote-$id',
  identityAliases: {'client-$id'},
  conversationId: 'dm:one',
  threadId: 'dm:one',
  senderDid: 'did:peer',
  content: id,
  createdAt: DateTime(2026),
  isMine: false,
  sendState: MessageSendState.sent,
);

void main() {
  test(
    'local deletion survives reopen and matches canonical/echo aliases',
    () async {
      final store = FakeProductLocalStore();
      final first = LocalMessageDeletions(store, 'owner', 'dm:one');
      await first.delete([message('a'), message('b')]);
      first.dispose();
      final reopened = LocalMessageDeletions(store, 'owner', 'dm:one');
      addTearDown(reopened.dispose);
      await reopened.ready;
      expect(
        isMessageLocallyDeleted(message('a'), reopened.state.requireValue),
        isTrue,
      );
      expect(
        isMessageLocallyDeleted(message('c'), reopened.state.requireValue),
        isFalse,
      );
      expect(
        reopened.state.requireValue,
        containsAll(['local-a', 'remote-a', 'client-a']),
      );
      expect(
        store.preferences.values.single.valueJson,
        isNot(contains('did:peer')),
      );
    },
  );

  test('other accounts conversations and devices are unaffected', () async {
    final store = FakeProductLocalStore();
    final current = LocalMessageDeletions(store, 'owner', 'dm:one');
    addTearDown(current.dispose);
    await current.delete([message('a')]);
    for (final other in [
      LocalMessageDeletions(store, 'other-owner', 'dm:one'),
      LocalMessageDeletions(store, 'owner', 'dm:two'),
      LocalMessageDeletions(FakeProductLocalStore(), 'owner', 'dm:one'),
    ]) {
      addTearDown(other.dispose);
      await other.ready;
      expect(other.state.requireValue, isEmpty);
    }
  });

  test('concurrent batches merge without losing a deletion', () async {
    final controller = LocalMessageDeletions(
      FakeProductLocalStore(),
      'owner',
      'dm:one',
    );
    addTearDown(controller.dispose);
    await Future.wait([
      controller.delete([message('a')]),
      controller.delete([message('b')]),
    ]);
    expect(
      controller.state.requireValue,
      containsAll(['remote-a', 'remote-b']),
    );
  });

  test(
    'failed persistence preserves visible content and allows retry',
    () async {
      final store = _FailingStore();
      final controller = LocalMessageDeletions(store, 'owner', 'dm:one');
      addTearDown(controller.dispose);
      await expectLater(controller.delete([message('a')]), throwsStateError);
      expect(controller.state.requireValue, isEmpty);
      store.fail = false;
      await controller.delete([message('a')]);
      expect(controller.state.requireValue, contains('remote-a'));
    },
  );

  test('disposed owner does not publish a delayed deletion', () async {
    final store = _DelayedStore();
    final controller = LocalMessageDeletions(store, 'owner', 'dm:one');
    await controller.ready;
    final deleting = controller.delete([message('a')]);
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    store.release.complete();
    await deleting;
    expect(store.preferences.values.single.ownerDid, 'owner');
  });
}

class _FailingStore extends FakeProductLocalStore {
  bool fail = true;
  @override
  Future<void> saveUiPreference(LocalUiPreference preference) async {
    if (fail) throw StateError('disk unavailable');
    await super.saveUiPreference(preference);
  }
}

class _DelayedStore extends FakeProductLocalStore {
  final release = Completer<void>();
  @override
  Future<void> saveUiPreference(LocalUiPreference preference) async {
    await release.future;
    await super.saveUiPreference(preference);
  }
}
