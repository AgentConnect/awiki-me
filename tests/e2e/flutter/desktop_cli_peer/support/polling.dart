part of '../desktop_cli_peer_e2e.dart';

Future<void> _waitForGroupMessages({
  required GroupApplicationService groups,
  required String groupDid,
  required String expectedText,
  String? expectedMessageId,
}) async {
  await _pollObservation(
    description: 'App group messages contain exact message "$expectedText"',
    observe: () async {
      final messages = await groups.listMessages(groupDid, limit: 20);
      return _observeExactRemoteMessage(
        messages: messages,
        expectedText: expectedText,
        expectedMessageId: expectedMessageId,
      );
    },
  );
}

Future<void> _waitForAppHistory({
  required MessagingService messaging,
  required AppThreadRef thread,
  required String expectedText,
  String? expectedMessageId,
}) async {
  await _pollObservation(
    description: 'App history contains exact message "$expectedText"',
    observe: () async {
      final messages = await messaging.loadHistory(thread, limit: 20);
      return _observeExactRemoteMessage(
        messages: messages,
        expectedText: expectedText,
        expectedMessageId: expectedMessageId,
      );
    },
  );
}

Future<void> _expectAppHistoryContainsExactlyOnce({
  required MessagingService messaging,
  required AppThreadRef thread,
  required List<ExactMessageExpectation> expected,
}) async {
  final runOwnedContents = expected.map((item) => item.content).toSet();
  // MessagingService.loadHistory preserves the SDK page contract: newest
  // first. Product UI timelines normalize that page into oldest-first order,
  // so the two surfaces intentionally use opposite exact sequences.
  final expectedNewestFirst = expected.reversed.toList(growable: false);
  E2eObservation observe(List<ChatMessage> messages) {
    final runOwned = messages
        .where((message) => runOwnedContents.contains(message.content))
        .toList(growable: false);
    if (runOwned.length < expected.length) {
      return const E2eObservation.pending('app_history_messages_pending');
    }
    if (runOwned.length > expected.length) {
      return const E2eObservation.fatal('app_history_extra_message');
    }
    return observeExactMessageSequence(
      messages: runOwned,
      expected: expectedNewestFirst,
      isRunOwned: (_) => true,
    );
  }

  await _pollObservation(
    description: 'App history exact run-owned sequence',
    observe: () async {
      final messages = await messaging.loadHistory(thread, limit: 50);
      return observe(messages);
    },
  );
  await Future<void>.delayed(const Duration(seconds: 2));
  final second = await messaging.loadHistory(thread, limit: 50);
  final stable = observe(second);
  if (stable.status != E2eObservationStatus.pass) {
    fail(
      'App history exact sequence became unstable: '
      '${stable.code ?? stable.status.name}.',
    );
  }
}

Future<ConversationSummary> _waitForAppConversationRefresh({
  required ConversationService conversations,
  required String ownerDid,
  required String expectedText,
  required String expectedConversationId,
}) async {
  ConversationSummary? matched;
  await _pollObservation(
    description: 'App conversation refresh contains "$expectedText"',
    observe: () async {
      final items = await conversations.listConversations(
        ownerDid: ownerDid,
        limit: 20,
      );
      final exact = items
          .where(
            (conversation) =>
                conversation.conversationId == expectedConversationId,
          )
          .toList(growable: false);
      if (exact.isEmpty) {
        return const E2eObservation.pending(
          'app_conversation_projection_pending',
        );
      }
      if (exact.length != 1) {
        return const E2eObservation.fatal(
          'duplicate_app_conversation_projection',
        );
      }
      if (exact.single.lastMessagePreview != expectedText) {
        return const E2eObservation.pending('app_conversation_preview_pending');
      }
      matched = exact.single;
      return const E2eObservation.pass();
    },
  );
  return matched!;
}

Future<void> _waitForAppConversationLatestInTimeline({
  required MessagingService messaging,
  required ConversationSummary conversation,
  required String expectedText,
  String? expectedMessageId,
}) async {
  expect(
    messaging,
    isA<ConversationTimelineMessagingService>(),
    reason:
        'Desktop CLI peer E2E must verify list/detail consistency through '
        'the canonical conversation timeline.',
  );
  final timelineMessaging = messaging as ConversationTimelineMessagingService;
  final conversationId = conversation.conversationId;
  final latestSnapshot = conversation.lastMessageSnapshot;

  await _pollObservation(
    description:
        'App conversation "$conversationId" latest message exists in canonical timeline',
    observe: () async {
      final messages = await timelineMessaging.loadConversationTimeline(
        AppConversationReadRef.fromConversationId(conversationId),
        limit: 50,
      );
      return observeConversationLatestInTimeline(
        messages: messages,
        latestSnapshot: latestSnapshot,
        conversationId: conversationId,
        expectedText: expectedText,
        expectedMessageId: expectedMessageId,
      );
    },
  );
}

E2eObservation _observeExactRemoteMessage({
  required Iterable<ChatMessage> messages,
  required String expectedText,
  String? expectedMessageId,
}) {
  final bodyMatches = messages
      .where((message) => message.content == expectedText)
      .toList(growable: false);
  if (bodyMatches.isEmpty) {
    return const E2eObservation.pending('remote_message_pending');
  }
  if (bodyMatches.length != 1) {
    return const E2eObservation.fatal('duplicate_remote_message');
  }
  final canonicalId = bodyMatches.single.remoteId ?? bodyMatches.single.localId;
  if (expectedMessageId != null && canonicalId != expectedMessageId) {
    return const E2eObservation.fatal('remote_message_id_mismatch');
  }
  return const E2eObservation.pass();
}

Future<void> _pollObservation({
  required String description,
  required Future<E2eObservation> Function() observe,
  String? failureLayer,
  Duration timeout = const Duration(seconds: 90),
  Duration interval = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  String? lastPendingCode;
  while (DateTime.now().isBefore(deadline)) {
    try {
      final observation = await observe();
      if (observation.status == E2eObservationStatus.pass) {
        return;
      }
      if (observation.status == E2eObservationStatus.fatal) {
        if (failureLayer != null) {
          await E2eFailureObservationWriter.recordFirst(
            layer: failureLayer,
            status: 'fatal',
            code: observation.code ?? 'unspecified_invariant',
          );
        }
        fail(
          'Fatal invariant while waiting for $description: '
          '${observation.code ?? 'unspecified_invariant'}.',
        );
      }
      lastPendingCode = observation.code;
    } on TestFailure {
      rethrow;
    } on Object catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(interval);
  }
  final errorSuffix = lastError == null
      ? ''
      : ' Last error: ${_sanitizeDiagnostic(lastError.toString())}';
  final pendingSuffix = lastPendingCode == null
      ? ''
      : ' Last pending: $lastPendingCode.';
  if (failureLayer != null) {
    await E2eFailureObservationWriter.recordFirst(
      layer: failureLayer,
      status: 'timeout',
      code: lastPendingCode ?? 'observation_timeout',
    );
  }
  fail('Timed out waiting for $description.$pendingSuffix$errorSuffix');
}

Future<void> _poll({
  required String description,
  required Future<bool> Function() action,
  Duration timeout = const Duration(seconds: 90),
  Duration interval = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await action()) {
        return;
      }
    } on Object catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(interval);
  }
  final suffix = lastError == null
      ? ''
      : ' Last error: ${_sanitizeDiagnostic(lastError.toString())}';
  fail('Timed out waiting for $description.$suffix');
}

extension on ChatMessage {
  bool _matchesText(String expectedText, {String? expectedMessageId}) {
    if (content != expectedText) {
      return false;
    }
    final id = remoteId ?? localId;
    return expectedMessageId == null || id == expectedMessageId;
  }
}
