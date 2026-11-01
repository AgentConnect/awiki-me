part of '../chat_page.dart';

extension _ChatMessageManagement on _ChatViewState {
  void _quoteMessage(ChatMessage message) {
    final excerpt = _copyableMessageText(context, message);
    _updateMessageManagement(() {
      _reply = MessageReplyReference(
        sourceMessageId: message.remoteId ?? message.localId,
        senderName: _displayNameForMessage(context, message),
        excerpt: String.fromCharCodes(excerpt.runes.take(500)),
      );
      _composerFocusRequestId++;
    });
    ref
        .read(chatComposerDraftsProvider.notifier)
        .setReply(widget.conversation, _reply);
  }

  void _startMessageSelection(ChatMessage message) {
    _updateMessageManagement(() {
      _selectionMode = true;
      _selectedMessageIds
        ..clear()
        ..add(message.localId);
    });
  }

  void _toggleMessageSelection(ChatMessage message) {
    if (_deletingMessages) return;
    _updateMessageManagement(() {
      if (!_selectedMessageIds.remove(message.localId)) {
        _selectedMessageIds.add(message.localId);
      }
    });
  }

  Widget _selectableMessageRow(ChatMessage message, Widget child) {
    if (!_selectionMode) return child;
    final selected = _selectedMessageIds.contains(message.localId);
    return Semantics(
      checked: selected,
      child: GestureDetector(
        key: Key('chat-message-select:${message.localId}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _toggleMessageSelection(message),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                selected
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.circle,
                color: selected
                    ? context.awikiTheme.primary
                    : context.awikiTheme.secondaryText,
                size: 22,
              ),
            ),
            Expanded(child: IgnorePointer(child: child)),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMessages(List<ChatMessage> messages) async {
    if (_deletingMessages || messages.isEmpty) return;
    final conversationId = widget.conversation.conversationId;
    final epoch = ref.read(sessionProvider).activeEpoch;
    if (epoch == null) return;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(context.l10n.chatDeleteMessagesTitle(messages.length)),
        content: Text(context.l10n.chatDeleteMessagesLocalNotice),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.commonCancel),
          ),
          CupertinoDialogAction(
            key: const Key('chat-confirm-delete-messages'),
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        widget.conversation.conversationId != conversationId ||
        !epoch.matches(ref.read(sessionProvider))) {
      return;
    }
    _updateMessageManagement(() => _deletingMessages = true);
    try {
      await ref
          .read(localMessageDeletionsProvider(conversationId).notifier)
          .delete(messages);
      if (!mounted ||
          widget.conversation.conversationId != conversationId ||
          !epoch.matches(ref.read(sessionProvider))) {
        return;
      }
      _updateMessageManagement(() {
        _selectionMode = false;
        _selectedMessageIds.clear();
        if (messages.any(
          (m) => messageDeletionKeys(m).contains(_reply?.sourceMessageId),
        )) {
          _cancelReply();
        }
      });
    } catch (_) {
      if (mounted && epoch.matches(ref.read(sessionProvider))) {
        AwikiMeToast.show(
          context,
          context.l10n.operationFailedRetry,
          danger: true,
        );
      }
    } finally {
      if (mounted) _updateMessageManagement(() => _deletingMessages = false);
    }
  }

  Widget _buildMessageSelectionBar(List<ChatMessage> messages) {
    final selected = messages
        .where((m) => _selectedMessageIds.contains(m.localId))
        .toList();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape):
            _cancelMessageSelection,
      },
      child: Focus(
        autofocus: true,
        child: SafeArea(
          top: false,
          child: Padding(
            key: const Key('chat-message-selection-bar'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                CupertinoButton(
                  onPressed: _deletingMessages ? null : _cancelMessageSelection,
                  child: Text(context.l10n.commonCancel),
                ),
                Expanded(
                  child: Text(
                    context.l10n.chatMessagesSelected(selected.length),
                    textAlign: TextAlign.center,
                  ),
                ),
                CupertinoButton(
                  key: const Key('chat-delete-selected-messages'),
                  onPressed: selected.isEmpty || _deletingMessages
                      ? null
                      : () => _deleteMessages(selected),
                  child: _deletingMessages
                      ? const CupertinoActivityIndicator()
                      : Text(
                          context.l10n.commonDelete,
                          style: TextStyle(color: context.awikiTheme.alert),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _cancelMessageSelection() {
    if (_deletingMessages) return;
    _updateMessageManagement(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  Widget _buildComposerReply() => Container(
    key: const Key('chat-composer-reply'),
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    padding: const EdgeInsets.only(left: 10),
    decoration: BoxDecoration(
      color: context.awikiTheme.surface,
      border: Border(
        left: BorderSide(color: context.awikiTheme.primary, width: 3),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${context.l10n.chatReply} ${_reply!.senderName ?? ''}\n${_reply!.excerpt ?? ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: context.awikiTheme.secondaryText,
            ),
          ),
        ),
        CupertinoButton(
          key: const Key('chat-cancel-reply'),
          onPressed: _cancelReply,
          child: const Icon(CupertinoIcons.xmark, size: 16),
        ),
      ],
    ),
  );

  void _cancelReply() {
    _updateMessageManagement(() => _reply = null);
    ref
        .read(chatComposerDraftsProvider.notifier)
        .setReply(widget.conversation, null);
  }
}

class _MessageQuote extends StatelessWidget {
  const _MessageQuote({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final reply = MessageReplyReference.tryParse(message.payloadJson);
    if (reply?.excerpt == null) return const SizedBox.shrink();
    return Container(
      key: Key('chat-message-quote:${message.localId}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: context.awikiTheme.secondaryText.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
      ),
      child: Text(
        '${reply!.senderName ?? ''}: ${reply.excerpt}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: context.awikiTheme.secondaryText),
      ),
    );
  }
}
