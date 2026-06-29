import 'dart:convert';

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/app_session.dart';
import '../../application/models/daemon_subkey_authorization_revoke_result.dart';
import '../../application/models/app_thread_ref.dart';
import '../../application/models/product_local_models.dart';
import '../../application/ports/relationship_core_port.dart';
import '../../application/thread_id_utils.dart';
import '../../domain/entities/chat_mention.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_attachment.dart';
import '../../domain/entities/agent/agent_control_payloads.dart';
import '../../domain/entities/agent/agent_bootstrap.dart';
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
    String? jwtToken,
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
      jwtToken: jwtToken,
    );
  }

  SessionIdentity legacySessionFromAppSession(AppSession session) {
    return session.toLegacySessionIdentity();
  }

  UserSubkeyPackage userSubkeyPackageFromCore(
    core.DaemonSubkeyPrivatePackage package,
  ) {
    return UserSubkeyPackage(
      userDid: package.userDid,
      verificationMethod: package.verificationMethod,
      publicKeyMultibase: package.publicKeyMultibase,
      privateKeyPem: package.privateKeyPem,
      keyType: package.keyType,
      keyAlgorithm: package.keyAlgorithm,
      privateKeyEncoding: package.privateKeyEncoding,
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
    final manifest = _attachmentManifestJson(message);
    final attachment = _attachmentFromCoreMessage(message, manifest: manifest);
    final bodyMentionPayload = ChatMentionPayload.tryParsePayloadJson(
      message.body.payloadJson,
    );
    final manifestMentionPayloadJson = _mentionPayloadJson(manifest);
    final mentionPayload =
        bodyMentionPayload ??
        ChatMentionPayload.tryParsePayloadJson(manifestMentionPayloadJson);
    final payloadJson = bodyMentionPayload == null
        ? manifestMentionPayloadJson ?? message.body.payloadJson
        : message.body.payloadJson;
    final bodyText = message.body.text ?? '';
    final isMine =
        message.direction == core.MessageDirection.outgoing ||
        message.sender == ownerDid;
    final isGroup =
        message.threadKind == 'group' ||
        message.group?.trim().isNotEmpty == true ||
        message.threadId.startsWith('group:');
    final peerDid = isGroup ? null : _directPeerForMessage(ownerDid, message);
    final groupId =
        _nonEmpty(message.group) ??
        (isGroup ? _stripPrefix(message.threadId, 'group:') : null);
    return ChatMessage(
      localId: message.id,
      remoteId: message.id,
      threadId: _messageThreadId(
        ownerDid: ownerDid,
        isGroup: isGroup,
        peerDid: peerDid,
        groupId: groupId,
        fallbackThreadId: message.threadId,
      ),
      senderDid: message.sender,
      senderName:
          _attribute(message.metadata, 'senderName') ??
          _attribute(message.metadata, 'sender_name'),
      receiverDid: _nonEmpty(message.receiver),
      groupId: groupId,
      content: attachment?.caption ?? mentionPayload?.text ?? bodyText,
      originalType: attachment != null
          ? _attachmentManifestContentType
          : mentionPayload == null
          ? message.body.kind ?? message.metadata.contentType ?? 'text'
          : 'application/json',
      createdAt: _parseDateTime(message.sentAt ?? message.receivedAt),
      isMine: isMine,
      sendState: _sendStateFromCore(message.metadata, isMine: isMine),
      serverSequence: message.metadata.serverSequence,
      isEncrypted: _isEncrypted(message.metadata.contentType),
      attachment: attachment,
      payloadJson: payloadJson,
      mentions: mentionPayload?.mentions ?? const <ChatMessageMention>[],
    );
  }

  ConversationSummary conversationFromCore(
    core.Conversation conversation, {
    required String ownerDid,
    ProductConversationOverlay? overlay,
  }) {
    final isGroup =
        conversation.threadKind == 'group' ||
        conversation.threadId.startsWith('group:');
    final lastMessage = conversation.lastMessage;
    final targetPeer = isGroup
        ? null
        : _directPeerTarget(
            _directPeerHandleForMessage(lastMessage) ??
                _firstNonEmpty(
                  conversation.participants.where(
                    (participant) => participant.trim() != ownerDid.trim(),
                  ),
                ) ??
                _directPeerFromConversationThread(ownerDid, conversation),
          );
    final targetDid = isGroup
        ? null
        : _directPeerDidForMessage(ownerDid, lastMessage) ??
              ((targetPeer?.startsWith('did:') ?? false) ? targetPeer : null);
    final groupId = isGroup
        ? lastMessage?.group ?? _stripPrefix(conversation.threadId, 'group:')
        : null;
    return ConversationSummary(
      threadId: _conversationThreadId(
        ownerDid: ownerDid,
        isGroup: isGroup,
        peerDid: targetDid,
        groupId: groupId,
        fallbackThreadId: conversation.threadId,
      ),
      displayName:
          overlay?.customTitle ??
          _nonEmpty(conversation.title) ??
          groupId ??
          targetPeer ??
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
      unreadMentionCount: conversation.unreadMentionCount,
      firstUnreadMentionMessageId: conversation.firstUnreadMentionMessageId,
      isGroup: isGroup,
      targetDid: targetDid,
      targetPeer: targetPeer,
      groupId: groupId,
      avatarUri: null,
      avatarSeed: overlay?.avatarSeed,
      lastMessagePayloadJson: lastMessage?.body.payloadJson,
    );
  }

  ConversationSummary conversationFromSnapshot(
    core.ConversationSnapshotItem conversation, {
    required String ownerDid,
    ProductConversationOverlay? overlay,
  }) {
    final isGroup =
        conversation.threadKind == 'group' ||
        conversation.threadId.startsWith('group:');
    final lastMessage = conversation.lastMessage;
    final targetPeer = isGroup
        ? null
        : _directPeerTarget(
            _directPeerHandleForSnapshotMessage(lastMessage) ??
                _firstNonEmpty(
                  conversation.participants.where(
                    (participant) => participant.trim() != ownerDid.trim(),
                  ),
                ) ??
                _directPeerFromSnapshotThread(ownerDid, conversation),
          );
    final targetDid = isGroup
        ? null
        : _directPeerDidForSnapshotMessage(ownerDid, lastMessage) ??
              ((targetPeer?.startsWith('did:') ?? false) ? targetPeer : null);
    final groupId = isGroup
        ? lastMessage?.group ?? _stripPrefix(conversation.threadId, 'group:')
        : null;
    return ConversationSummary(
      threadId: _conversationThreadId(
        ownerDid: ownerDid,
        isGroup: isGroup,
        peerDid: targetDid,
        groupId: groupId,
        fallbackThreadId: conversation.threadId,
      ),
      displayName:
          overlay?.customTitle ??
          groupId ??
          targetPeer ??
          targetDid ??
          conversation.threadId,
      lastMessagePreview: lastMessage == null
          ? ''
          : _snapshotMessagePreview(lastMessage),
      lastMessageAt: _parseDateTime(
        conversation.lastMessageAt ??
            lastMessage?.sentAt ??
            lastMessage?.receivedAt,
      ),
      unreadCount: conversation.unreadCount,
      unreadMentionCount: conversation.unreadMentionCount,
      firstUnreadMentionMessageId: conversation.firstUnreadMentionMessageId,
      isGroup: isGroup,
      targetDid: targetDid,
      targetPeer: targetPeer,
      groupId: groupId,
      avatarUri: null,
      avatarSeed: overlay?.avatarSeed,
      lastMessagePayloadJson: lastMessage?.body.payloadJson,
    );
  }

  GroupSummary groupFromCoreSummary(core.GroupSummary group) {
    return GroupSummary(
      groupId: group.did,
      displayName:
          _nonEmpty(group.displayName) ?? _nonEmpty(group.name) ?? group.did,
      description: '',
      memberCount: group.memberCount ?? 0,
      lastMessageAt: _tryParseDateTime(group.lastMessageAt),
      avatarUri: _nonEmpty(group.avatarUri),
      myRole: group.myRole,
      membershipStatus: group.membershipStatus,
    );
  }

  GroupSummary groupFromCoreSnapshot(core.GroupSnapshot group) {
    return GroupSummary(
      groupId: group.did,
      displayName:
          _nonEmpty(group.displayName) ?? _nonEmpty(group.name) ?? group.did,
      description: group.description ?? '',
      memberCount: group.memberCount ?? 0,
      lastMessageAt: _tryParseDateTime(group.lastMessageAt),
      avatarUri: _nonEmpty(group.avatarUri),
      myRole: group.myRole ?? group.membershipStatus,
      membershipStatus: group.membershipStatus,
    );
  }

  GroupMemberSummary groupMemberFromCore(core.GroupMember member) {
    final did = member.did ?? '';
    final subjectType = GroupMemberSubjectType.parse(
      _nonEmpty(member.subjectType) ?? _subjectTypeFromDid(did),
    );
    final handle =
        _normalizeHandle(_nonEmpty(member.handle)) ??
        _handleFromDid(did) ??
        did;
    return GroupMemberSummary(
      userId: did,
      did: did,
      handle: handle,
      role: member.role ?? 'member',
      subjectType: subjectType,
      membershipStatus: GroupMemberMembershipStatus.parse(member.status),
    );
  }

  UserProfile userProfileFromCore(core.UserProfile profile) {
    return UserProfile(
      did: profile.subject,
      displayName:
          _nonEmpty(profile.displayName) ?? _compactDid(profile.subject),
      bio: _nonEmpty(profile.bio) ?? _nonEmpty(profile.description) ?? '',
      tags: profile.tags,
      profileMarkdown: profile.markdown ?? '',
      handle: profile.handle,
      avatarUri: _nonEmpty(profile.avatarUri) ?? _nonEmpty(profile.avatarUrl),
      profileUri: _nonEmpty(profile.profileUri),
      subjectType: _nonEmpty(profile.subjectType),
      fullHandle: profile.fullHandle,
    );
  }

  core.ProfilePatch profilePatchToCore(ProfilePatch patch) {
    return core.ProfilePatch(
      displayName: patch.effectiveDisplayName,
      bio: patch.bio,
      tags: patch.tags,
      markdown: patch.profileMarkdown,
      avatarUri: patch.avatarUri,
    );
  }

  RelationshipSummary relationshipFromCore(core.RelationStatus status) {
    return RelationshipSummary(
      did: status.peer,
      displayName: status.displayName ?? _compactDid(status.peer),
      relationship: status.relationship ?? 'none',
      avatarUri: null,
    );
  }

  DaemonSubkeyAuthorizationRevokeResult
  daemonSubkeyAuthorizationRevokeResultFromCore(
    core.DaemonSubkeyAuthorizationRevokeResult result,
  ) {
    return DaemonSubkeyAuthorizationRevokeResult(
      userDid: result.userDid,
      verificationMethod: result.verificationMethod,
      updated: result.updated,
    );
  }

  RelationshipSummary relationshipFromCoreListItem(
    core.RelationshipListItem item,
  ) {
    return RelationshipSummary(
      did: item.did,
      handle: _nonEmpty(item.handle),
      displayName:
          _nonEmpty(item.displayName) ??
          _nonEmpty(item.handle) ??
          _compactDid(item.did),
      relationship: item.relationship,
      avatarUri: _nonEmpty(item.avatarUri) ?? _nonEmpty(item.avatarUrl),
    );
  }

  CoreRelationshipPage relationshipPageFromCore(
    core.RelationshipPage page, {
    int fallbackCursorOffset = 0,
  }) {
    final items = page.items.map(relationshipFromCoreListItem).toList();
    return CoreRelationshipPage(
      items: items,
      nextCursor:
          page.nextCursor ??
          (page.hasMore ? '${fallbackCursorOffset + items.length}' : null),
      hasMore: page.hasMore,
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
    if (chatMessage.isAgentControlPayload) {
      return RealtimeUpdate(
        agentControlPayload:
            AgentControlPayloads.decode(chatMessage.payloadJson) ??
            const <String, Object?>{},
        syncDirty: event.sync?.syncDirty ?? false,
        gapDetected: event.sync?.gapDetected ?? false,
        syncEventSeq: event.sync?.eventSeq,
        syncEventType: event.sync?.eventType,
      );
    }
    final isGroup =
        chatMessage.groupId != null || message.threadKind == 'group';
    final targetPeer = isGroup
        ? null
        : _directPeerTarget(
            _directPeerHandleForMessage(message) ??
                _directPeerForMessage(ownerDid, message),
          );
    final targetDid = isGroup
        ? null
        : _directPeerDidForMessage(ownerDid, message);
    final conversation = ConversationSummary(
      threadId: chatMessage.threadId,
      displayName:
          chatMessage.groupId ?? targetPeer ?? targetDid ?? message.sender,
      lastMessagePreview: _messagePreview(message),
      lastMessageAt: chatMessage.createdAt,
      unreadCount: chatMessage.isMine ? 0 : 1,
      isGroup: isGroup,
      targetDid: targetDid,
      targetPeer: targetPeer,
      groupId: chatMessage.groupId,
      avatarUri: null,
      lastMessagePayloadJson: message.body.payloadJson,
    );
    return RealtimeUpdate(
      message: chatMessage,
      conversationHint: conversation,
      group: chatMessage.groupId == null
          ? null
          : GroupSummary(
              groupId: chatMessage.groupId!,
              displayName: chatMessage.groupId!,
              description: '',
              memberCount: 0,
              lastMessageAt: chatMessage.createdAt,
              membershipStatus: null,
            ),
      syncDirty: event.sync?.syncDirty ?? false,
      gapDetected: event.sync?.gapDetected ?? false,
      syncEventSeq: event.sync?.eventSeq,
      syncEventType: event.sync?.eventType,
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
  return DateTime.tryParse(raw)?.toLocal();
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

String _messageThreadId({
  required String ownerDid,
  required bool isGroup,
  String? peerDid,
  String? groupId,
  String? fallbackThreadId,
}) {
  final fallback = fallbackThreadId?.trim() ?? '';
  if (!isGroup && _isDirectConversationThreadId(fallback)) {
    return fallback;
  }
  return canonicalThreadId(
    ownerDid: ownerDid,
    isGroup: isGroup,
    peerDid: peerDid,
    groupId: groupId,
    fallbackThreadId: fallbackThreadId,
  );
}

String _conversationThreadId({
  required String ownerDid,
  required bool isGroup,
  String? peerDid,
  String? groupId,
  String? fallbackThreadId,
}) {
  final fallback = fallbackThreadId?.trim() ?? '';
  if (!isGroup &&
      fallback.isNotEmpty &&
      _isDirectConversationThreadId(fallback)) {
    return fallback;
  }
  if (isGroup) {
    return canonicalGroupThreadId(groupId ?? _stripPrefix(fallback, 'group:'));
  }
  return canonicalThreadId(
    ownerDid: ownerDid,
    isGroup: false,
    peerDid: peerDid,
    fallbackThreadId: fallback,
  );
}

String? _directPeerForMessage(String ownerDid, core.Message message) {
  if (message.sender.trim() != ownerDid.trim()) {
    return _nonEmpty(message.sender);
  }
  return _nonEmpty(message.receiver) ??
      _directPeerFromThreadId(ownerDid, message.threadId);
}

String? _directPeerDidForMessage(String ownerDid, core.Message? message) {
  if (message == null) {
    return null;
  }
  final currentDid =
      _attribute(message.metadata, 'peer_current_did') ??
      _attribute(message.metadata, 'resolved_target_did');
  if (currentDid != null && currentDid.startsWith('did:')) {
    return currentDid;
  }
  final peer = _directPeerForMessage(ownerDid, message);
  return (peer?.startsWith('did:') ?? false) ? peer : null;
}

String? _directPeerDidForSnapshotMessage(
  String ownerDid,
  core.ConversationSnapshotMessage? message,
) {
  if (message == null) {
    return null;
  }
  final currentDid =
      _snapshotAttribute(message, 'peer_current_did') ??
      _snapshotAttribute(message, 'resolved_target_did');
  if (currentDid != null && currentDid.startsWith('did:')) {
    return currentDid;
  }
  final owner = ownerDid.trim();
  final sender = _nonEmpty(message.sender);
  final receiver = _nonEmpty(message.receiver);
  if (sender != null && sender.startsWith('did:') && sender != owner) {
    return sender;
  }
  if (receiver != null && receiver.startsWith('did:') && receiver != owner) {
    return receiver;
  }
  return null;
}

String? _directPeerHandleForMessage(core.Message? message) {
  if (message == null) {
    return null;
  }
  return _attribute(message.metadata, 'peer_full_handle') ??
      _attribute(message.metadata, 'target_handle') ??
      ((message.threadKind == 'direct' &&
              !message.threadId.startsWith('did:') &&
              !_isInternalDirectThreadId(message.threadId))
          ? _nonEmpty(message.threadId)
          : null);
}

String? _directPeerHandleForSnapshotMessage(
  core.ConversationSnapshotMessage? message,
) {
  if (message == null) {
    return null;
  }
  return _snapshotAttribute(message, 'peer_full_handle') ??
      _snapshotAttribute(message, 'target_handle') ??
      ((message.threadKind == 'direct' &&
              !message.threadId.startsWith('did:') &&
              !_isInternalDirectThreadId(message.threadId))
          ? _nonEmpty(message.threadId)
          : null);
}

String? _directPeerTarget(String? value) {
  final target = _nonEmpty(value);
  if (target == null) {
    return null;
  }
  return target.startsWith('did:') ? target : target.toLowerCase();
}

String? _directPeerFromConversationThread(
  String ownerDid,
  core.Conversation conversation,
) {
  if (conversation.threadKind != 'direct') {
    return null;
  }
  return _directPeerFromThreadId(ownerDid, conversation.threadId) ??
      (_isInternalDirectThreadId(conversation.threadId)
          ? null
          : _nonEmpty(conversation.threadId));
}

String? _directPeerFromSnapshotThread(
  String ownerDid,
  core.ConversationSnapshotItem conversation,
) {
  if (conversation.threadKind != 'direct') {
    return null;
  }
  return _directPeerFromThreadId(ownerDid, conversation.threadId) ??
      (_isInternalDirectThreadId(conversation.threadId)
          ? null
          : _nonEmpty(conversation.threadId));
}

String? _directPeerFromThreadId(String ownerDid, String threadId) {
  final raw = threadId.trim();
  if (!raw.startsWith('dm:') || _isInternalDirectThreadId(raw)) {
    return null;
  }
  final body = raw.substring('dm:'.length);
  final owner = ownerDid.trim();
  if (body.startsWith('$owner:')) {
    return _nonEmpty(body.substring(owner.length + 1));
  }
  if (body.endsWith(':$owner')) {
    return _nonEmpty(body.substring(0, body.length - owner.length - 1));
  }
  return null;
}

bool _isInternalDirectThreadId(String threadId) {
  return threadId.trim().startsWith('dm:peer-scope:');
}

bool _isDirectConversationThreadId(String threadId) {
  return threadId.trim().startsWith('dm:');
}

String _compactDid(String did) {
  if (did.length <= 18) {
    return did;
  }
  return '${did.substring(0, 10)}…${did.substring(did.length - 6)}';
}

String? _handleFromDid(String did) {
  final normalized = did.trim();
  final userMatch = RegExp(
    r'^did:wba:[^:]+:(?:user:)?([^:]+):e1_',
  ).firstMatch(normalized);
  final userHandle = _normalizeHandle(userMatch?.group(1));
  if (userHandle != null) {
    return userHandle;
  }
  final agentMatch = RegExp(
    r'^did:wba:[^:]+:agent:[^:]+:([^:]+):e1_',
  ).firstMatch(normalized);
  return _normalizeHandle(agentMatch?.group(1));
}

String? _normalizeHandle(String? value) {
  var trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty || trimmed.startsWith('did:')) {
    return null;
  }
  while (trimmed.startsWith('@')) {
    trimmed = trimmed.substring(1).trimLeft();
  }
  if (trimmed.startsWith('wba://')) {
    trimmed = trimmed.substring('wba://'.length).trimLeft();
  }
  final dotIndex = trimmed.indexOf('.');
  if (dotIndex > 0) {
    trimmed = trimmed.substring(0, dotIndex);
  }
  return _nonEmpty(trimmed);
}

String? _subjectTypeFromDid(String did) {
  final normalized = did.trim();
  if (normalized.startsWith('did:agent:') || normalized.contains(':agent:')) {
    return 'agent';
  }
  if (normalized.startsWith('did:')) {
    return 'human';
  }
  return null;
}

String _messagePreview(core.Message message) {
  if (AgentControlPayloads.isControl(message.body.payloadJson)) {
    return '';
  }
  final manifest = _attachmentManifestJson(message);
  final attachment = _attachmentFromCoreMessage(message, manifest: manifest);
  if (attachment != null) {
    final caption = attachment.caption?.trim();
    if (caption != null && caption.isNotEmpty) {
      return caption;
    }
    return '[附件] ${attachment.displayName}';
  }
  final mentionPayload = ChatMentionPayload.tryParsePayloadJson(
    message.body.payloadJson,
  );
  if (mentionPayload != null) {
    return mentionPayload.text;
  }
  return message.body.text ??
      message.body.unsupportedContentType ??
      message.metadata.contentType ??
      message.body.kind ??
      '';
}

String _snapshotMessagePreview(core.ConversationSnapshotMessage message) {
  if (AgentControlPayloads.isControl(message.body.payloadJson)) {
    return '';
  }
  final manifest = _snapshotAttachmentManifestJson(message);
  final attachment = _attachmentFromManifest(manifest);
  if (attachment != null) {
    final caption = attachment.caption?.trim();
    if (caption != null && caption.isNotEmpty) {
      return caption;
    }
    return '[附件] ${attachment.displayName}';
  }
  final mentionPayload =
      ChatMentionPayload.tryParsePayloadJson(message.body.payloadJson) ??
      _mentionPayloadFromAttachmentManifest(manifest);
  if (mentionPayload != null) {
    return mentionPayload.text;
  }
  return message.body.text ??
      message.body.payloadJson ??
      message.body.unsupportedContentType ??
      message.contentType ??
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

String? _snapshotAttribute(
  core.ConversationSnapshotMessage message,
  String key,
) {
  for (final attribute in message.attributes) {
    if (attribute.key == key && attribute.value.trim().isNotEmpty) {
      return attribute.value;
    }
  }
  return null;
}

const String _attachmentManifestContentType =
    'application/anp-attachment-manifest+json';

ChatAttachment? _attachmentFromCoreMessage(
  core.Message message, {
  Map<String, Object?>? manifest,
}) {
  if (!_isAttachmentManifestMessage(message)) {
    return null;
  }
  final fromManifest = _attachmentFromManifest(manifest);
  if (fromManifest != null) {
    return fromManifest;
  }
  final attachmentId = _firstNonEmpty(<String>[
    _attribute(message.metadata, 'attachment_id') ?? '',
    _stringFromJsonMap(manifest, 'attachment_id') ?? '',
    _stringFromJsonMap(manifest, 'primary_attachment_id') ?? '',
  ]);
  if (attachmentId == null) {
    return null;
  }
  final filename =
      _attribute(message.metadata, 'attachment_filename') ??
      _stringFromJsonMap(manifest, 'filename') ??
      '附件';
  final mimeType =
      _attribute(message.metadata, 'attachment_mime_type') ??
      _attribute(message.metadata, 'attachment_content_type') ??
      _stringFromJsonMap(manifest, 'mime_type') ??
      'application/octet-stream';
  return ChatAttachment(
    attachmentId: attachmentId,
    filename: filename,
    mimeType: mimeType,
    sizeBytes:
        _intFromString(_attribute(message.metadata, 'attachment_size_bytes')) ??
        _intFromJsonMap(manifest, 'size_bytes'),
    caption:
        _attribute(message.metadata, 'caption') ??
        _stringFromJsonMap(manifest, 'caption'),
    objectUri:
        _attribute(message.metadata, 'object_uri') ??
        _stringFromJsonMap(manifest, 'object_uri'),
  );
}

bool _isAttachmentManifestMessage(core.Message message) {
  final values = <String?>[
    message.metadata.contentType,
    message.body.unsupportedContentType,
    message.body.kind,
  ];
  return values.any(
    (value) => value?.trim().toLowerCase() == _attachmentManifestContentType,
  );
}

Map<String, Object?>? _attachmentManifestJson(core.Message message) {
  final candidates = <String?>[
    _attribute(message.metadata, 'attachment_manifest'),
    _attribute(message.metadata, 'raw_content'),
    message.body.payloadJson,
    message.body.text,
  ];
  for (final candidate in candidates) {
    final parsed = _tryDecodeObject(candidate);
    if (parsed != null) {
      return parsed;
    }
  }
  return null;
}

Map<String, Object?>? _snapshotAttachmentManifestJson(
  core.ConversationSnapshotMessage message,
) {
  if (!_isSnapshotAttachmentManifestMessage(message)) {
    return null;
  }
  final candidates = <String?>[
    _snapshotAttribute(message, 'attachment_manifest'),
    _snapshotAttribute(message, 'raw_content'),
    message.body.payloadJson,
    message.body.text,
  ];
  for (final candidate in candidates) {
    final parsed = _tryDecodeObject(candidate);
    if (parsed != null) {
      return parsed;
    }
  }
  return null;
}

bool _isSnapshotAttachmentManifestMessage(
  core.ConversationSnapshotMessage message,
) {
  final values = <String?>[
    message.contentType,
    message.body.unsupportedContentType,
    message.body.kind,
  ];
  return values.any(
    (value) => value?.trim().toLowerCase() == _attachmentManifestContentType,
  );
}

ChatMentionPayload? _mentionPayloadFromAttachmentManifest(
  Map<String, Object?>? manifest,
) {
  final payloadJson = _mentionPayloadJson(manifest);
  return ChatMentionPayload.tryParsePayloadJson(payloadJson);
}

String? _mentionPayloadJson(Map<String, Object?>? manifest) {
  final raw = manifest?['mention_payload'];
  if (raw == null) {
    return null;
  }
  if (raw is String) {
    return _nonEmpty(raw);
  }
  if (raw is Map) {
    return jsonEncode(raw);
  }
  return null;
}

ChatAttachment? _attachmentFromManifest(Map<String, Object?>? manifest) {
  if (manifest == null) {
    return null;
  }
  final attachments = manifest['attachments'];
  if (attachments is! List || attachments.isEmpty) {
    return null;
  }
  final first = attachments.first;
  if (first is! Map) {
    return null;
  }
  final attachment = first.cast<String, Object?>();
  final attachmentId =
      _stringFromJsonMap(attachment, 'attachment_id') ??
      _stringFromJsonMap(attachment, 'id') ??
      _stringFromJsonMap(manifest, 'primary_attachment_id');
  if (attachmentId == null) {
    return null;
  }
  return ChatAttachment(
    attachmentId: attachmentId,
    filename: _stringFromJsonMap(attachment, 'filename') ?? '附件',
    mimeType:
        _stringFromJsonMap(attachment, 'mime_type') ??
        _stringFromJsonMap(attachment, 'content_type') ??
        'application/octet-stream',
    sizeBytes:
        _intFromJsonMap(attachment, 'size_bytes') ??
        _intFromString(_stringFromJsonMap(attachment, 'size')),
    caption: _stringFromJsonMap(manifest, 'caption'),
    objectUri:
        _stringFromJsonMap(attachment, 'object_uri') ??
        _stringFromNestedJsonMap(attachment, 'access_info', 'object_uri'),
  );
}

Map<String, Object?>? _tryDecodeObject(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) {
      return decoded.cast<String, Object?>();
    }
  } catch (_) {
    return null;
  }
  return null;
}

String? _stringFromJsonMap(Map<String, Object?>? value, String key) {
  final raw = value?[key];
  if (raw is String) {
    return _nonEmpty(raw);
  }
  if (raw is num) {
    return raw.toString();
  }
  return null;
}

String? _stringFromNestedJsonMap(
  Map<String, Object?>? value,
  String parent,
  String key,
) {
  final raw = value?[parent];
  if (raw is! Map) {
    return null;
  }
  return _stringFromJsonMap(raw.cast<String, Object?>(), key);
}

int? _intFromJsonMap(Map<String, Object?>? value, String key) {
  final raw = value?[key];
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  if (raw is String) {
    return _intFromString(raw);
  }
  return null;
}

int? _intFromString(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return int.tryParse(value);
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
