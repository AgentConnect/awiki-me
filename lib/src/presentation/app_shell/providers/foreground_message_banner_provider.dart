import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/tenant/app_tenant.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/conversation_summary.dart';

@immutable
class ForegroundMessageBannerContent {
  const ForegroundMessageBannerContent({
    required this.conversationTitle,
    required this.senderLabel,
    required this.preview,
    required this.isGroup,
    required this.avatarSeed,
    this.avatarUri,
  });

  final String conversationTitle;
  final String senderLabel;
  final String preview;
  final bool isGroup;
  final String avatarSeed;
  final String? avatarUri;
}

@immutable
class ForegroundMessageBannerEvent {
  const ForegroundMessageBannerEvent({
    required this.sequence,
    required this.storageScopeId,
    required this.ownerDid,
    required this.sessionGeneration,
    required this.conversationId,
    required this.content,
    required this.receivedAt,
  });

  final int sequence;
  final StorageScopeId storageScopeId;
  final String ownerDid;
  final int sessionGeneration;
  final String conversationId;
  final ForegroundMessageBannerContent content;
  final DateTime receivedAt;
}

ForegroundMessageBannerContent resolveForegroundMessageBannerContent({
  required ChatMessage message,
  required ConversationSummary? conversation,
  required String senderLabel,
  required String preview,
  required String groupFallbackTitle,
}) {
  final normalizedSender = _singleLine(senderLabel);
  final normalizedPreview = _singleLine(preview);
  final isGroup =
      conversation?.isGroup == true ||
      (message.groupId?.trim().isNotEmpty ?? false);
  final candidateTitle = _singleLine(conversation?.displayName ?? '');
  final conversationTitle = isGroup
      ? (_isSafeGroupTitle(candidateTitle, conversation, message)
            ? candidateTitle
            : _singleLine(groupFallbackTitle))
      : (_isSafeDirectTitle(candidateTitle)
            ? candidateTitle
            : normalizedSender);
  final avatarSeed = _singleLine(conversation?.avatarSeed ?? '');

  return ForegroundMessageBannerContent(
    conversationTitle: conversationTitle,
    senderLabel: normalizedSender,
    preview: normalizedPreview,
    isGroup: isGroup,
    avatarSeed: avatarSeed.isNotEmpty ? avatarSeed : conversationTitle,
    avatarUri: conversation?.avatarUri,
  );
}

bool isOrdinaryMessagePresentationEligible(ChatMessage message) {
  if (!message.hasRenderableContent ||
      message.isMine ||
      message.isGroupSystemEvent ||
      message.isAgentControlPayload) {
    return false;
  }
  final type = message.originalType.trim().toLowerCase();
  if (message.isEncrypted && type.contains('e2ee')) {
    return false;
  }
  return true;
}

class ForegroundMessageBannerController
    extends StateNotifier<ForegroundMessageBannerEvent?> {
  ForegroundMessageBannerController() : super(null);

  int _sequence = 0;

  void show({
    required StorageScopeId storageScopeId,
    required String ownerDid,
    required int sessionGeneration,
    required String conversationId,
    required ForegroundMessageBannerContent content,
    DateTime? receivedAt,
  }) {
    final normalizedConversationId = conversationId.trim();
    if (normalizedConversationId.isEmpty ||
        content.conversationTitle.isEmpty ||
        content.preview.isEmpty) {
      return;
    }
    _sequence += 1;
    state = ForegroundMessageBannerEvent(
      sequence: _sequence,
      storageScopeId: storageScopeId,
      ownerDid: ownerDid,
      sessionGeneration: sessionGeneration,
      conversationId: normalizedConversationId,
      content: content,
      receivedAt: receivedAt ?? DateTime.now(),
    );
  }

  void dismiss({int? sequence}) {
    if (sequence != null && state?.sequence != sequence) {
      return;
    }
    state = null;
  }
}

final foregroundMessageBannerProvider =
    StateNotifierProvider<
      ForegroundMessageBannerController,
      ForegroundMessageBannerEvent?
    >((ref) => ForegroundMessageBannerController());

String _singleLine(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

bool _isSafeDirectTitle(String title) =>
    title.isNotEmpty && !title.toLowerCase().startsWith('did:');

bool _isSafeGroupTitle(
  String title,
  ConversationSummary? conversation,
  ChatMessage message,
) {
  if (title.isEmpty) {
    return false;
  }
  final normalized = title.toLowerCase();
  if (normalized.startsWith('did:') ||
      normalized.startsWith('group:') ||
      normalized.contains(':group:')) {
    return false;
  }
  final opaqueIdentifiers = <String?>[
    conversation?.canonicalGroupDid,
    conversation?.groupId,
    message.groupId,
  ];
  return !opaqueIdentifiers.any(
    (identifier) =>
        identifier?.trim().isNotEmpty == true &&
        identifier!.trim().toLowerCase() == normalized,
  );
}
