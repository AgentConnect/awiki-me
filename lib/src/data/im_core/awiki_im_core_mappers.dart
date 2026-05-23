import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/app_session.dart';
import '../../application/models/app_thread_ref.dart';
import '../../application/models/product_local_models.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/realtime_update.dart';
import '../../domain/entities/relationship_summary.dart';
import '../../domain/entities/session_identity.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/services/realtime_gateway.dart';

class AwikiImCoreMappers {
  const AwikiImCoreMappers();

  AppSession appSessionFromIdentity(
    core.IdentitySummary identity, {
    bool authenticated = false,
    DateTime? expiresAt,
  }) {
    return AppSession(
      did: identity.did,
      identityId: identity.id,
      displayName:
          _nonEmpty(identity.displayName) ??
          _nonEmpty(identity.handle) ??
          _nonEmpty(identity.localAlias) ??
          _compactDid(identity.did),
      handle: _nonEmpty(identity.handle),
      localAlias: _nonEmpty(identity.localAlias),
      authenticated: authenticated,
      expiresAt: expiresAt,
    );
  }

  SessionIdentity legacySessionFromAppSession(AppSession session) {
    return SessionIdentity(
      did: session.did,
      credentialName: session.localAlias ?? session.identityId,
      displayName: session.displayName,
      handle: session.handle,
      jwtToken: null,
    );
  }

  core.ThreadRef threadRefToCore(AppThreadRef thread) {
    return switch (thread) {
      AppDirectThreadRef(:final peerDidOrHandle) => core.ThreadRef.direct(
        peerDidOrHandle,
      ),
      AppGroupThreadRef(:final groupDid) => core.ThreadRef.group(groupDid),
      AppMessageThreadRef(:final threadId) => core.ThreadRef.thread(threadId),
    };
  }

  core.MessageTarget messageTargetToCore(AppThreadRef thread) {
    return switch (thread) {
      AppDirectThreadRef(:final peerDidOrHandle) => core.MessageTarget.direct(
        peerDidOrHandle,
      ),
      AppGroupThreadRef(:final groupDid) => core.MessageTarget.group(groupDid),
      AppMessageThreadRef(:final threadId) => throw UnsupportedError(
        'Cannot send directly to thread id $threadId',
      ),
    };
  }

  ChatMessage chatMessageFromCore(
    core.Message message, {
    required String ownerDid,
  }) {
    final isMine =
        message.direction == core.MessageDirection.outgoing ||
        message.sender == ownerDid;
    return ChatMessage(
      localId: message.id,
      remoteId: message.id,
      threadId: message.threadId,
      senderDid: message.sender,
      senderName:
          _attribute(message.metadata, 'senderName') ??
          _attribute(message.metadata, 'sender_name'),
      receiverDid: _nonEmpty(message.receiver),
      groupId: _nonEmpty(message.group),
      content: message.body.text ?? '',
      originalType: message.body.kind ?? message.metadata.contentType ?? 'text',
      createdAt: _parseDateTime(message.sentAt ?? message.receivedAt),
      isMine: isMine,
      sendState: _sendStateFromCore(message.metadata, isMine: isMine),
      serverSequence: message.metadata.serverSequence,
      isEncrypted: _isEncrypted(message.metadata.contentType),
    );
  }

  ConversationSummary conversationFromCore(
    core.Conversation conversation, {
    ProductConversationOverlay? overlay,
  }) {
    final isGroup =
        conversation.threadKind == 'group' ||
        conversation.threadId.startsWith('group:');
    final lastMessage = conversation.lastMessage;
    final targetDid = isGroup
        ? null
        : _firstNonEmpty(conversation.participants);
    final groupId = isGroup
        ? lastMessage?.group ?? _stripPrefix(conversation.threadId, 'group:')
        : null;
    return ConversationSummary(
      threadId: conversation.threadId,
      displayName:
          overlay?.customTitle ??
          _nonEmpty(conversation.title) ??
          groupId ??
          targetDid ??
          conversation.threadId,
      lastMessagePreview: lastMessage == null
          ? ''
          : _messagePreview(lastMessage),
      lastMessageAt: _parseDateTime(
        conversation.lastMessageAt ??
            lastMessage?.sentAt ??
            lastMessage?.receivedAt,
      ),
      unreadCount: conversation.unreadCount,
      isGroup: isGroup,
      targetDid: targetDid,
      groupId: groupId,
      avatarSeed: overlay?.avatarSeed,
    );
  }

  GroupSummary groupFromCoreSummary(core.GroupSummary group) {
    return GroupSummary(
      groupId: group.did,
      name: _nonEmpty(group.name) ?? group.did,
      description: '',
      memberCount: group.memberCount ?? 0,
      lastMessageAt: _tryParseDateTime(group.lastMessageAt),
      myRole: group.membershipStatus,
    );
  }

  GroupSummary groupFromCoreSnapshot(core.GroupSnapshot group) {
    return GroupSummary(
      groupId: group.did,
      name: _nonEmpty(group.name) ?? group.did,
      description: group.description ?? '',
      memberCount: group.memberCount ?? 0,
      lastMessageAt: _tryParseDateTime(group.lastMessageAt),
      myRole: group.myRole ?? group.membershipStatus,
    );
  }

  GroupMemberSummary groupMemberFromCore(core.GroupMember member) {
    final did = member.did ?? '';
    return GroupMemberSummary(
      userId: did,
      did: did,
      handle: member.handle ?? did,
      role: member.role ?? 'member',
    );
  }

  UserProfile userProfileFromCore(core.UserProfile profile) {
    return UserProfile(
      did: profile.subject,
      nickName: profile.displayName ?? _compactDid(profile.subject),
      bio: profile.bio ?? '',
      tags: profile.tags,
      profileMarkdown: profile.markdown ?? '',
      handle: profile.handle,
    );
  }

  core.ProfilePatch profilePatchToCore(ProfilePatch patch) {
    return core.ProfilePatch(
      displayName: patch.nickName,
      bio: patch.bio,
      tags: patch.tags,
      markdown: patch.profileMarkdown,
    );
  }

  RelationshipSummary relationshipFromCore(core.RelationStatus status) {
    return RelationshipSummary(
      did: status.peer,
      displayName: status.displayName ?? _compactDid(status.peer),
      relationship: status.relationship ?? 'none',
    );
  }

  RealtimeUpdate? realtimeUpdateFromCore(
    core.RealtimeEvent event, {
    required String ownerDid,
  }) {
    final message = event.message;
    if (message == null) {
      return null;
    }
    final chatMessage = chatMessageFromCore(message, ownerDid: ownerDid);
    final conversation = ConversationSummary(
      threadId: message.threadId,
      displayName: message.group ?? message.receiver ?? message.sender,
      lastMessagePreview: _messagePreview(message),
      lastMessageAt: chatMessage.createdAt,
      unreadCount: chatMessage.isMine ? 0 : 1,
      isGroup: message.threadKind == 'group',
      targetDid: message.threadKind == 'group' ? null : message.sender,
      groupId: message.group,
    );
    return RealtimeUpdate(
      message: chatMessage,
      conversation: conversation,
      group: message.group == null
          ? null
          : GroupSummary(
              groupId: message.group!,
              name: message.group!,
              description: '',
              memberCount: 0,
              lastMessageAt: chatMessage.createdAt,
            ),
    );
  }

  RealtimeConnectionStatus connectionStatusFromCore(
    core.RealtimeConnectionState state,
  ) {
    return _connectionStatusFromString(state.state);
  }
}

DateTime _parseDateTime(String? raw) {
  return _tryParseDateTime(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _tryParseDateTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

String? _firstNonEmpty(Iterable<String> values) {
  for (final value in values) {
    final trimmed = _nonEmpty(value);
    if (trimmed != null) {
      return trimmed;
    }
  }
  return null;
}

String _stripPrefix(String value, String prefix) {
  return value.startsWith(prefix) ? value.substring(prefix.length) : value;
}

String _compactDid(String did) {
  if (did.length <= 18) {
    return did;
  }
  return '${did.substring(0, 10)}…${did.substring(did.length - 6)}';
}

String _messagePreview(core.Message message) {
  return message.body.text ??
      message.body.unsupportedContentType ??
      message.metadata.contentType ??
      message.body.kind ??
      '';
}

MessageSendState _sendStateFromCore(
  core.MessageMetadata metadata, {
  required bool isMine,
}) {
  final raw = (metadata.sendState ?? metadata.deliveryState ?? '')
      .toLowerCase();
  if (raw.contains('fail') || raw.contains('reject')) {
    return MessageSendState.failed;
  }
  if (raw.contains('send') && !raw.contains('sent')) {
    return MessageSendState.sending;
  }
  return isMine ? MessageSendState.sent : MessageSendState.sent;
}

bool _isEncrypted(String? contentType) {
  final raw = contentType?.toLowerCase() ?? '';
  return raw.contains('encrypted') || raw.contains('e2ee');
}

String? _attribute(core.MessageMetadata metadata, String key) {
  for (final attribute in metadata.attributes) {
    if (attribute.key == key && attribute.value.trim().isNotEmpty) {
      return attribute.value;
    }
  }
  return null;
}

RealtimeConnectionStatus _connectionStatusFromString(String raw) {
  switch (raw.toLowerCase()) {
    case 'connecting':
      return RealtimeConnectionStatus.connecting;
    case 'connected':
      return RealtimeConnectionStatus.connected;
    case 'reconnecting':
      return RealtimeConnectionStatus.reconnecting;
    case 'disconnected':
    case 'closed':
      return RealtimeConnectionStatus.disconnected;
    case 'failed':
    case 'error':
      return RealtimeConnectionStatus.failed;
    case 'idle':
    default:
      return RealtimeConnectionStatus.idle;
  }
}
