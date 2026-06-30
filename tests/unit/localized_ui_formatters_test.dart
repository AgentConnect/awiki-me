import 'package:awiki_me/l10n/app_localizations_en.dart';
import 'package:awiki_me/l10n/app_localizations_zh.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/presentation/shared/formatters/localized_ui_formatters.dart';
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
