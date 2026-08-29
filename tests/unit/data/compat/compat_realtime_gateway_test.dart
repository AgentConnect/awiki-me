import 'dart:async';

import 'package:awiki_me/src/application/realtime_application_service.dart';
import 'package:awiki_me/src/data/compat/compat_realtime_gateway.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'compat realtime gateway forwards typed updates as map events',
    () async {
      final realtime = _FakeRealtimeService();
      final gateway = CompatRealtimeGateway(realtime: realtime);
      final events = <Map<String, Object?>>[];
      final statuses = <RealtimeConnectionStatus>[];
      final statusSub = gateway.connectionStatusStream.listen(statuses.add);
      addTearDown(statusSub.cancel);

      await gateway.connect(
        session: const SessionIdentity(
          did: 'did:alice',
          credentialName: 'alice',
          displayName: 'Alice',
        ),
        onMessage: (event) async => events.add(event),
      );
      realtime.emitStatus(RealtimeConnectionStatus.connected);
      realtime.emitUpdate(_update());
      await pumpEventQueue();
      await gateway.disconnect();

      expect(
        events.single[compatRealtimeUpdateEventKey],
        isA<RealtimeUpdate>(),
      );
      expect(statuses, contains(RealtimeConnectionStatus.connected));
      expect(gateway.connectionStatus, RealtimeConnectionStatus.disconnected);
    },
  );
}

RealtimeUpdate _update() {
  final message = ChatMessage(
    localId: 'msg-1',
    threadId: 'dm:alice:bob',
    senderDid: 'did:bob',
    content: 'hi',
    createdAt: DateTime.utc(2026, 5, 23),
    isMine: false,
    sendState: MessageSendState.sent,
  );
  return RealtimeUpdate(
    ownerDid: 'did:wba:awiki.ai:user:alice:e1_owner',
    message: message,
    conversationHint: ConversationSummary(
      threadId: 'dm:alice:bob',
      conversationId: 'dm:alice:bob',
      displayName: 'Bob',
      lastMessagePreview: 'hi',
      lastMessageAt: DateTime.utc(2026, 5, 23),
      unreadCount: 1,
      isGroup: false,
      targetDid: 'did:bob',
    ),
  );
}

class _FakeRealtimeService implements RealtimeApplicationService {
  final StreamController<RealtimeConnectionStatus> _statuses =
      StreamController<RealtimeConnectionStatus>.broadcast();
  final StreamController<RealtimeUpdate> _updates =
      StreamController<RealtimeUpdate>.broadcast();
  bool _running = false;

  @override
  Stream<RealtimeConnectionStatus> get connectionStates => _statuses.stream;

  @override
  bool get isRunning => _running;

  @override
  Stream<RealtimeUpdate> get updates => _updates.stream;

  @override
  Future<void> start() async {
    _running = true;
  }

  @override
  Future<void> stop() async {
    _running = false;
  }

  void emitStatus(RealtimeConnectionStatus status) => _statuses.add(status);

  void emitUpdate(RealtimeUpdate update) => _updates.add(update);
}
