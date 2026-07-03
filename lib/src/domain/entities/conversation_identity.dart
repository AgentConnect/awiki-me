import 'chat_message.dart';
import 'conversation_summary.dart';

class ConversationVisibilityIdentity {
  const ConversationVisibilityIdentity({
    required this.primaryKey,
    required this.aliasKeys,
  });

  final String primaryKey;
  final List<String> aliasKeys;

  List<String> get keys {
    final keys = <String>[];
    void add(String value) {
      final key = value.trim();
      if (key.isNotEmpty && !keys.contains(key)) {
        keys.add(key);
      }
    }

    add(primaryKey);
    for (final key in aliasKeys) {
      add(key);
    }
    return keys;
  }
}

ConversationVisibilityIdentity conversationVisibilityIdentity(
  ConversationSummary conversation, {
  String? runtimeAgentDid,
  bool includeHandleAliasesForStrongIdentity = false,
}) {
  final aliases = <String>[];
  void addAlias(String value) {
    final key = value.trim();
    if (key.isNotEmpty && !aliases.contains(key)) {
      aliases.add(key);
    }
  }

  if (conversation.isGroup) {
    final groupId = conversation.groupId?.trim();
    final groupKey = groupId != null && groupId.isNotEmpty
        ? 'group:$groupId'
        : 'group:${conversation.threadId}';
    addAlias(groupKey);
    addAlias('thread:${conversation.threadId}');
    addAlias(conversation.threadId);
    return ConversationVisibilityIdentity(
      primaryKey: groupKey,
      aliasKeys: aliases,
    );
  }

  if (isPeerScopedDirectConversation(conversation)) {
    final threadId = conversation.threadId.trim();
    final threadKey = threadId.isEmpty
        ? 'thread:${conversation.threadId}'
        : threadId;
    if (threadId.isNotEmpty) {
      addAlias('thread:$threadId');
    }
    return ConversationVisibilityIdentity(
      primaryKey: threadKey,
      aliasKeys: aliases,
    );
  }

  final explicitKey = conversation.conversationKey?.trim();
  final normalizedRuntimeAgentDid = _normalizedDid(runtimeAgentDid);
  final targetDid = _normalizedDid(conversation.targetDid);
  final targetPeer = normalizedDirectPeer(conversation.targetPeer);
  final runtimeDid =
      normalizedRuntimeAgentDid ??
      _runtimeDid(targetDid) ??
      _runtimeDid(targetPeer);

  if (runtimeDid != null) {
    final runtimeKey = 'runtime:$runtimeDid';
    _addExplicitKeyAlias(aliases, explicitKey, hasStrongDirectIdentity: true);
    addAlias(runtimeKey);
    _addDidAliases(aliases, runtimeDid);
    if (includeHandleAliasesForStrongIdentity) {
      _addHandleAliases(aliases, targetPeer);
    }
    addAlias('thread:${conversation.threadId}');
    addAlias(conversation.threadId);
    return ConversationVisibilityIdentity(
      primaryKey: runtimeKey,
      aliasKeys: aliases,
    );
  }

  if (targetDid != null) {
    final didKey = 'direct-did:$targetDid';
    _addExplicitKeyAlias(aliases, explicitKey, hasStrongDirectIdentity: true);
    addAlias(didKey);
    _addDidAliases(aliases, targetDid);
    if (includeHandleAliasesForStrongIdentity) {
      _addHandleAliases(aliases, targetPeer);
    }
    addAlias('thread:${conversation.threadId}');
    addAlias(conversation.threadId);
    return ConversationVisibilityIdentity(
      primaryKey: didKey,
      aliasKeys: aliases,
    );
  }

  final peerDid = targetPeer != null && targetPeer.startsWith('did:')
      ? targetPeer
      : null;
  if (peerDid != null) {
    final didKey = 'direct-did:$peerDid';
    _addExplicitKeyAlias(aliases, explicitKey, hasStrongDirectIdentity: true);
    addAlias(didKey);
    _addDidAliases(aliases, peerDid);
    if (includeHandleAliasesForStrongIdentity) {
      _addHandleAliases(aliases, targetPeer);
    }
    addAlias('thread:${conversation.threadId}');
    addAlias(conversation.threadId);
    return ConversationVisibilityIdentity(
      primaryKey: didKey,
      aliasKeys: aliases,
    );
  }

  final peerHandle = targetPeer;
  if (peerHandle != null) {
    final handleKey = 'direct-handle:$peerHandle';
    _addExplicitKeyAlias(aliases, explicitKey, hasStrongDirectIdentity: false);
    addAlias(handleKey);
    _addHandleAliases(aliases, peerHandle);
    addAlias('thread:${conversation.threadId}');
    addAlias(conversation.threadId);
    return ConversationVisibilityIdentity(
      primaryKey: handleKey,
      aliasKeys: aliases,
    );
  }

  final threadKey = 'thread:${conversation.threadId}';
  _addExplicitKeyAlias(aliases, explicitKey, hasStrongDirectIdentity: false);
  addAlias(threadKey);
  addAlias(conversation.threadId);
  return ConversationVisibilityIdentity(
    primaryKey: threadKey,
    aliasKeys: aliases,
  );
}

void _addExplicitKeyAlias(
  List<String> aliases,
  String? explicitKey, {
  required bool hasStrongDirectIdentity,
}) {
  final key = explicitKey?.trim();
  if (key == null || key.isEmpty) {
    return;
  }
  if (hasStrongDirectIdentity && _looksLikeHandleOnlyKey(key)) {
    return;
  }
  _addUnique(aliases, key);
}

bool sameConversationTarget(
  ConversationSummary first,
  ConversationSummary second,
) {
  if (sameConversationThread(first, second)) {
    return true;
  }
  if (first.isGroup || second.isGroup) {
    return first.isGroup &&
        second.isGroup &&
        sameNonEmpty(first.groupId, second.groupId);
  }
  return sameDirectConversationTarget(first, second);
}

bool sameConversationThread(
  ConversationSummary first,
  ConversationSummary second,
) {
  final firstThread = first.threadId.trim();
  final secondThread = second.threadId.trim();
  return firstThread.isNotEmpty && firstThread == secondThread;
}

bool isPeerScopedDirectConversation(ConversationSummary conversation) {
  return isPeerScopedDirectThreadId(conversation.threadId) &&
      !conversation.isGroup;
}

bool isPeerScopedDirectThreadId(String threadId) {
  return threadId.trim().startsWith('dm:peer-scope:');
}

bool sameDirectConversationTarget(
  ConversationSummary first,
  ConversationSummary second,
) {
  if (sameNonEmpty(first.targetDid, second.targetDid)) {
    return true;
  }
  if (hasConflictingDirectDid(first, second)) {
    return false;
  }
  final firstPeer = normalizedDirectPeer(first.targetPeer);
  final secondPeer = normalizedDirectPeer(second.targetPeer);
  return firstPeer != null && firstPeer == secondPeer;
}

bool hasConflictingDirectDid(
  ConversationSummary first,
  ConversationSummary second,
) {
  if (first.isGroup || second.isGroup) {
    return false;
  }
  final firstDid = _normalizedDid(first.targetDid);
  final secondDid = _normalizedDid(second.targetDid);
  return firstDid != null && secondDid != null && firstDid != secondDid;
}

bool sameNonEmpty(String? first, String? second) {
  final a = first?.trim();
  final b = second?.trim();
  return a != null && a.isNotEmpty && b != null && b.isNotEmpty && a == b;
}

String? normalizedDirectPeer(String? value) {
  final peer = _trimLeadingAt(value?.trim()).trim();
  if (peer.isEmpty) {
    return null;
  }
  return peer.startsWith('did:') ? peer : peer.toLowerCase();
}

String? directPeerDidFromMessages(List<ChatMessage> messages) {
  for (final message in messages.reversed) {
    if (message.isMine) {
      final receiver = message.receiverDid?.trim();
      if (receiver != null && receiver.isNotEmpty) {
        return receiver;
      }
      continue;
    }
    final sender = message.senderDid.trim();
    if (sender.isNotEmpty) {
      return sender;
    }
  }
  return null;
}

void _addDidAliases(List<String> aliases, String? did) {
  final normalized = _normalizedDid(did);
  if (normalized == null) {
    return;
  }
  _addUnique(aliases, 'direct-did:$normalized');
  _addUnique(aliases, 'direct:$normalized');
}

void _addHandleAliases(List<String> aliases, String? handle) {
  final normalized = normalizedDirectPeer(handle);
  if (normalized == null || normalized.startsWith('did:')) {
    return;
  }
  _addUnique(aliases, 'direct-handle:$normalized');
  _addUnique(aliases, 'direct:$normalized');
  final localPart = _handleLocalPart(normalized);
  _addUnique(aliases, 'direct-handle:$localPart');
  _addUnique(aliases, 'direct:$localPart');
}

void _addUnique(List<String> values, String value) {
  final key = value.trim();
  if (key.isNotEmpty && !values.contains(key)) {
    values.add(key);
  }
}

String? _normalizedDid(String? value) {
  final did = value?.trim();
  if (did == null || did.isEmpty || !did.startsWith('did:')) {
    return null;
  }
  return did;
}

String? _runtimeDid(String? value) {
  final did = _normalizedDid(value);
  if (did == null) {
    return null;
  }
  return did.contains(':agent:runtime:') || did.startsWith('did:agent:runtime')
      ? did
      : null;
}

bool _looksLikeHandleOnlyKey(String key) {
  final normalized = key.trim().toLowerCase();
  if (normalized.startsWith('direct-handle:')) {
    return true;
  }
  if (!normalized.startsWith('direct:')) {
    return false;
  }
  final value = normalized.substring('direct:'.length);
  return value.isNotEmpty && !value.startsWith('did:');
}

String _handleLocalPart(String value) {
  final normalized = _trimLeadingAt(value.trim()).toLowerCase();
  final dotIndex = normalized.indexOf('.');
  if (dotIndex <= 0) {
    return normalized;
  }
  return normalized.substring(0, dotIndex);
}

String _trimLeadingAt(String? value) {
  final text = value ?? '';
  return text.startsWith('@') ? text.substring(1).trimLeft() : text;
}
