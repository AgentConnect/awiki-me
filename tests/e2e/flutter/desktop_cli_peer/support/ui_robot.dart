part of '../desktop_cli_peer_e2e.dart';

/// A small page object for real desktop product actions.
///
/// It only performs visible input, tap, navigation, lifecycle, and drop
/// operations. Business services remain read-only oracles outside this class.
class _DesktopAppRobot {
  _DesktopAppRobot(this.tester);

  final WidgetTester tester;

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(AppShell)));

  ConversationSummary get selectedConversation {
    final selected = container.read(selectedConversationProvider);
    if (selected == null) {
      fail('No conversation is selected in the App UI.');
    }
    return selected;
  }

  Future<void> activate(AppSession session) async {
    await container
        .read(appRuntimeProvider.notifier)
        .activateSession(session.toLegacySessionIdentity());
    await pumpUntil(
      description: 'authenticated App shell',
      condition: () =>
          find.bySemanticsIdentifier('e2e-authenticated').evaluate().length ==
          1,
    );
  }

  Future<ConversationSummary> startDirectConversation(String peerHandle) async {
    await tapOne(
      find.byKey(const Key('start-conversation-button')),
      description: 'start conversation button',
    );
    await pumpUntilFinder(
      find.byKey(const Key('identity-lookup-input')),
      description: 'identity lookup input',
    );
    await tester.enterText(
      find.byKey(const Key('identity-lookup-input')),
      peerHandle,
    );
    await tapOne(
      find.byKey(const Key('identity-lookup-search-button')),
      description: 'identity lookup search button',
    );
    await pumpUntilFinder(
      find.byKey(const Key('identity-start-chat-button')),
      description: 'resolved start-chat action',
      enabled: true,
    );
    await tapOne(
      find.byKey(const Key('identity-start-chat-button')),
      description: 'start-chat action',
    );
    await pumpUntilFinder(
      find.bySemanticsIdentifier('e2e-chat-input'),
      description: 'chat composer after start conversation',
    );
    final selected = selectedConversation;
    if (selected.isGroup || (selected.targetDid?.trim().isEmpty ?? true)) {
      fail('UI resolved an invalid direct conversation: $selected');
    }
    return selected;
  }

  Future<void> sendText(String content) async {
    final input = find.bySemanticsIdentifier('e2e-chat-input');
    await pumpUntilFinder(input, description: 'chat input');
    await tester.enterText(input, content);
    await tapOne(
      find.bySemanticsIdentifier('e2e-chat-send-button'),
      description: 'chat send button',
    );
  }

  Future<void> retryFailedText() async {
    final retry = find.byWidgetPredicate(
      (widget) =>
          widget.key is Key &&
          widget.key.toString().contains('chat-retry-message:'),
      description: 'failed message retry action',
    );
    await tapOne(retry, description: 'failed message retry action');
  }

  Future<void> expectMessageContentVisible(
    ChatMessage message, {
    String? expectedText,
  }) async {
    final text = expectedText ?? message.content;
    final content = find.byKey(Key('chat-message-content:${message.localId}'));
    await pumpUntilFinder(
      content,
      description: 'message content container ${message.localId}',
    );
    await pumpUntilFinder(
      find.descendant(
        of: content,
        matching: find.text(text, findRichText: true),
      ),
      description: 'message ${message.localId} exact visible text "$text"',
    );
    expectExactlyOneVisibleMessageContent(
      localId: message.localId,
      expectedText: text,
    );
  }

  Future<String> sendMention({
    required String handle,
    required String suffix,
  }) async {
    final input = find.bySemanticsIdentifier('e2e-chat-input');
    await tester.enterText(input, '@$handle');
    await pumpUntilFinder(
      find.byKey(const Key('chat-mention-candidate-panel')),
      description: 'mention candidate panel',
    );
    final candidate = find.byWidgetPredicate(
      (widget) =>
          widget.key is Key &&
          widget.key.toString().contains('chat-mention-candidate-') &&
          !widget.key.toString().contains('candidate-panel'),
      description: 'enabled mention candidate',
    );
    await pumpUntilFinder(candidate, description: 'mention candidate');
    await tester.tap(candidate.first);
    await tester.pump();
    final field = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField).last,
    );
    final selectedSurface = field.controller?.text ?? '';
    if (!selectedSurface.startsWith('@') || selectedSurface.trim().isEmpty) {
      fail('Mention candidate did not update the composer.');
    }
    await tester.enterText(input, '$selectedSurface $suffix');
    await tapOne(
      find.bySemanticsIdentifier('e2e-chat-send-button'),
      description: 'mention send button',
    );
    return '$selectedSurface $suffix';
  }

  Future<void> navigateToContacts() => tapOne(
    find.bySemanticsIdentifier('e2e-contacts-tab'),
    description: 'Contacts tab',
  );

  Future<void> navigateToMessages() => tapOne(
    find.bySemanticsIdentifier('e2e-messages-tab'),
    description: 'Messages tab',
  );

  Future<void> expectConversationUnreadBadge({
    required String conversationId,
    required int unreadCount,
  }) async {
    final row = find.byKey(Key('conversation-row:$conversationId'));
    await pumpUntilFinder(
      row,
      description: 'conversation row $conversationId',
      timeout: const Duration(seconds: 90),
    );
    final unreadBadge = find.descendant(
      of: row,
      matching: find.byKey(const Key('conversation-preview-tag-unread')),
    );
    await pumpUntilFinder(
      unreadBadge,
      description: 'conversation row unread badge',
    );
    expect(
      find.descendant(of: unreadBadge, matching: find.text('$unreadCount')),
      findsOneWidget,
    );
  }

  Future<void> openConversationRow(String conversationId) => tapOne(
    find.byKey(Key('conversation-row:$conversationId')),
    description: 'conversation row $conversationId',
  );

  Future<void> followSelectedPeer() async {
    await tapOne(
      find.byKey(const Key('chat-peer-info-avatar-button')),
      description: 'peer info button',
    );
    await pumpUntilFinder(
      find.byKey(const Key('peer-info-dialog-handle-value')),
      description: 'handle-first peer identity header',
    );
    await pumpUntilFinder(
      find.byKey(const Key('chat-follow-button')),
      description: 'follow button',
    );
    await tapOne(
      find.byKey(const Key('chat-follow-button')),
      description: 'follow button',
    );
    await pumpUntilFinder(
      find.byKey(const Key('chat-unfollow-button')),
      description: 'following state',
    );
    expect(
      find.byKey(const Key('chat-relationship-action-progress')),
      findsNothing,
      reason: 'follow mutation must release its busy indicator',
    );
  }

  Future<void> unfollowSelectedPeer() async {
    final unfollow = find.byKey(const Key('chat-unfollow-button'));
    await pumpUntilFinder(unfollow, description: 'unfollow button');
    await tapOne(unfollow, description: 'unfollow button');
    await pumpUntilFinder(
      find.byKey(const Key('confirm-unfollow-button')),
      description: 'unfollow confirmation',
    );
    await tapOne(
      find.byKey(const Key('confirm-unfollow-button')),
      description: 'confirm unfollow',
    );
    await pumpUntilFinder(
      find.byKey(const Key('chat-follow-button')),
      description: 'unfollowed state',
    );
    expect(
      find.byKey(const Key('chat-relationship-action-progress')),
      findsNothing,
      reason: 'unfollow mutation must release its busy indicator',
    );
  }

  Future<void> closePeerInfo() => tapOne(
    find.byKey(const Key('peer-info-close-button')),
    description: 'peer info close button',
  );

  Future<ConversationSummary> createGroup(String name) async {
    await navigateToContacts();
    await pumpUntilFinder(
      find.byKey(const Key('friends-groups-row')),
      description: 'Groups row',
    );
    await tapOne(
      find.byKey(const Key('friends-groups-row')),
      description: 'Groups row',
    );
    await pumpUntilFinder(
      find.byKey(const Key('group-list-create-button')),
      description: 'create group button',
    );
    await tapOne(
      find.byKey(const Key('group-list-create-button')),
      description: 'create group button',
    );
    await pumpUntilFinder(
      find.byKey(const Key('create-group-name-input')),
      description: 'group name input',
    );
    await tester.enterText(
      find.byKey(const Key('create-group-name-input')),
      name,
    );
    await tapOne(
      find.byKey(const Key('create-group-submit-button')),
      description: 'create group submit button',
    );
    await pumpUntilFinder(
      find.bySemanticsIdentifier('e2e-chat-input'),
      description: 'new group chat composer',
      timeout: const Duration(seconds: 90),
    );
    final selected = selectedConversation;
    if (!selected.isGroup || (selected.groupId?.trim().isEmpty ?? true)) {
      fail('UI group creation did not select a canonical group: $selected');
    }
    return selected;
  }

  Future<void> addGroupMember(String handle) async {
    await tapOne(
      find.byKey(const Key('chat-header-add-group-member-button')),
      description: 'add group member button',
    );
    await pumpUntilFinder(
      find.byKey(const Key('identity-lookup-input')),
      description: 'group member lookup input',
    );
    await tester.enterText(
      find.byKey(const Key('identity-lookup-input')),
      handle,
    );
    await tapOne(
      find.byKey(const Key('identity-lookup-search-button')),
      description: 'group member search button',
    );
    await pumpUntilFinder(
      find.byKey(const Key('identity-add-group-member-button')),
      description: 'resolved add-member action',
      enabled: true,
    );
    await tapOne(
      find.byKey(const Key('identity-add-group-member-button')),
      description: 'add resolved group member',
    );
    await pumpUntil(
      description: 'group member dialog closes',
      condition: () => find
          .byKey(const Key('identity-add-group-member-button'))
          .evaluate()
          .isEmpty,
    );
  }

  Future<void> stageAttachmentByDesktopDrop({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final dropTarget = find.byWidgetPredicate(
      (widget) =>
          widget.key is Key &&
          widget.key.toString().contains('chat-attachment-drop-target:'),
      description: 'chat attachment drop target',
    );
    await pumpUntilFinder(dropTarget, description: 'attachment drop target');
    final center = tester.getCenter(dropTarget.first);
    await _sendDesktopDropMethod('entered', <double>[center.dx, center.dy]);
    await _sendDesktopDropMethod('updated', <double>[center.dx, center.dy]);
    await pumpUntilFinder(
      find.byKey(const Key('chat-attachment-drop-overlay')),
      description: 'attachment drop overlay',
    );
    await _sendDesktopDropMethod('performOperation_web', <Map<String, Object?>>[
      <String, Object?>{
        'uri': '',
        'children': <Map<String, Object?>>[],
        'data': bytes,
        'name': filename,
        'type': mimeType,
        'size': bytes.length,
        'relativePath': null,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      },
    ]);
    await pumpUntilFinder(
      find.byKey(const Key('chat-pending-attachment-preview')),
      description: 'pending attachment preview',
    );
  }

  Future<void> sendStagedAttachment({String? caption}) async {
    if (caption != null && caption.isNotEmpty) {
      await tester.enterText(
        find.bySemanticsIdentifier('e2e-chat-input'),
        caption,
      );
    }
    await tapOne(
      find.bySemanticsIdentifier('e2e-chat-send-button'),
      description: 'attachment send button',
    );
    await pumpUntil(
      description: 'pending attachment clears after send',
      condition: () => find
          .byKey(const Key('chat-pending-attachment-preview'))
          .evaluate()
          .isEmpty,
      timeout: const Duration(seconds: 90),
    );
  }

  Future<void> simulateReconnect() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await pumpUntilFinder(
      find.bySemanticsIdentifier('e2e-authenticated'),
      description: 'App shell after lifecycle reconnect',
    );
  }

  /// Rebuilds the Widget tree and App shell in this integration-test process.
  /// This is intentionally not evidence of a native OS process restart.
  Future<void> restart({
    required AppBootstrap bootstrap,
    required List<Override> providerOverrides,
    required AppSession session,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      AwikiMeApp(bootstrap: bootstrap, providerOverrides: providerOverrides),
    );
    await pumpUntilFinder(
      find.byType(AppShell),
      description: 'AppShell after widget restart',
      timeout: const Duration(seconds: 90),
    );
    if (find.bySemanticsIdentifier('e2e-authenticated').evaluate().isEmpty) {
      await activate(session);
    }
    await pumpUntilFinder(
      find.bySemanticsIdentifier('e2e-authenticated'),
      description: 'authenticated App after widget restart',
      timeout: const Duration(seconds: 90),
    );
  }

  Future<void> _sendDesktopDropMethod(String method, Object? arguments) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'desktop_drop',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        );
    await tester.pump();
  }

  Future<void> tapOne(Finder finder, {required String description}) async {
    await pumpUntilFinder(finder, description: description, enabled: true);
    if (finder.evaluate().length != 1) {
      fail(
        'Expected exactly one $description before tap, found '
        '${finder.evaluate().length}.',
      );
    }
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> pumpUntilFinder(
    Finder finder, {
    required String description,
    bool enabled = false,
    Duration timeout = const Duration(seconds: 45),
  }) {
    return pumpUntil(
      description: description,
      timeout: timeout,
      condition: () {
        final elements = finder.evaluate().toList(growable: false);
        if (elements.length != 1) {
          return false;
        }
        if (enabled) {
          final widget = elements.single.widget;
          if (widget is AppPrimaryButton && widget.onPressed == null) {
            return false;
          }
          if (widget is AppPressable &&
              (!widget.enabled || widget.onTap == null)) {
            return false;
          }
          if (widget is AppIconButton && widget.onPressed == null) {
            return false;
          }
        }
        return true;
      },
    );
  }

  Future<void> pumpUntil({
    required String description,
    required bool Function() condition,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        await tester.pump(const Duration(milliseconds: 200));
        if (condition()) {
          return;
        }
      } on Object catch (error) {
        lastError = error;
      }
    }
    fail(
      'Timed out waiting for $description.'
      '${lastError == null ? '' : ' Last error: $lastError'}',
    );
  }
}

/// Deterministic E2E-only transport fault. It emits a real timeline patch so
/// the production failed/retry UI is exercised, then delegates the retry to
/// the real awiki.info-backed messaging service.
class _FailOnceMessagingService
    implements
        MessagingService,
        LocalHistoryMessagingService,
        ThreadPatchMessagingService,
        ConversationTimelineMessagingService {
  _FailOnceMessagingService({
    required MessagingService delegate,
    required this.ownerDid,
  }) : _delegate = delegate;

  final MessagingService _delegate;
  final String ownerDid;
  bool _failNextConversationText = false;
  final Map<String, List<_PatchSink>> _patchSinks =
      <String, List<_PatchSink>>{};
  final Map<String, int> _patchVersions = <String, int>{};

  void failNextConversationText() {
    _failNextConversationText = true;
  }

  @override
  Future<ChatMessage> sendConversationText({
    required AppConversationReadRef conversation,
    required String content,
    String? clientMessageId,
    String? idempotencyKey,
  }) async {
    if (_failNextConversationText) {
      _failNextConversationText = false;
      final localId = clientMessageId?.trim();
      if (localId == null || localId.isEmpty) {
        throw StateError('Controlled E2E failure requires clientMessageId.');
      }
      final target = _threadTarget(conversation.conversationId);
      final failed = ChatMessage(
        localId: localId,
        conversationId: conversation.conversationId,
        threadId: conversation.conversationId,
        senderDid: ownerDid,
        receiverDid: target.kind == 'direct' ? target.id : null,
        groupId: target.kind == 'group' ? target.id : null,
        content: content,
        createdAt: DateTime.now(),
        isMine: true,
        sendState: MessageSendState.failed,
      );
      final version = _nextPatchVersion(conversation.conversationId);
      for (final sink
          in _patchSinks[conversation.conversationId] ?? const <_PatchSink>[]) {
        sink.emit(
          ThreadMessagePatch(
            kind: ThreadMessagePatchKind.upsert,
            ownerDid: ownerDid,
            version: version,
            threadKind: target.kind,
            threadId: target.id,
            conversationId: conversation.conversationId,
            message: failed,
          ),
        );
      }
      throw StateError('controlled_e2e_transport_failure');
    }
    return _delegate.sendConversationText(
      conversation: conversation,
      content: content,
      clientMessageId: clientMessageId,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Stream<ThreadMessagePatch> watchConversationTimelinePatches(
    AppConversationReadRef conversation, {
    int limit = 100,
  }) {
    final timeline = _timelineDelegate;
    late final StreamController<ThreadMessagePatch> controller;
    StreamSubscription<ThreadMessagePatch>? subscription;
    late final _PatchSink sink;
    controller = StreamController<ThreadMessagePatch>(
      onListen: () {
        sink = _PatchSink(controller);
        _patchSinks
            .putIfAbsent(conversation.conversationId, () => <_PatchSink>[])
            .add(sink);
        subscription = timeline
            .watchConversationTimelinePatches(conversation, limit: limit)
            .listen(
              (patch) => sink.emit(
                _withPatchVersion(
                  patch,
                  _nextPatchVersion(conversation.conversationId),
                ),
              ),
              onError: controller.addError,
              onDone: controller.close,
            );
      },
      onCancel: () async {
        _patchSinks[conversation.conversationId]?.remove(sink);
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  ConversationTimelineMessagingService get _timelineDelegate {
    final delegate = _delegate;
    if (delegate is! ConversationTimelineMessagingService) {
      throw StateError('Real messaging service lacks conversation timeline.');
    }
    return delegate as ConversationTimelineMessagingService;
  }

  LocalHistoryMessagingService get _localDelegate {
    final delegate = _delegate;
    if (delegate is! LocalHistoryMessagingService) {
      throw StateError('Real messaging service lacks local history.');
    }
    return delegate as LocalHistoryMessagingService;
  }

  ThreadPatchMessagingService get _threadPatchDelegate {
    final delegate = _delegate;
    if (delegate is! ThreadPatchMessagingService) {
      throw StateError('Real messaging service lacks thread patches.');
    }
    return delegate as ThreadPatchMessagingService;
  }

  @override
  Future<List<ChatMessage>> loadConversationTimeline(
    AppConversationReadRef conversation, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) => _timelineDelegate.loadConversationTimeline(
    conversation,
    limit: limit,
    cursor: cursor,
    includeControlPayloads: includeControlPayloads,
  );

  @override
  Future<ThreadMessagePatch> repairConversationTimelineStore(
    AppConversationReadRef conversation, {
    int limit = 100,
  }) async {
    final patch = await _timelineDelegate.repairConversationTimelineStore(
      conversation,
      limit: limit,
    );
    return _withPatchVersion(
      patch,
      _nextPatchVersion(conversation.conversationId),
    );
  }

  @override
  Future<List<ChatMessage>> loadLocalHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) => _localDelegate.loadLocalHistory(
    thread,
    limit: limit,
    cursor: cursor,
    includeControlPayloads: includeControlPayloads,
  );

  @override
  Stream<ThreadMessagePatch> watchThreadPatches(
    AppThreadRef thread, {
    int limit = 100,
  }) => _threadPatchDelegate.watchThreadPatches(thread, limit: limit);

  @override
  Future<ThreadMessagePatch> repairThreadStore(
    AppThreadRef thread, {
    int limit = 100,
  }) => _threadPatchDelegate.repairThreadStore(thread, limit: limit);

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) => _delegate.sendText(thread: thread, content: content);

  @override
  Future<ChatMessage> sendAttachment({
    required AppThreadRef thread,
    required AttachmentDraft attachment,
    String? caption,
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
    String? idempotencyKey,
  }) => _delegate.sendAttachment(
    thread: thread,
    attachment: attachment,
    caption: caption,
    mentions: mentions,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<ChatMessage> sendConversationAttachment({
    required AppConversationReadRef conversation,
    required AttachmentDraft attachment,
    String? caption,
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
    String? clientMessageId,
    String? idempotencyKey,
  }) => _delegate.sendConversationAttachment(
    conversation: conversation,
    attachment: attachment,
    caption: caption,
    mentions: mentions,
    clientMessageId: clientMessageId,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  }) => _delegate.sendPayload(
    thread: thread,
    payload: payload,
    secure: secure,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<ChatMessage> sendMentionText({
    required AppThreadRef thread,
    required String text,
    required List<ChatMentionDraft> mentions,
    String? idempotencyKey,
  }) => _delegate.sendMentionText(
    thread: thread,
    text: text,
    mentions: mentions,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<ChatMessage> sendConversationMentionText({
    required AppConversationReadRef conversation,
    required String text,
    required List<ChatMentionDraft> mentions,
    String? clientMessageId,
    String? idempotencyKey,
  }) => _delegate.sendConversationMentionText(
    conversation: conversation,
    text: text,
    mentions: mentions,
    clientMessageId: clientMessageId,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<AttachmentDownloadResult> downloadAttachment({
    required AppThreadRef thread,
    required String messageId,
    String? attachmentId,
    String? localPath,
  }) => _delegate.downloadAttachment(
    thread: thread,
    messageId: messageId,
    attachmentId: attachmentId,
    localPath: localPath,
  );

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) => _delegate.loadHistory(
    thread,
    limit: limit,
    cursor: cursor,
    includeControlPayloads: includeControlPayloads,
  );

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) =>
      _delegate.retryByResendOriginalContent(failed);

  int _nextPatchVersion(String conversationId) {
    final next = (_patchVersions[conversationId] ?? 0) + 1;
    _patchVersions[conversationId] = next;
    return next;
  }
}

class _PatchSink {
  _PatchSink(this.controller);

  final StreamController<ThreadMessagePatch> controller;

  void emit(ThreadMessagePatch patch) {
    if (!controller.isClosed) {
      controller.add(patch);
    }
  }
}

class _RecordingAttachmentOpenService extends AttachmentOpenService {
  String? lastOpenedPath;

  @override
  Future<void> open(String pathOrUri) async {
    lastOpenedPath = pathOrUri;
  }
}

({String kind, String id}) _threadTarget(String conversationId) {
  final separator = conversationId.indexOf(':');
  if (separator <= 0 || separator == conversationId.length - 1) {
    return (kind: 'unknown', id: conversationId);
  }
  final prefix = conversationId.substring(0, separator).toLowerCase();
  return (
    kind: prefix == 'dm' ? 'direct' : prefix,
    id: conversationId.substring(separator + 1),
  );
}

ThreadMessagePatch _withPatchVersion(ThreadMessagePatch patch, int version) =>
    ThreadMessagePatch(
      kind: patch.kind,
      ownerDid: patch.ownerDid,
      version: version,
      threadKind: patch.threadKind,
      threadId: patch.threadId,
      conversationId: patch.conversationId,
      messages: patch.messages,
      message: patch.message,
      index: patch.index,
      messageId: patch.messageId,
      reason: patch.reason,
    );
