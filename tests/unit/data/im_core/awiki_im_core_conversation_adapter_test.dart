import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_conversation_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mark-read resolves canonical direct and group thread refs', () {
    final direct = coreThreadRefForMarkRead(
      const AppThreadRef.thread('dm:did:alice:did:bob'),
      'did:alice',
    );
    final group = coreThreadRefForMarkRead(
      const AppThreadRef.thread('group:did:group'),
      'did:alice',
    );

    expect(direct, isA<core.DirectThreadRef>());
    expect((direct as core.DirectThreadRef).peer, 'did:bob');
    expect(group, isA<core.GroupThreadRef>());
    expect((group as core.GroupThreadRef).group, 'did:group');
  });

  test('mark-read collects only unread incoming message ids', () {
    final ids = unreadIncomingMessageIdsForMarkRead(<core.Message>[
      _message(id: 'incoming-unread', sender: 'did:bob', isRead: false),
      _message(id: 'incoming-read', sender: 'did:bob', isRead: true),
      _message(id: 'incoming-without-read-state', sender: 'did:bob'),
      _message(
        id: 'outgoing-unread',
        sender: 'did:alice',
        direction: core.MessageDirection.outgoing,
        isRead: false,
      ),
    ], ownerDid: 'did:alice');

    expect(ids, <String>['incoming-unread', 'incoming-without-read-state']);
  });
}

core.Message _message({
  required String id,
  required String sender,
  core.MessageDirection direction = core.MessageDirection.incoming,
  bool? isRead,
}) {
  return core.Message(
    id: id,
    threadKind: 'direct',
    threadId: 'did:bob',
    direction: direction,
    sender: sender,
    receiver: 'did:alice',
    body: const core.MessageBodyView(text: 'hello'),
    metadata: core.MessageMetadata(
      attributes: isRead == null
          ? const <core.MessageMetadataAttribute>[]
          : <core.MessageMetadataAttribute>[
              core.MessageMetadataAttribute(
                key: 'is_read',
                value: isRead.toString(),
              ),
            ],
    ),
  );
}
