import 'dart:async';

import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/presentation/chat/message_actions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageActionContext', () {
    test(
      'freezes the real message and conversation and resolves copy text',
      () {
        final message = _message(content: 'complete message');
        final conversation = _conversation();

        final selected = _context(
          message: message,
          conversation: conversation,
          selectedText: 'selected text',
        );
        final fallback = _context(message: message, conversation: conversation);

        expect(identical(selected.message, message), isTrue);
        expect(identical(selected.conversation, conversation), isTrue);
        expect(selected.copySelectionText, 'selected text');
        expect(fallback.copySelectionText, 'complete message');
        expect(selected.isDesktop, isTrue);
        expect(_context(platform: TargetPlatform.windows).isDesktop, isTrue);
        expect(_context(platform: TargetPlatform.linux).isDesktop, isTrue);
        expect(_context(platform: TargetPlatform.android).isDesktop, isFalse);
        expect(_context(platform: TargetPlatform.iOS).isDesktop, isFalse);
        expect(_context(platform: TargetPlatform.fuchsia).isDesktop, isFalse);
      },
    );
  });

  group('MessageActionCatalog', () {
    test('filters hidden actions and sorts stably by group and order', () {
      final context = _context();
      final disabled = _action(
        id: MessageActionId.copyAll,
        group: MessageActionGroup.selection,
        order: 20,
        isEnabled: (_) => false,
      );
      final sameOrderFirst = _action(
        id: MessageActionId.copySelection,
        group: MessageActionGroup.content,
        order: 10,
        label: 'same-order-first',
      );
      final sameOrderSecond = _action(
        id: MessageActionId.selectAll,
        group: MessageActionGroup.content,
        order: 10,
        label: 'same-order-second',
      );
      final hidden = _action(
        id: MessageActionId.selectAll,
        group: MessageActionGroup.selection,
        order: 1,
        isVisible: (_) => false,
      );

      final resolved = MessageActionCatalog(<MessageActionSpec>[
        sameOrderFirst,
        disabled,
        hidden,
        sameOrderSecond,
      ]).resolve(context);

      expect(resolved, <MessageActionSpec>[
        disabled,
        sameOrderFirst,
        sameOrderSecond,
      ]);
      expect(resolved.first.isEnabled(context), isFalse);
    });
  });

  group('MessageActionExecutor', () {
    test('honors before, after, and keep-open dismissal policies', () async {
      final executor = MessageActionExecutor();
      final context = _context();
      final events = <String>[];

      Future<void> execute(
        MessageActionMenuDismissPolicy policy, {
        bool preserveSelection = false,
      }) async {
        await executor.execute(
          action: _action(
            id: MessageActionId.copySelection,
            dismissPolicy: policy,
            preserveSelectionOnDismiss: preserveSelection,
            onInvoke: (_) => events.add('invoke'),
          ),
          context: context,
          dismissMenu: ({required preserveSelection}) {
            events.add('dismiss:$preserveSelection');
          },
          onUnexpectedError: (error, stackTrace) => fail('$error'),
        );
      }

      await execute(MessageActionMenuDismissPolicy.beforeExecution);
      expect(events, <String>['dismiss:false', 'invoke']);

      events.clear();
      await execute(
        MessageActionMenuDismissPolicy.afterExecution,
        preserveSelection: true,
      );
      expect(events, <String>['invoke', 'dismiss:true']);

      events.clear();
      await execute(MessageActionMenuDismissPolicy.keepOpen);
      expect(events, <String>['invoke']);
    });

    test('rejects disabled and concurrent execution', () async {
      final executor = MessageActionExecutor();
      final context = _context();
      final release = Completer<void>();
      var invocationCount = 0;
      final action = _action(
        id: MessageActionId.copySelection,
        onInvoke: (_) async {
          invocationCount += 1;
          await release.future;
        },
      );

      final first = executor.execute(
        action: action,
        context: context,
        dismissMenu: ({required preserveSelection}) {},
        onUnexpectedError: (error, stackTrace) => fail('$error'),
      );
      expect(executor.activeAction, MessageActionId.copySelection);
      expect(
        await executor.execute(
          action: action,
          context: context,
          dismissMenu: ({required preserveSelection}) {},
          onUnexpectedError: (error, stackTrace) => fail('$error'),
        ),
        isFalse,
      );
      expect(invocationCount, 1);

      release.complete();
      expect(await first, isTrue);
      expect(executor.activeAction, isNull);

      expect(
        await executor.execute(
          action: _action(id: MessageActionId.copyAll, isEnabled: (_) => false),
          context: context,
          dismissMenu: ({required preserveSelection}) {},
          onUnexpectedError: (error, stackTrace) => fail('$error'),
        ),
        isFalse,
      );
    });

    test('routes unexpected errors through the shared handler', () async {
      final executor = MessageActionExecutor();
      final failure = StateError('copy failed');
      Object? handledError;
      StackTrace? handledStackTrace;

      final result = await executor.execute(
        action: _action(
          id: MessageActionId.copyAll,
          onInvoke: (_) => throw failure,
        ),
        context: _context(),
        dismissMenu: ({required preserveSelection}) {},
        onUnexpectedError: (error, stackTrace) {
          handledError = error;
          handledStackTrace = stackTrace;
        },
      );

      expect(result, isFalse);
      expect(identical(handledError, failure), isTrue);
      expect(handledStackTrace, isNotNull);
      expect(executor.activeAction, isNull);
    });
  });
}

MessageActionSpec _action({
  required MessageActionId id,
  MessageActionGroup group = MessageActionGroup.selection,
  int order = 10,
  String label = 'action',
  MessageActionAvailability? isVisible,
  MessageActionAvailability? isEnabled,
  MessageActionMenuDismissPolicy dismissPolicy =
      MessageActionMenuDismissPolicy.beforeExecution,
  bool preserveSelectionOnDismiss = false,
  MessageActionHandler? onInvoke,
}) {
  return MessageActionSpec(
    id: id,
    group: group,
    order: order,
    label: label,
    icon: CupertinoIcons.doc,
    isVisible: isVisible ?? (_) => true,
    isEnabled: isEnabled ?? (_) => true,
    dismissPolicy: dismissPolicy,
    preserveSelectionOnDismiss: preserveSelectionOnDismiss,
    onInvoke: onInvoke ?? (_) {},
  );
}

MessageActionContext _context({
  ChatMessage? message,
  ConversationSummary? conversation,
  String? selectedText,
  TargetPlatform platform = TargetPlatform.macOS,
}) {
  final resolvedMessage = message ?? _message();
  return MessageActionContext(
    message: resolvedMessage,
    conversation: conversation ?? _conversation(),
    fullText: resolvedMessage.content,
    selectedText: selectedText,
    platform: platform,
  );
}

ChatMessage _message({String content = 'complete message'}) {
  return ChatMessage(
    localId: 'message-1',
    remoteId: 'remote-message-1',
    conversationId: 'conversation-1',
    threadId: 'thread-1',
    senderDid: 'did:test:peer',
    receiverDid: 'did:test:me',
    content: content,
    createdAt: DateTime.utc(2026, 8, 13),
    isMine: false,
    sendState: MessageSendState.sent,
  );
}

ConversationSummary _conversation() {
  return ConversationSummary(
    conversationId: 'conversation-1',
    threadId: 'thread-1',
    displayName: 'Peer',
    lastMessagePreview: 'complete message',
    lastMessageAt: DateTime.utc(2026, 8, 13),
    unreadCount: 0,
    isGroup: false,
    targetDid: 'did:test:peer',
  );
}
