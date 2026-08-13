import 'package:awiki_me/l10n/app_localizations_en.dart';
import 'package:awiki_me/l10n/app_localizations_zh.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_message_v1.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_system_event.dart';
import 'package:awiki_me/src/presentation/shared/formatters/localized_ui_formatters.dart';
import 'package:awiki_me/src/presentation/shared/formatters/markdown_preview_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final zh = AppLocalizationsZh();
  final en = AppLocalizationsEn();

  test('attachment message preview is localized at presentation boundary', () {
    final message = ChatMessage(
      localId: 'msg-1',
      threadId: 'dm:1',
      senderDid: 'did:alice',
      content: '',
      createdAt: DateTime(2026, 6, 30),
      isMine: false,
      sendState: MessageSendState.sent,
      attachment: const ChatAttachment(
        attachmentId: 'att-1',
        filename: 'report.pdf',
        mimeType: 'application/pdf',
      ),
    );

    expect(localizeMessagePreview(zh, message), '附件：report.pdf');
    expect(localizeMessagePreview(en, message), 'Attachment: report.pdf');
  });

  test('typed Agent preview precedes raw-shaped message fields', () {
    ChatMessage message(AgentMessageProjection projection) => ChatMessage(
      localId: 'agent-message',
      threadId: 'dm:agent',
      senderDid: 'did:agent',
      content: 'SHOULD_NOT_RENDER',
      originalType: 'agent_message',
      payloadJson: '{"private":"SHOULD_NOT_RENDER_RAW"}',
      createdAt: DateTime(2026, 8, 11),
      isMine: false,
      sendState: MessageSendState.sent,
      agentMessage: projection,
    );

    expect(
      localizeMessagePreview(
        zh,
        message(
          const ValidAgentMessageProjection(
            AgentMessageV1(
              eventId: 'event-1',
              taskName: 'Release verification',
              kind: AgentMessageKind.message,
              level: AgentMessageLevel.normal,
              summary: 'Validated summary',
              detail: null,
              action: AgentMessageAction.openConversation,
            ),
          ),
        ),
      ),
      'Validated summary',
    );
    expect(
      localizeMessagePreview(
        zh,
        message(const InvalidAgentMessageProjection()),
      ),
      '这条 Agent 消息无法安全显示。',
    );
    expect(
      localizeMessagePreview(
        en,
        message(const InvalidAgentMessageProjection()),
      ),
      'This Agent message cannot be displayed safely.',
    );
  });

  test('empty attachment filename uses localized fallback', () {
    const attachment = ChatAttachment(
      attachmentId: 'att-1',
      filename: '',
      mimeType: 'application/octet-stream',
    );

    expect(localizeAttachmentName(zh, attachment), '文件');
    expect(localizeAttachmentName(en, attachment), 'File');
  });

  test('legacy attachment preview is normalized into current locale', () {
    expect(
      localizeLegacyConversationPreview(zh, '[Attachment] Untitled attachment'),
      '附件：文件',
    );
    expect(
      localizeLegacyConversationPreview(en, '[附件] report.pdf'),
      'Attachment: report.pdf',
    );
  });

  test('markdown plain text preview preserves visible semantics', () {
    expect(markdownPlainTextPreview('**重要**'), '重要');
    expect(markdownPlainTextPreview('# 标题'), '标题');
    expect(markdownPlainTextPreview('- A\n- B'), 'A B');
    expect(markdownPlainTextPreview('[文档](https://example.com)'), '文档');
    expect(markdownPlainTextPreview('`a*b`'), 'a*b');
    expect(
      markdownPlainTextPreview('```dart\nfinal x = 1;\n```'),
      'final x = 1;',
    );
    expect(markdownPlainTextPreview(r'\*不是强调\*'), '*不是强调*');
    expect(markdownPlainTextPreview('普通文本'), '普通文本');
    expect(markdownPlainTextPreview('请看**重点**'), '请看重点');
  });

  test(
    'message preview flattens markdown without rendering markdown widgets',
    () {
      final message = ChatMessage(
        localId: 'msg-1',
        threadId: 'dm:1',
        senderDid: 'did:alice',
        content: '# 标题\n\n请看 **重点** 和 [文档](https://example.com)',
        createdAt: DateTime(2026, 6, 30),
        isMine: false,
        sendState: MessageSendState.sent,
        originalType: 'text/markdown',
      );

      expect(localizeMessagePreview(zh, message), '标题 请看 重点 和 文档');
    },
  );

  test('attachment caption preview flattens markdown before localization', () {
    final message = ChatMessage(
      localId: 'msg-1',
      threadId: 'dm:1',
      senderDid: 'did:alice',
      content: '',
      createdAt: DateTime(2026, 6, 30),
      isMine: false,
      sendState: MessageSendState.sent,
      attachment: const ChatAttachment(
        attachmentId: 'att-1',
        filename: 'report.pdf',
        mimeType: 'application/pdf',
        caption: '**报告** [链接](https://example.com)',
      ),
    );

    expect(localizeMessagePreview(zh, message), '报告 链接');
  });

  test('legacy conversation preview flattens markdown syntax', () {
    expect(
      localizeLegacyConversationPreview(zh, '## 更新\n\n- **完成**\n- `a*b`'),
      '更新 完成 a*b',
    );
  });

  test('group system event uses resolved nickname before DID fallback', () {
    const event = GroupSystemEvent(
      type: 'member_added',
      groupDid: 'did:test:group',
      groupEventSeq: 1,
      actorDid: 'did:wba:awiki.info:user:alice:e1_key',
      subjectDid: 'did:wba:awiki.info:user:bob:e1_key',
    );

    expect(
      localizeGroupSystemEvent(
        zh,
        event,
        actorName: 'Alice nickname',
        subjectName: 'Bob nickname',
      ),
      'Alice nickname邀请Bob nickname加入了群聊',
    );
    expect(
      localizeGroupSystemEvent(
        zh,
        event,
        actorName: 'alice.awiki.info',
        subjectName: 'bob.awiki.info',
      ),
      'alice.awiki.info邀请bob.awiki.info加入了群聊',
    );
    expect(localizeGroupSystemEvent(zh, event), 'alice邀请bob加入了群聊');
  });

  test('conversation snapshot drives localized attachment preview', () {
    final snapshot = ChatMessage(
      localId: 'msg-1',
      threadId: 'dm:1',
      senderDid: 'did:alice',
      content: '',
      createdAt: DateTime(2026, 6, 30),
      isMine: false,
      sendState: MessageSendState.sent,
      attachment: const ChatAttachment(
        attachmentId: 'att-1',
        filename: 'design.md',
        mimeType: 'text/markdown',
      ),
    );
    final conversation = ConversationSummary(
      threadId: 'dm:1',
      conversationId: 'dm:1',
      displayName: 'Alice',
      lastMessagePreview: 'design.md',
      lastMessageAt: snapshot.createdAt,
      unreadCount: 0,
      isGroup: false,
      lastMessageSnapshot: snapshot,
    );

    expect(localizeConversationPreview(zh, conversation), '附件：design.md');
    expect(
      localizeConversationPreview(en, conversation),
      'Attachment: design.md',
    );
  });
}
