import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/flutter/support/coding_agent_diagnostics.dart';

void main() {
  test('ACP projection diagnostics expose only identity comparisons', () {
    final message = ChatMessage(
      localId: 'secret-id',
      threadId: 'secret-thread',
      conversationId: 'secret-conversation',
      senderDid: 'secret-sender',
      content: 'secret-text',
      payloadJson:
          '{"schema":"awiki.acp.status.v1","acp":{"agent_did":"secret-sender","text":"secret-output"}}',
      createdAt: DateTime.utc(2026),
      isMine: false,
      sendState: MessageSendState.sent,
    );
    expect(codingAgentAcpProjectionSummary([message], {'other-conversation'}), [
      {
        'conversation_present': true,
        'conversation_matches': false,
        'sender_matches': true,
        'incoming': true,
        'sent': true,
      },
    ]);
  });
  test(
    'delivery summary exposes state without identity or command content',
    () {
      final messages = [
        ChatMessage(
          localId: 'private-local-id',
          remoteId: 'private-remote-id',
          threadId: 'private-thread',
          senderDid: 'private-sender',
          receiverDid: 'private-recipient',
          content: 'private-command',
          payloadJson: '{"secret":"private-payload"}',
          createdAt: DateTime.utc(2026),
          isMine: true,
          sendState: MessageSendState.sent,
        ),
        ChatMessage(
          localId: 'private-local-id-2',
          threadId: 'private-thread',
          senderDid: 'private-sender',
          content: 'private-command',
          createdAt: DateTime.utc(2026),
          isMine: false,
          sendState: MessageSendState.failed,
        ),
      ];
      expect(codingAgentControlDeliverySummary(messages), [
        {'outgoing': true, 'state': 'sent', 'remote_id_present': true},
        {'outgoing': false, 'state': 'failed', 'remote_id_present': false},
      ]);
    },
  );
}
