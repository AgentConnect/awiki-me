part of '../desktop_cli_peer_e2e.dart';

/// A small page object for real desktop product actions.
///
/// It only performs visible input, tap, navigation, lifecycle, and drop
/// operations. Business services remain read-only oracles outside this class.
class _DesktopAppRobot {
  _DesktopAppRobot(this.tester, {this.failureCaseId});

  final WidgetTester tester;
  String? failureCaseId;

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(AppShell)));

  ConversationSummary get selectedConversation {
    final selectedId = container.read(selectedConversationProvider);
    if (selectedId == null) {
      fail('No conversation is selected in the App UI.');
    }
    for (final conversation
        in container.read(conversationListProvider).conversations) {
      if (conversation.conversationId == selectedId) {
        return conversation;
      }
    }
    fail('Selected conversation "$selectedId" is missing from the App store.');
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

  Future<ConversationSummary> startDirectConversation(
    String peerHandle, {
    String expectedPrimaryDisplayName = _nicknameFixtureDisplayName,
  }) async {
    final directButton = find.byKey(const Key('start-conversation-button'));
    final quickActionsButton = find.bySemanticsIdentifier(
      'e2e-quick-actions-button',
    );
    await pumpUntil(
      description: 'start conversation entry',
      condition: () {
        final directCount = directButton.evaluate().length;
        final quickActionsCount = quickActionsButton.evaluate().length;
        return (directCount == 1 && quickActionsCount == 0) ||
            (directCount == 0 && quickActionsCount == 1);
      },
    );
    final variant = requireDesktopPlatformVariant(
      macOSCount: directButton.evaluate().length,
      otherCount: quickActionsButton.evaluate().length,
      element: 'start-conversation entry',
    );
    switch (variant) {
      case DesktopPlatformVariant.macOS:
        await tapOne(directButton, description: 'start conversation button');
      case DesktopPlatformVariant.other:
        await tapOne(quickActionsButton, description: 'quick actions button');
        await tapOne(
          find.bySemanticsIdentifier('e2e-start-conversation-menu-item'),
          description: 'start conversation menu item',
        );
    }
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
    E2eObservation observeIdentityPreviewTitle() {
      final previewTitle = find.byKey(
        const Key('identity-preview-display-name'),
      );
      final elements = previewTitle.evaluate().toList(growable: false);
      if (elements.isEmpty) {
        return const E2eObservation.pending('identity_preview_pending');
      }
      if (elements.length != 1 || elements.single.widget is! Text) {
        return const E2eObservation.fatal(
          'identity_preview_title_not_exact_one',
        );
      }
      final text = (elements.single.widget as Text).data?.trim() ?? '';
      if (text != expectedPrimaryDisplayName.trim()) {
        return const E2eObservation.fatal(
          'identity_preview_primary_name_mismatch',
        );
      }
      return const E2eObservation.pass();
    }

    await pumpUntilObservation(
      description: 'first visible identity primary title',
      timeout: const Duration(seconds: 90),
      observe: observeIdentityPreviewTitle,
    );
    await pumpUntilFinder(
      find.byKey(const Key('identity-start-chat-button')),
      description: 'resolved start-chat action',
      enabled: true,
    );
    final previewTitle = find.byKey(const Key('identity-preview-display-name'));
    final previewTitleText =
        tester.widget<Text>(previewTitle).data?.trim() ?? '';
    await tapOne(
      find.byKey(const Key('identity-start-chat-button')),
      description: 'start-chat action',
    );
    final expectedPeer = normalizeDidOrHandleInput(peerHandle).toLowerCase();
    await pumpUntil(
      description: 'selected direct conversation after start-chat action',
      timeout: const Duration(seconds: 90),
      condition: () {
        final selectedId = container.read(selectedConversationProvider);
        if (selectedId == null) {
          return false;
        }
        final selected = container
            .read(conversationListProvider)
            .conversations
            .where((item) => item.conversationId == selectedId)
            .firstOrNull;
        if (selected == null ||
            selected.isGroup ||
            (selected.targetDid?.trim().isEmpty ?? true) ||
            (selected.peerPersonaId?.trim().isEmpty ?? true)) {
          return false;
        }
        final profile = container
            .read(peerDisplayProfileProvider)
            .forPeer(
              peerPersonaId: selected.peerPersonaId,
              did: selected.targetDid,
            );
        final resolvedHandle = normalizeDidOrHandleInput(
          profile?.handle ?? '',
        ).toLowerCase();
        return resolvedHandle == expectedPeer ||
            resolvedHandle.startsWith('$expectedPeer.');
      },
    );
    await pumpUntilFinder(
      find.bySemanticsIdentifier('e2e-chat-input'),
      description: 'chat composer after start conversation',
    );
    final selected = selectedConversation;
    if (selected.isGroup || (selected.targetDid?.trim().isEmpty ?? true)) {
      fail('UI resolved an invalid direct conversation: $selected');
    }
    final conversationTitle = expectedDirectDisplayName(selected);
    if (previewTitleText != conversationTitle ||
        conversationTitle != expectedPrimaryDisplayName.trim()) {
      fail(
        'Identity lookup title and canonical conversation title do not match.',
      );
    }
    return selected;
  }

  Future<void> sendText(String content) async {
    final input = find.bySemanticsIdentifier('e2e-chat-input');
    await pumpUntilFinder(input, description: 'chat input');
    final inputField = find.descendant(
      of: input,
      matching: find.byType(CupertinoTextField),
    );
    await pumpUntilFinder(
      inputField,
      description: 'enabled chat input',
      enabled: true,
    );
    await _enterExactComposerText(
      inputField,
      content,
      description: 'chat message input',
    );
    await tapOne(
      find.bySemanticsIdentifier('e2e-chat-send-button'),
      description: 'chat send button',
    );
    await _waitForComposerClear(input, description: 'text send completion');
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

  Future<void> expectMemberAddedSystemEvent({
    required String conversationId,
    required String subjectDid,
    required String expectedMemberName,
  }) async {
    E2eObservation observe() {
      final matches = _uiMessages(this, conversationId)
          .where((message) {
            final event = message.groupSystemEvent;
            return event?.isMemberAdded == true &&
                event?.subjectDid?.trim() == subjectDid.trim();
          })
          .toList(growable: false);
      if (matches.isEmpty) {
        return const E2eObservation.pending('member_added_event_pending');
      }
      if (matches.length != 1) {
        return const E2eObservation.fatal('duplicate_member_added_event');
      }
      final message = matches.single;
      final event = message.groupSystemEvent!;
      final textFinder = find.byKey(
        Key('chat-group-system-event:${message.localId}'),
      );
      final elements = textFinder.evaluate().toList(growable: false);
      if (elements.isEmpty) {
        return const E2eObservation.pending('member_added_event_not_visible');
      }
      if (elements.length != 1 || elements.single.widget is! Text) {
        return const E2eObservation.fatal(
          'member_added_event_rendered_multiple_times',
        );
      }
      final text = (elements.single.widget as Text).data ?? '';
      final l10n = AppLocalizations.of(elements.single);
      final sessionDid = container.read(sessionProvider).session?.did.trim();
      final actorDid = event.actorDid?.trim() ?? '';
      final expectedText = actorDid.isNotEmpty && actorDid == sessionDid
          ? l10n.chatGroupMemberAddedByYou(expectedMemberName)
          : actorDid.isEmpty
          ? l10n.chatGroupMemberJoined(expectedMemberName)
          : l10n.chatGroupMemberAddedBy(
              container.read(
                publicIdentityDisplayNameProvider(
                  PublicIdentityDisplayNameRequest(
                    did: actorDid,
                    unknownLabel: l10n.commonUnknown,
                  ),
                ),
              ),
              expectedMemberName,
            );
      if (text != expectedText) {
        return const E2eObservation.fatal(
          'member_added_event_display_name_mismatch',
        );
      }
      return const E2eObservation.pass();
    }

    await pumpUntilObservation(
      description: 'nickname-first group member-added system event',
      timeout: const Duration(seconds: 90),
      observe: observe,
    );
    await assertStableFor(
      description: 'group member-added display name',
      observe: observe,
    );
  }

  Future<void> expectMessageSenderIdentityProjection({
    required String conversationId,
    required ChatMessage message,
    required String expectedName,
  }) async {
    final anchor = requireGroupSenderLabelAnchor(
      messages: _uiMessages(this, conversationId),
      target: message,
    );
    final anchorContent = find.byKey(
      Key('chat-message-content:${anchor.localId}'),
    );
    await pumpUntilFinder(
      anchorContent,
      description: 'group sender-label anchor ${anchor.localId}',
    );
    await tester.ensureVisible(anchorContent);
    await tester.pumpAndSettle();

    E2eObservation observe() {
      final sender = find.byKey(Key('chat-message-sender:${anchor.localId}'));
      final nameObservation = observeExactScopedText(
        widgets: sender.evaluate().map((element) => element.widget),
        expectedText: expectedName,
        pendingCode: 'message_sender_label_pending',
        exactOneCode: 'message_sender_label_rendered_multiple_times',
        mismatchCode: 'message_sender_display_name_mismatch',
      );
      if (nameObservation.status != E2eObservationStatus.pass) {
        return nameObservation;
      }
      final avatars = find
          .descendant(of: anchorContent, matching: find.byType(AvatarBadge))
          .evaluate()
          .toList(growable: false);
      if (avatars.isEmpty) {
        return const E2eObservation.pending('message_sender_avatar_pending');
      }
      if (avatars.length != 1) {
        return const E2eObservation.fatal(
          'message_sender_avatar_rendered_multiple_times',
        );
      }
      final avatar = avatars.single.widget as AvatarBadge;
      final expectedAvatar = container
          .read(peerDisplayProfileProvider)
          .forPeer(
            peerPersonaId: anchor.senderPeerPersonaId,
            did: anchor.senderDid,
          )
          ?.avatarUri
          ?.trim();
      if (avatar.seed != expectedName ||
          (avatar.avatarUri?.trim() ?? '') != (expectedAvatar ?? '')) {
        return const E2eObservation.fatal(
          'message_sender_avatar_projection_mismatch',
        );
      }
      return const E2eObservation.pass();
    }

    await pumpUntilObservation(
      description: 'exact group message sender identity projection',
      observe: observe,
    );
    await assertStableFor(
      description: 'group message sender identity projection',
      observe: observe,
    );
  }

  Future<String> sendMention({
    required String handle,
    required String expectedDid,
    required String expectedDisplayName,
    required String suffix,
  }) async {
    final input = find.bySemanticsIdentifier('e2e-chat-input');
    final inputField = find.descendant(
      of: input,
      matching: find.byType(CupertinoTextField),
    );
    await pumpUntilFinder(
      inputField,
      description: 'enabled mention composer field',
      enabled: true,
    );
    final selectedGroupDid = selectedConversation.groupId?.trim();
    if (selectedGroupDid == null || selectedGroupDid.isEmpty) {
      fail('Mention composition requires a canonical selected group.');
    }
    await pumpUntil(
      description: 'preloaded mention member projection',
      condition: () {
        final members = container
            .read(groupProvider)
            .membersByGroup[selectedGroupDid];
        return members != null &&
            members.any((member) => member.did.trim() == expectedDid.trim());
      },
    );
    await _enterExactComposerText(
      inputField,
      '@',
      description: 'mention trigger input',
    );
    try {
      await pumpUntilFinder(
        find.byKey(const Key('chat-mention-candidate-panel')),
        description: 'mention candidate panel for typed @ trigger',
      );
    } on Object catch (error) {
      final selected = selectedConversation;
      final groupDid = selected.groupId?.trim();
      if (groupDid == null || groupDid.isEmpty) {
        fail('Mention panel failed without a canonical selected group: $error');
      }
      final field = tester.widget<CupertinoTextField>(inputField);
      final value = field.controller?.value ?? const TextEditingValue();
      final trigger = ChatMentionTrigger.detect(
        text: value.text,
        selectionBaseOffset: value.selection.baseOffset,
        selectionExtentOffset: value.selection.extentOffset,
        composingStart: value.composing.start,
        composingEnd: value.composing.end,
        isGroup: selected.isGroup,
      );
      final members = await container
          .read(groupApplicationServiceProvider)
          .listMembers(groupDid, limit: 100);
      final session = container.read(sessionProvider).session;
      final candidates = ChatMentionCandidate.forGroupMembers(
        members,
        query: handle,
        currentUserDid: session?.did,
        currentUserHandle: session?.handle,
      );
      final matchingMembers = members
          .where((member) {
            return normalizeDidOrHandleInput(member.handle).toLowerCase() ==
                normalizeDidOrHandleInput(handle).toLowerCase();
          })
          .toList(growable: false);
      fail(
        'Mention candidate panel was not visible; member_count='
        '${members.length} matching_member_count=${matchingMembers.length} '
        'candidate_count=${candidates.length} target_active_count='
        '${matchingMembers.where((member) => member.membershipStatus == GroupMemberMembershipStatus.active).length} '
        'target_human_count='
        '${matchingMembers.where((member) => member.subjectType == GroupMemberSubjectType.human).length} '
        'selected_is_group=${selected.isGroup} input_exact_at='
        '${value.text == '@'} selection_collapsed_at_end='
        '${value.selection.isCollapsed && value.selection.end == value.text.length} '
        'trigger_detected=${trigger != null}.',
      );
    }
    tester.testTextInput.enterText('@$handle');
    await tester.pump();
    final filteredPanel = find.byKey(const Key('chat-mention-candidate-panel'));
    final filteredField = tester.widget<CupertinoTextField>(inputField);
    final candidate = find.byKey(
      Key('chat-mention-candidate-member:$expectedDid'),
    );
    if (filteredField.controller?.text != '@$handle' ||
        filteredPanel.evaluate().length != 1 ||
        find
            .descendant(
              of: filteredPanel,
              matching: find.byType(CupertinoActivityIndicator),
            )
            .evaluate()
            .isNotEmpty ||
        candidate.evaluate().length != 1) {
      fail(
        'A preloaded mention query did not filter in the first local frame; '
        'exact_input=${filteredField.controller?.text == '@$handle'} '
        'panel_count=${filteredPanel.evaluate().length} '
        'loading_count=${find.descendant(of: filteredPanel, matching: find.byType(CupertinoActivityIndicator)).evaluate().length} '
        'target_count=${candidate.evaluate().length}.',
      );
    }
    await pumpUntilFinder(candidate, description: 'mention candidate');
    _expectIdentityCandidatePresentation(
      candidate: candidate,
      expectedDisplayName: expectedDisplayName,
      expectedAvatarUri: container
          .read(peerDisplayProfileProvider)
          .forDid(expectedDid)
          ?.avatarUri,
      expectedSurface: '@$expectedDisplayName',
    );
    await tester.tap(candidate.first);
    await tester.pump();
    final field = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField).last,
    );
    final selectedSurface = field.controller?.text ?? '';
    if (!selectedSurface.startsWith('@') || selectedSurface.trim().isEmpty) {
      fail('Mention candidate did not update the composer.');
    }
    await _enterExactComposerText(
      inputField,
      '$selectedSurface $suffix',
      description: 'mention message input',
    );
    await tapOne(
      find.bySemanticsIdentifier('e2e-chat-send-button'),
      description: 'mention send button',
    );
    await _waitForComposerClear(input, description: 'mention send completion');
    return '$selectedSurface $suffix';
  }

  Future<void> _waitForComposerClear(
    Finder input, {
    required String description,
  }) async {
    final field = find.descendant(
      of: input,
      matching: find.byType(CupertinoTextField),
    );
    await pumpUntil(
      description: description,
      condition: () {
        final elements = field.evaluate().toList(growable: false);
        if (elements.length != 1 ||
            elements.single.widget is! CupertinoTextField) {
          return false;
        }
        final widget = elements.single.widget as CupertinoTextField;
        return widget.controller?.text.isEmpty ?? false;
      },
    );
  }

  Future<void> _enterExactComposerText(
    Finder field,
    String value, {
    required String description,
  }) async {
    for (var attempt = 0; attempt < 3; attempt += 1) {
      await pumpUntilFinder(
        field,
        description: 'enabled $description',
        enabled: true,
      );
      await tester.tap(field);
      await tester.pump();
      await tester.showKeyboard(field);
      tester.testTextInput.enterText(value);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final widget = tester.widget<CupertinoTextField>(field);
      if (widget.controller?.text == value) {
        return;
      }
      await tester.pump(Duration(milliseconds: 150 * (attempt + 1)));
    }
    final widget = tester.widget<CupertinoTextField>(field);
    final observed = widget.controller?.value ?? const TextEditingValue();
    fail(
      'Composer did not retain exact $description after three bounded visible '
      'input attempts; expected_length=${value.length} observed_length='
      '${observed.text.length} selection_collapsed_at_end='
      '${observed.selection.isCollapsed && observed.selection.end == observed.text.length}.',
    );
  }

  Future<void> navigateToContacts() async {
    final macOSTab = find.bySemanticsIdentifier('e2e-contacts-tab');
    final otherTab = find.bySemanticsIdentifier('e2e-friends-tab');
    await pumpUntil(
      description: 'Contacts tab',
      condition: () {
        final macOSCount = macOSTab.evaluate().length;
        final otherCount = otherTab.evaluate().length;
        return (macOSCount == 1 && otherCount == 0) ||
            (macOSCount == 0 && otherCount == 1);
      },
    );
    final variant = requireDesktopPlatformVariant(
      macOSCount: macOSTab.evaluate().length,
      otherCount: otherTab.evaluate().length,
      element: 'Contacts tab',
    );
    await tapOne(
      variant == DesktopPlatformVariant.macOS ? macOSTab : otherTab,
      description: 'Contacts tab',
    );
  }

  Future<void> navigateToMessages() => tapOne(
    find.bySemanticsIdentifier('e2e-messages-tab'),
    description: 'Messages tab',
  );

  Future<void> refreshRelationshipProjection({
    required String peerDid,
    required bool expectedFollowing,
  }) async {
    await container.read(friendsProvider.notifier).refresh();
    final actual = container.read(friendsProvider).isFollowing(peerDid);
    if (actual != expectedFollowing) {
      fail(
        'Refreshed UI relationship projection for the exact peer did not '
        'match expected following=$expectedFollowing.',
      );
    }
  }

  Future<void> expectConversationUnreadBadge({
    required String conversationId,
    required int unreadCount,
  }) async {
    if (unreadCount < 0) {
      fail(
        'Unread badge oracle requires a non-negative count, got $unreadCount.',
      );
    }
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
    if (unreadCount == 0) {
      E2eObservation observeNoBadge() {
        final count = unreadBadge.evaluate().length;
        if (count == 0) {
          return const E2eObservation.pass();
        }
        if (count > 1) {
          return const E2eObservation.fatal(
            'duplicate_conversation_unread_badge',
          );
        }
        return const E2eObservation.pending(
          'conversation_unread_badge_not_cleared',
        );
      }

      await pumpUntilObservation(
        description: 'conversation row unread badge cleared',
        observe: observeNoBadge,
      );
      await assertStableFor(
        description: 'conversation row unread badge remains cleared',
        observe: observeNoBadge,
      );
      return;
    }
    await pumpUntilFinder(
      unreadBadge,
      description: 'conversation row unread badge',
    );
    final l10n = AppLocalizations.of(tester.element(unreadBadge));
    final countLabel = unreadCount > 999 ? '999+' : '$unreadCount';
    final expectedLabel = l10n.conversationsUnreadTag(countLabel);
    final exactLabel = find.descendant(
      of: unreadBadge,
      matching: find.text(expectedLabel),
    );
    await pumpUntilFinder(
      exactLabel,
      description:
          'conversation row exact localized unread badge "$expectedLabel"',
    );
    expect(exactLabel, findsOneWidget);
  }

  String expectedDirectDisplayName(ConversationSummary conversation) {
    if (conversation.isGroup) {
      fail('Direct display-name oracle received a Group conversation.');
    }
    return container.read(
      peerDisplayNameProvider(
        PeerDisplayNameRequest(
          peerPersonaId: conversation.peerPersonaId,
          did: conversation.targetDid,
          nickname: conversation.displayName,
          fullHandle: conversation.targetPeer,
        ),
      ),
    );
  }

  Future<void> expectConversationRowPresentation({
    required String conversationId,
    required String expectedTitle,
    required String expectedPreview,
    required int unreadCount,
  }) async {
    final row = find.byKey(Key('conversation-row:$conversationId'));
    await pumpUntilFinder(
      row,
      description: 'conversation row presentation $conversationId',
      timeout: const Duration(seconds: 90),
    );
    final l10n = AppLocalizations.of(tester.element(row));
    final visiblePreview = expectedPreview.trim().isEmpty
        ? l10n.conversationsNoMessagePreview
        : expectedPreview;
    final unreadLabel = unreadCount <= 0
        ? null
        : l10n.conversationsUnreadTag(
            unreadCount > 999 ? '999+' : '$unreadCount',
          );
    expectExactConversationRowUi(
      conversationId: conversationId,
      expectedTitle: expectedTitle,
      expectedPreview: visiblePreview,
      expectedUnreadLabel: unreadLabel,
    );
  }

  Future<void> expectSelectedConversationHeader(String expectedTitle) async {
    final header = find.byKey(const Key('chat-header-title'));
    E2eObservation observe() => observeExactScopedText(
      widgets: header.evaluate().map((element) => element.widget),
      expectedText: expectedTitle,
      pendingCode: 'chat_header_title_pending',
      exactOneCode: 'chat_header_title_not_exact_one',
      mismatchCode: 'chat_header_title_mismatch',
    );
    await pumpUntilObservation(
      description: 'selected conversation header title',
      observe: observe,
    );
    await assertStableFor(
      description: 'selected conversation header title',
      observe: observe,
    );
  }

  Future<void> expectConversationRowsInOrder(
    List<String> conversationIds,
  ) async {
    for (final conversationId in conversationIds) {
      await pumpUntilFinder(
        find.byKey(Key('conversation-row:$conversationId')),
        description: 'ordered conversation row $conversationId',
        timeout: const Duration(seconds: 90),
      );
    }
    expectVisibleConversationOrder(
      tester: tester,
      conversationIds: conversationIds,
    );
  }

  Future<void> openConversationRow(String conversationId) => tapOne(
    find.byKey(Key('conversation-row:$conversationId')),
    description: 'conversation row $conversationId',
  );

  Future<void> openConversationRowWithFirstVisibleTitle({
    required String conversationId,
    required String expectedTitle,
  }) async {
    await tapOne(
      find.byKey(Key('conversation-row:$conversationId')),
      description: 'conversation row $conversationId',
    );
    final header = find.byKey(const Key('chat-header-title'));
    E2eObservation observe() {
      final selectedId = container.read(selectedConversationProvider);
      final titles = header
          .evaluate()
          .map((element) => element.widget)
          .whereType<Text>()
          .map((widget) => widget.data ?? '');
      return observeFirstVisibleConversationTitle(
        targetSelected: selectedId == conversationId,
        visibleTitles: titles,
        expectedTitle: expectedTitle,
      );
    }

    await pumpUntilObservation(
      description: 'first visible cached conversation title',
      observe: observe,
    );
    await assertStableFor(
      description: 'cached conversation title after open',
      observe: observe,
    );
  }

  Future<ConversationSummary> reopenConversationFromLocalSearch({
    required String query,
    required String conversationId,
    required String expectedTitle,
  }) async {
    await navigateToMessages();
    final search = find.byKey(const Key('conversation-search-field'));
    await pumpUntilFinder(search, description: 'conversation search field');
    final input = find.descendant(
      of: search,
      matching: find.byType(CupertinoTextField),
    );
    await pumpUntilFinder(
      input,
      description: 'conversation search editable field',
      enabled: true,
    );
    await tester.enterText(input, query);
    await tester.pump();
    final row = find.byKey(Key('conversation-row:$conversationId'));
    await pumpUntilFinder(row, description: 'exact searched conversation row');
    expect(
      find.descendant(
        of: row,
        matching: find.text(expectedTitle, findRichText: true),
      ),
      findsOneWidget,
    );
    await tapOne(row, description: 'searched conversation row');
    await pumpUntilFinder(
      find.bySemanticsIdentifier('e2e-chat-input'),
      description: 'chat composer after local conversation search',
    );
    final selected = selectedConversation;
    if (selected.conversationId != conversationId) {
      fail('Local conversation search opened a different canonical row.');
    }
    await tester.enterText(input, '');
    await tester.pump();
    return selected;
  }

  Future<ConversationSummary> openContactConversation(
    String peerDid, {
    String? expectedTitle,
    bool fromFollowers = false,
    bool forceViewAll = false,
  }) async {
    await navigateToContacts();
    await container.read(friendsProvider.notifier).refresh();
    await tester.pump();
    final rowKey = Key('contact-row:${peerDid.trim()}');
    final friendsPage = find.byType(FriendsPage);
    await pumpUntilFinder(friendsPage, description: 'contacts sidebar page');
    var row = find.descendant(of: friendsPage, matching: find.byKey(rowKey));
    final openedViewAll = forceViewAll || row.evaluate().length != 1;
    if (openedViewAll) {
      await tapOne(
        find.byKey(
          fromFollowers
              ? const Key('friends-followers-view-all')
              : const Key('friends-following-view-all'),
        ),
        description: fromFollowers
            ? 'follower contacts view-all action'
            : 'following contacts view-all action',
      );
      final relationshipList = find.byWidgetPredicate(
        (widget) =>
            widget is RelationshipListPage &&
            widget.type ==
                (fromFollowers
                    ? FriendsRelationshipListType.followers
                    : FriendsRelationshipListType.following),
      );
      await pumpUntilFinder(
        relationshipList,
        description: 'relationship list detail pane',
      );
      row = find.descendant(of: relationshipList, matching: find.byKey(rowKey));
    }
    if (expectedTitle != null) {
      final title = find.descendant(
        of: row,
        matching: find.byKey(Key('contact-row-title:${peerDid.trim()}')),
      );
      E2eObservation observeTitle() {
        final rows = row.evaluate().toList(growable: false);
        if (rows.isEmpty) {
          return const E2eObservation.pending('contact_row_pending');
        }
        if (rows.length != 1) {
          return const E2eObservation.fatal('contact_row_not_exact_one');
        }
        return observeExactScopedText(
          widgets: title.evaluate().map((element) => element.widget),
          expectedText: expectedTitle,
          pendingCode: 'contact_title_pending',
          exactOneCode: 'contact_title_not_exact_one',
          mismatchCode: 'contact_first_visible_title_mismatch',
        );
      }

      await pumpUntilObservation(
        description: 'contact row first visible display title',
        timeout: const Duration(seconds: 90),
        observe: observeTitle,
      );
      await assertStableFor(
        description: 'contact row display title',
        observe: observeTitle,
      );
    }
    await tapOne(row, description: 'exact contact row');
    await pumpUntilFinder(
      find.bySemanticsIdentifier('e2e-chat-input'),
      description: 'chat composer after contact-row open',
      timeout: const Duration(seconds: 90),
    );
    final selected = selectedConversation;
    if (selected.isGroup || selected.targetDid?.trim() != peerDid.trim()) {
      fail('Contact row opened the wrong Direct peer: $selected');
    }
    if (!selected.conversationId.startsWith('dm:peer-scope:v1:')) {
      fail('Contact row did not open a canonical peer-scope conversation.');
    }
    return selected;
  }

  Future<void> expectGroupMemberDisplayName({
    required GroupMemberSummary member,
    required String expectedName,
  }) async {
    await tapOne(
      find.byKey(const Key('chat-peer-info-avatar-button')),
      description: 'group info button',
    );
    await pumpUntilFinder(
      find.byKey(const Key('group-info-dialog-did-value')),
      description: 'group info dialog',
    );
    final dialog = find.ancestor(
      of: find.byKey(const Key('group-info-dialog-did-value')),
      matching: find.byType(AppDialogScaffold),
    );
    final title = find.descendant(
      of: dialog,
      matching: find.byKey(
        Key('group-member-title:${groupMemberPresentationKey(member)}'),
      ),
    );
    E2eObservation observeTitle() {
      return observeExactScopedText(
        widgets: title.evaluate().map((element) => element.widget),
        expectedText: expectedName,
        pendingCode: 'group_member_title_pending',
        exactOneCode: 'group_member_title_not_exact_one',
        mismatchCode: 'group_member_first_visible_title_mismatch',
      );
    }

    await pumpUntilObservation(
      description: 'group member first visible display title',
      timeout: const Duration(seconds: 90),
      observe: observeTitle,
    );
    await assertStableFor(
      description: 'group member display title',
      observe: observeTitle,
    );
    await tapOne(
      find.byKey(const Key('peer-info-close-button')),
      description: 'group info close button',
    );
  }

  Future<void> openSelectedPeerInfo() async {
    await tapOne(
      find.byKey(const Key('chat-peer-info-avatar-button')),
      description: 'peer info button',
    );
    await pumpUntilFinder(
      find.byKey(const Key('peer-info-dialog-handle-value')),
      description: 'handle-first peer identity header',
    );
  }

  Future<void> expectSelectedPeerInfoDisplayNameAfterRefresh(
    String expectedName,
  ) async {
    await openSelectedPeerInfo();
    final title = find.byKey(const Key('peer-info-dialog-handle-value'));
    E2eObservation observeRefresh() {
      final elements = title.evaluate().toList(growable: false);
      if (elements.isEmpty) {
        return const E2eObservation.pending('peer_info_title_pending');
      }
      if (elements.length != 1 || elements.single.widget is! Text) {
        return const E2eObservation.fatal('peer_info_title_not_exact_one');
      }
      final actual = (elements.single.widget as Text).data?.trim() ?? '';
      if (actual != expectedName.trim()) {
        return const E2eObservation.pending(
          'peer_info_profile_refresh_pending',
        );
      }
      return const E2eObservation.pass();
    }

    await pumpUntilObservation(
      description: 'peer info explicit profile refresh',
      timeout: const Duration(seconds: 90),
      observe: observeRefresh,
    );
    await assertStableFor(
      description: 'peer info refreshed display name',
      observe: () => observeExactScopedText(
        widgets: title.evaluate().map((element) => element.widget),
        expectedText: expectedName,
        pendingCode: 'peer_info_title_pending',
        exactOneCode: 'peer_info_title_not_exact_one',
        mismatchCode: 'peer_info_refreshed_name_reverted',
      ),
    );
  }

  Future<void> followSelectedPeer() async {
    await openSelectedPeerInfo();
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
    final groupDid = selected.groupId!.trim();
    await pumpUntil(
      description: 'canonical group conversation projection',
      timeout: const Duration(seconds: 90),
      condition: () {
        final current = selectedConversation;
        return current.isGroup &&
            current.groupId?.trim() == groupDid &&
            current.threadId.trim() == 'group:$groupDid' &&
            current.conversationId == 'group:$groupDid';
      },
    );
    return selectedConversation;
  }

  Future<void> addGroupMember(
    String handle, {
    required String expectedDisplayName,
  }) async {
    final preflight = await container
        .read(directoryApplicationServiceProvider)
        .resolvePeer(handle);
    if (preflight.did.trim().isEmpty) {
      fail('Read-only group member preflight returned no DID.');
    }
    final expectedHandles = <String>{
      normalizeDidOrHandleInput(handle).toLowerCase(),
      if (preflight.handle?.trim().isNotEmpty ?? false)
        normalizeDidOrHandleInput(preflight.handle!).toLowerCase(),
    };
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
    final search = find.byKey(const Key('identity-lookup-search-button'));
    final addMember = find.byKey(const Key('identity-add-group-member-button'));
    final dialog = find.ancestor(
      of: addMember,
      matching: find.byType(AppDialogScaffold),
    );
    final candidateLabel = find.byWidgetPredicate((widget) {
      if (widget is! Text || widget.data == null) {
        return false;
      }
      return expectedHandles.contains(
        normalizeDidOrHandleInput(widget.data!).toLowerCase(),
      );
    });
    final candidateTile = find.descendant(
      of: dialog,
      matching: find.byType(AppPressableTile),
    );
    final exactCandidateLabel = find.descendant(
      of: candidateTile,
      matching: candidateLabel,
    );
    Object? lastResolutionError;
    for (var attempt = 0; attempt < 3; attempt += 1) {
      await pumpUntilFinder(
        search,
        description: 'group member search action',
        enabled: true,
      );
      await tapOne(search, description: 'group member search action');
      try {
        await pumpUntilFinder(
          candidateTile,
          description: 'exact resolved group member candidate',
          enabled: true,
          timeout: const Duration(seconds: 20),
        );
        if (exactCandidateLabel.evaluate().isEmpty) {
          fail(
            'Resolved group member candidate did not render an exact handle.',
          );
        }
        lastResolutionError = null;
        break;
      } on Object catch (error) {
        lastResolutionError = error;
        if (attempt < 2) {
          await pumpUntilFinder(
            search,
            description: 'group member search retry action',
            enabled: true,
          );
        }
      }
    }
    if (lastResolutionError != null) {
      String resolverDiagnostic;
      try {
        await container
            .read(directoryApplicationServiceProvider)
            .resolvePeer(handle);
        resolverDiagnostic = 'application_resolver_succeeded';
      } on Object catch (error) {
        resolverDiagnostic = error is core.AwikiImCoreException
            ? error.code
            : error.runtimeType.toString();
      }
      final actionElements = addMember.evaluate().toList(growable: false);
      final actionEnabled = actionElements.length == 1
          ? actionElements.single.widget is AppPrimaryButton &&
                (actionElements.single.widget as AppPrimaryButton).onPressed !=
                    null
          : false;
      final input = tester.widget<CupertinoTextField>(
        find.byType(CupertinoTextField).last,
      );
      final candidateCount = candidateTile.evaluate().length;
      fail(
        'Group member resolution did not expose one exact enabled candidate '
        'after three bounded visible search attempts; resolver='
        '$resolverDiagnostic action_count=${actionElements.length} '
        'action_enabled=$actionEnabled input_exact='
        '${input.controller?.text == handle} candidate_count=$candidateCount.',
      );
    }
    _expectIdentityCandidatePresentation(
      candidate: candidateTile,
      expectedDisplayName: expectedDisplayName,
      expectedAvatarUri: container
          .read(peerDisplayProfileProvider)
          .forDid(preflight.did)
          ?.avatarUri,
    );
    await tapOne(candidateTile, description: 'exact resolved group member');
    await pumpUntilFinder(
      addMember,
      description: 'selected add-member action',
      enabled: true,
    );
    await tapOne(addMember, description: 'add resolved group member');
    await pumpUntil(
      description: 'group member dialog closes',
      condition: () {
        if (find
            .byKey(const Key('identity-add-group-member-button'))
            .evaluate()
            .isEmpty) {
          return true;
        }
        final notices = find
            .byType(AwikiMeErrorNotice)
            .evaluate()
            .toList(growable: false);
        if (notices.isNotEmpty) {
          final notice = notices.last.widget as AwikiMeErrorNotice;
          final code = RegExp(
            r'AwikiImCoreException\(([^)]+)\)',
          ).firstMatch(notice.message)?.group(1);
          fail(
            'Group member submission failed before the dialog closed; '
            'error_code=${code ?? 'unclassified'}.',
          );
        }
        return false;
      },
    );
  }

  void _expectIdentityCandidatePresentation({
    required Finder candidate,
    required String expectedDisplayName,
    required String? expectedAvatarUri,
    String? expectedSurface,
  }) {
    final expectedTitle = expectedSurface ?? expectedDisplayName;
    final titleCount = find
        .descendant(of: candidate, matching: find.text(expectedTitle))
        .evaluate()
        .length;
    final avatars = find
        .descendant(of: candidate, matching: find.byType(AvatarBadge))
        .evaluate()
        .toList(growable: false);
    if (titleCount != 1 || avatars.length != 1) {
      fail(
        'Identity candidate did not expose one exact projected title/avatar; '
        'title_count=$titleCount avatar_count=${avatars.length}.',
      );
    }
    final avatar = avatars.single.widget as AvatarBadge;
    final expectedAvatar = expectedAvatarUri?.trim() ?? '';
    final actualAvatar = avatar.avatarUri?.trim() ?? '';
    if (avatar.seed != expectedDisplayName || actualAvatar != expectedAvatar) {
      fail(
        'Identity candidate name/avatar projection diverged from the canonical '
        'peer display projection; exact_seed='
        '${avatar.seed == expectedDisplayName} exact_avatar='
        '${actualAvatar == expectedAvatar}.',
      );
    }
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
    final sourceDirectory = await Directory.systemTemp.createTemp(
      'awiki-e2e-drop-',
    );
    final source = File('${sourceDirectory.path}/$filename');
    await source.writeAsBytes(bytes, flush: true);
    try {
      if (Platform.isMacOS) {
        await _sendDesktopDropMethod(
          'performOperation_macos',
          <Map<String, Object?>>[
            <String, Object?>{
              'path': source.path,
              'isDirectory': false,
              'fromPromise': false,
            },
          ],
        );
      } else {
        await _sendDesktopDropMethod('performOperation', <String>[source.path]);
      }
      await pumpUntilFinder(
        find.byKey(const Key('chat-pending-attachment-preview')),
        description: 'pending attachment preview',
      );
    } finally {
      if (await sourceDirectory.exists()) {
        await sourceDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> expectPendingAttachmentFilename(String expectedFilename) async {
    final preview = find.byKey(const Key('chat-pending-attachment-preview'));
    await pumpUntilFinder(preview, description: 'pending attachment preview');
    final draft = container
        .read(chatComposerDraftsProvider.notifier)
        .draftFor(selectedConversation)
        .pendingAttachment;
    if (draft == null || draft.filename != expectedFilename) {
      fail(
        'Pending attachment model did not preserve the exact dropped '
        'filename; draft_present=${draft != null} exact_filename='
        '${draft?.filename == expectedFilename}.',
      );
    }
    await pumpUntilFinder(
      find.descendant(of: preview, matching: find.text(expectedFilename)),
      description: 'exact pending attachment filename',
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
    // Desktop integration tests use the legal foreground -> hidden ->
    // foreground path. Entering `paused` suspends the test binding's frame
    // scheduler and cannot be used as a synthetic reconnect boundary.
    for (final state in const <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    await pumpUntilFinder(
      find.bySemanticsIdentifier('e2e-authenticated'),
      description: 'App shell after lifecycle reconnect',
    );
  }

  Future<void> enterHiddenLifecycle() async {
    for (final state in const <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
  }

  Future<void> resumeFromHiddenLifecycle() async {
    for (final state in const <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    await pumpUntilFinder(
      find.bySemanticsIdentifier('e2e-authenticated'),
      description: 'App shell after hidden burst resume',
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
    final elements = finder.evaluate().toList(growable: false);
    if (elements.length != 1) {
      fail(
        'Expected exactly one $description before tap, found '
        '${elements.length}.',
      );
    }
    await tester.ensureVisible(finder);
    final widget = elements.single.widget;
    final pressableDescendant = find.descendant(
      of: finder,
      matching: find.byType(AppPressable),
    );
    final pressableCount = pressableDescendant.evaluate().length;
    final requiresPressableDescendant =
        widget is AppPrimaryButton ||
        widget is AppSecondaryButton ||
        widget is AppIconButton ||
        widget is AppPressableTile;
    if (requiresPressableDescendant && pressableCount != 1) {
      fail(
        'Expected exactly one interactive target for $description, found '
        '$pressableCount.',
      );
    }
    final tapTarget = pressableCount == 1 ? pressableDescendant : finder;
    await tester.tap(tapTarget);
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
          if (widget is AppSecondaryButton && widget.onPressed == null) {
            return false;
          }
          if (widget is AppPressableTile && widget.onTap == null) {
            return false;
          }
          if (widget is CupertinoTextField && widget.enabled == false) {
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

  Future<void> pumpUntilObservation({
    required String description,
    required E2eObservation Function() observe,
    Duration timeout = const Duration(seconds: 45),
    String failureLayer = 'visible_ui',
  }) async {
    final deadline = DateTime.now().add(timeout);
    String? lastPendingCode;
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      final observation = observe();
      switch (observation.status) {
        case E2eObservationStatus.pass:
          return;
        case E2eObservationStatus.pending:
          lastPendingCode = observation.code;
          continue;
        case E2eObservationStatus.fatal:
          await E2eFailureObservationWriter.recordFirst(
            layer: failureLayer,
            status: 'fatal',
            code: observation.code ?? 'unspecified_invariant',
            caseId: failureCaseId,
          );
          fail(
            'Fatal invariant while waiting for $description: '
            '${observation.code ?? 'unspecified_invariant'}.',
          );
      }
    }
    await E2eFailureObservationWriter.recordFirst(
      layer: failureLayer,
      status: 'timeout',
      code: lastPendingCode ?? 'observation_timeout',
      caseId: failureCaseId,
    );
    fail(
      'Timed out waiting for $description.'
      '${lastPendingCode == null ? '' : ' Last pending: $lastPendingCode.'}',
    );
  }

  Future<void> assertStableFor({
    required String description,
    required E2eObservation Function() observe,
    Duration duration = const Duration(seconds: 2),
    String failureLayer = 'visible_ui',
  }) async {
    final deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      final observation = observe();
      if (observation.status != E2eObservationStatus.pass) {
        await E2eFailureObservationWriter.recordFirst(
          layer: failureLayer,
          status: 'unstable',
          code: observation.code ?? 'unspecified_instability',
          caseId: failureCaseId,
        );
        fail(
          '$description became unstable: '
          '${observation.code ?? observation.status.name}.',
        );
      }
    }
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
  int delegatedConversationTextAttempts = 0;
  bool conversationTextAttemptPending = false;
  String? lastConversationTextFailureCode;
  String? lastConversationTextFailureDetail;
  final Map<String, List<_PatchSink>> _patchSinks =
      <String, List<_PatchSink>>{};
  final Map<String, int> _patchVersions = <String, int>{};
  final Map<String, Map<String, ChatMessage>> _injectedFailedMessages =
      <String, Map<String, ChatMessage>>{};

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
      final presentationConversationId = _presentationConversationIdForSend(
        conversation.conversationId,
      );
      final target = _threadTarget(conversation.conversationId);
      final failed = ChatMessage(
        localId: localId,
        conversationId: presentationConversationId,
        threadId: presentationConversationId,
        senderDid: ownerDid,
        receiverDid: target.kind == 'direct' ? target.id : null,
        groupId: target.kind == 'group' ? target.id : null,
        content: content,
        createdAt: DateTime.now(),
        isMine: true,
        sendState: MessageSendState.failed,
      );
      _injectedFailedMessages.putIfAbsent(
        presentationConversationId,
        () => <String, ChatMessage>{},
      )[localId] = failed;
      final version = _nextPatchVersion(presentationConversationId);
      for (final sink
          in _patchSinks[presentationConversationId] ?? const <_PatchSink>[]) {
        sink.emit(
          ThreadMessagePatch(
            kind: ThreadMessagePatchKind.upsert,
            ownerDid: ownerDid,
            version: version,
            threadKind: 'conversation',
            threadId: presentationConversationId,
            conversationId: presentationConversationId,
            message: failed,
          ),
        );
      }
      throw StateError('controlled_e2e_transport_failure');
    }
    delegatedConversationTextAttempts += 1;
    conversationTextAttemptPending = true;
    lastConversationTextFailureCode = null;
    lastConversationTextFailureDetail = null;
    try {
      final sent = await _delegate.sendConversationText(
        conversation: conversation,
        content: content,
        clientMessageId: clientMessageId,
        idempotencyKey: idempotencyKey,
      );
      _removeInjectedFailedMessage(
        _presentationConversationIdForSend(conversation.conversationId),
        clientMessageId,
      );
      return sent;
    } on Object catch (error) {
      lastConversationTextFailureCode = error is core.AwikiImCoreException
          ? error.code
          : error.runtimeType.toString();
      lastConversationTextFailureDetail = error.toString();
      rethrow;
    } finally {
      conversationTextAttemptPending = false;
    }
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
                  _retainInjectedFailures(conversation.conversationId, patch),
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
  }) async => _mergeInjectedFailures(
    conversation.conversationId,
    await _timelineDelegate.loadConversationTimeline(
      conversation,
      limit: limit,
      cursor: cursor,
      includeControlPayloads: includeControlPayloads,
    ),
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
      _retainInjectedFailures(conversation.conversationId, patch),
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

  ThreadMessagePatch _retainInjectedFailures(
    String conversationId,
    ThreadMessagePatch patch,
  ) {
    final message = patch.message;
    if (message != null && message.sendState == MessageSendState.sent) {
      _removeInjectedFailedMessage(conversationId, message.localId);
      _removeInjectedFailedMessage(conversationId, message.remoteId);
    }
    if (patch.kind != ThreadMessagePatchKind.reset) {
      return patch;
    }
    return ThreadMessagePatch(
      kind: patch.kind,
      ownerDid: patch.ownerDid,
      version: patch.version,
      threadKind: patch.threadKind,
      threadId: patch.threadId,
      conversationId: patch.conversationId,
      messages: _mergeInjectedFailures(conversationId, patch.messages),
      message: patch.message,
      index: patch.index,
      messageId: patch.messageId,
      reason: patch.reason,
    );
  }

  List<ChatMessage> _mergeInjectedFailures(
    String conversationId,
    List<ChatMessage> messages,
  ) {
    final injected = _injectedFailedMessages[conversationId];
    if (injected == null || injected.isEmpty) {
      return messages;
    }
    final merged = <ChatMessage>[...messages];
    for (final failed in injected.values) {
      final alreadyPresent = merged.any(
        (message) =>
            message.localId == failed.localId ||
            message.remoteId == failed.localId,
      );
      if (!alreadyPresent) {
        merged.add(failed);
      }
    }
    return merged;
  }

  void _removeInjectedFailedMessage(String conversationId, String? messageId) {
    final normalized = messageId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    final injected = _injectedFailedMessages[conversationId];
    injected?.remove(normalized);
    if (injected != null && injected.isEmpty) {
      _injectedFailedMessages.remove(conversationId);
    }
  }

  String _presentationConversationIdForSend(String writeConversationId) {
    final normalized = writeConversationId.trim();
    if (_patchSinks.containsKey(normalized)) {
      return normalized;
    }
    final activeConversationIds = _patchSinks.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => entry.key)
        .toSet();
    if (activeConversationIds.length != 1) {
      throw StateError(
        'Controlled E2E failure requires exactly one active canonical '
        'conversation timeline, found ${activeConversationIds.length}.',
      );
    }
    return activeConversationIds.single;
  }

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
