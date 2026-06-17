import 'dart:convert';

import 'group_member_summary.dart';

enum ChatMentionSelector {
  all('all'),
  agents('agents'),
  humans('humans');

  const ChatMentionSelector(this.wireValue);

  final String wireValue;
}

enum ChatMentionTargetKind {
  human('human'),
  agent('agent'),
  groupSelector('group_selector'),
  unknown('unknown');

  const ChatMentionTargetKind(this.wireValue);

  final String wireValue;
}

enum ChatMentionRole {
  addressee('addressee'),
  cc('cc');

  const ChatMentionRole(this.wireValue);

  final String wireValue;
}

class ChatMentionTargetDraft {
  const ChatMentionTargetDraft._({
    required this.kind,
    this.selector,
    this.did,
    this.handle,
    this.displayName,
  });

  const ChatMentionTargetDraft.groupSelector(ChatMentionSelector selector)
    : this._(kind: ChatMentionTargetKind.groupSelector, selector: selector);

  const ChatMentionTargetDraft.member({
    required ChatMentionTargetKind kind,
    required String did,
    String? handle,
    String? displayName,
  }) : this._(kind: kind, did: did, handle: handle, displayName: displayName);

  const ChatMentionTargetDraft.unknownMember({
    required String did,
    String? handle,
    String? displayName,
  }) : this._(
         kind: ChatMentionTargetKind.unknown,
         did: did,
         handle: handle,
         displayName: displayName,
       );

  final ChatMentionTargetKind kind;
  final ChatMentionSelector? selector;
  final String? did;
  final String? handle;
  final String? displayName;

  bool get isP9Sendable {
    if (kind == ChatMentionTargetKind.groupSelector) {
      return selector != null;
    }
    return (kind == ChatMentionTargetKind.human ||
            kind == ChatMentionTargetKind.agent) &&
        (did ?? '').trim().isNotEmpty;
  }

  Map<String, Object?> toP9Json() {
    if (kind == ChatMentionTargetKind.groupSelector) {
      final currentSelector = selector;
      if (currentSelector == null) {
        throw StateError('group selector mention target requires selector.');
      }
      return <String, Object?>{
        'kind': kind.wireValue,
        'selector': currentSelector.wireValue,
      };
    }
    if (kind != ChatMentionTargetKind.human &&
        kind != ChatMentionTargetKind.agent) {
      throw StateError('unknown mention target cannot be serialized to P9.');
    }
    final currentDid = did?.trim();
    if (currentDid == null || currentDid.isEmpty) {
      throw StateError('member mention target requires did.');
    }
    return <String, Object?>{'kind': kind.wireValue, 'did': currentDid};
  }
}

String? mentionTargetDisplayHandle(ChatMentionTargetDraft target) {
  final handle = _mentionHandle(target.handle);
  if (handle != null) {
    return handle;
  }
  final displayName = _mentionDisplayName(target.displayName);
  if (displayName != null && !_isDidLike(displayName)) {
    return displayName;
  }
  return _handleFromDid(target.did);
}

class ChatMentionCandidate {
  const ChatMentionCandidate({
    required this.id,
    required this.surface,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.target,
    this.enabled = true,
    this.disabledReason,
    this.searchTerms = const <String>[],
  });

  final String id;
  final String surface;
  final String title;
  final String subtitle;
  final String badge;
  final ChatMentionTargetDraft target;
  final bool enabled;
  final String? disabledReason;
  final List<String> searchTerms;

  factory ChatMentionCandidate.fromGroupMember(GroupMemberSummary member) {
    final did = member.did.trim();
    final handle = _mentionHandle(member.handle);
    final displayName = _mentionDisplayName(member.displayName);
    final subjectType = _effectiveGroupMemberSubjectType(member);
    final label = _memberMentionLabel(
      subjectType: subjectType,
      handle: handle,
      displayName: displayName,
      did: did,
    );
    final active =
        member.membershipStatus == GroupMemberMembershipStatus.active;
    final targetKind = switch (subjectType) {
      GroupMemberSubjectType.human => ChatMentionTargetKind.human,
      GroupMemberSubjectType.agent => ChatMentionTargetKind.agent,
      GroupMemberSubjectType.unknown => ChatMentionTargetKind.unknown,
    };
    final sendable =
        active && did.isNotEmpty && targetKind != ChatMentionTargetKind.unknown;
    return ChatMentionCandidate(
      id: did.isEmpty ? 'member:${member.userId}' : 'member:$did',
      surface: '@$label',
      title: label,
      subtitle: _memberSubtitle(member),
      badge: switch (subjectType) {
        GroupMemberSubjectType.human => '用户',
        GroupMemberSubjectType.agent => '智能体',
        GroupMemberSubjectType.unknown => '类型未知',
      },
      target: sendable
          ? ChatMentionTargetDraft.member(
              kind: targetKind,
              did: did,
              handle: handle,
              displayName: displayName,
            )
          : ChatMentionTargetDraft.unknownMember(
              did: did,
              handle: handle,
              displayName: displayName,
            ),
      enabled: sendable,
      disabledReason: sendable
          ? null
          : active
          ? '成员类型未知，暂不能作为单人 mention 目标'
          : '成员状态不是 active，暂不能 mention',
      searchTerms: <String>[
        label,
        displayName ?? '',
        handle ?? '',
        member.handle,
        did,
        member.userId,
      ],
    );
  }

  factory ChatMentionCandidate.forGroupSelector(ChatMentionSelector selector) {
    final surface = switch (selector) {
      ChatMentionSelector.all => '@所有人',
      ChatMentionSelector.humans => '@所有人类',
      ChatMentionSelector.agents => '@所有智能体',
    };
    final title = switch (selector) {
      ChatMentionSelector.all => '所有人',
      ChatMentionSelector.humans => '所有人类',
      ChatMentionSelector.agents => '所有智能体',
    };
    final subtitle = switch (selector) {
      ChatMentionSelector.all => '提醒群内所有成员',
      ChatMentionSelector.humans => '只提醒群内人类成员',
      ChatMentionSelector.agents => '提醒群内智能体',
    };
    final badge = switch (selector) {
      ChatMentionSelector.all => '群',
      ChatMentionSelector.humans => '人类',
      ChatMentionSelector.agents => '智能体',
    };
    return ChatMentionCandidate(
      id: 'selector:${selector.wireValue}',
      surface: surface,
      title: title,
      subtitle: subtitle,
      badge: badge,
      target: ChatMentionTargetDraft.groupSelector(selector),
      searchTerms: <String>[
        surface,
        title,
        subtitle,
        selector.wireValue,
        switch (selector) {
          ChatMentionSelector.all => 'all everyone 全体 全部 所有人',
          ChatMentionSelector.humans => 'humans human user users 人 人类 用户',
          ChatMentionSelector.agents => 'agents agent bot bots 智能体 代理',
        },
      ],
    );
  }

  bool matchesQuery(String query) {
    final normalized = _normalizeSearch(query);
    if (normalized.isEmpty) {
      return true;
    }
    return <String>[
      surface,
      title,
      subtitle,
      badge,
      ...searchTerms,
    ].map(_normalizeSearch).any((term) => term.contains(normalized));
  }

  static List<ChatMentionCandidate> forGroupMembers(
    Iterable<GroupMemberSummary> members, {
    String query = '',
  }) {
    final candidates = <ChatMentionCandidate>[
      ChatMentionCandidate.forGroupSelector(ChatMentionSelector.all),
      ChatMentionCandidate.forGroupSelector(ChatMentionSelector.humans),
      ChatMentionCandidate.forGroupSelector(ChatMentionSelector.agents),
      for (final member in members)
        if (member.membershipStatus == GroupMemberMembershipStatus.active)
          ChatMentionCandidate.fromGroupMember(member),
    ];
    return candidates
        .where((candidate) => candidate.matchesQuery(query))
        .toList();
  }
}

class ChatMentionDraft {
  const ChatMentionDraft({
    required this.localId,
    required this.surface,
    required this.start,
    required this.end,
    required this.target,
    this.role = ChatMentionRole.addressee,
  });

  final String localId;
  final String surface;
  final int start;
  final int end;
  final ChatMentionTargetDraft target;
  final ChatMentionRole role;

  bool rangeMatches(String text) {
    return start >= 0 &&
        end >= start &&
        end <= text.length &&
        text.substring(start, end) == surface;
  }

  ChatMentionDraft copyWith({int? start, int? end}) {
    return ChatMentionDraft(
      localId: localId,
      surface: surface,
      start: start ?? this.start,
      end: end ?? this.end,
      target: target,
      role: role,
    );
  }

  ChatMentionWireRange toWireRange(String text) {
    if (!rangeMatches(text)) {
      throw StateError('mention range no longer matches draft text.');
    }
    return ChatMentionWireRange(
      start: codePointOffsetForCodeUnit(text, start),
      end: codePointOffsetForCodeUnit(text, end),
    );
  }

  Map<String, Object?> toP9Json(String text) {
    final range = toWireRange(text);
    return <String, Object?>{
      'id': localId,
      'range': range.toJson(),
      'target': target.toP9Json(),
      'mention_role': role.wireValue,
    };
  }

  static List<ChatMentionDraft> transformMentions({
    required String oldText,
    required String newText,
    required Iterable<ChatMentionDraft> oldMentions,
  }) {
    if (oldText == newText) {
      return oldMentions
          .where((mention) => mention.rangeMatches(newText))
          .toList();
    }

    var prefix = 0;
    final shortest = oldText.length < newText.length
        ? oldText.length
        : newText.length;
    while (prefix < shortest &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix += 1;
    }

    var oldSuffix = oldText.length;
    var newSuffix = newText.length;
    while (oldSuffix > prefix &&
        newSuffix > prefix &&
        oldText.codeUnitAt(oldSuffix - 1) ==
            newText.codeUnitAt(newSuffix - 1)) {
      oldSuffix -= 1;
      newSuffix -= 1;
    }

    final delta = (newSuffix - prefix) - (oldSuffix - prefix);
    final transformed = <ChatMentionDraft>[];
    for (final mention in oldMentions) {
      ChatMentionDraft? next;
      if (oldSuffix <= mention.start) {
        next = mention.copyWith(
          start: mention.start + delta,
          end: mention.end + delta,
        );
      } else if (prefix >= mention.end) {
        next = mention;
      } else {
        next = null;
      }
      if (next != null && next.rangeMatches(newText)) {
        transformed.add(next);
      }
    }
    return transformed;
  }

  static List<ChatMentionDraft> mergeReplacingOverlap(
    Iterable<ChatMentionDraft> mentions,
    ChatMentionDraft inserted,
    String text,
  ) {
    final next = <ChatMentionDraft>[
      for (final mention in mentions)
        if (mention.rangeMatches(text) &&
            (mention.end <= inserted.start || mention.start >= inserted.end))
          mention,
      inserted,
    ];
    next.sort((a, b) => a.start.compareTo(b.start));
    return next;
  }
}

class ChatMentionWireRange {
  const ChatMentionWireRange({required this.start, required this.end});

  final int start;
  final int end;

  Map<String, Object?> toJson() => <String, Object?>{
    'start': start,
    'end': end,
    'unit': 'unicode_code_point',
  };
}

class ChatMessageMention {
  const ChatMessageMention({
    required this.id,
    required this.surface,
    required this.start,
    required this.end,
    required this.target,
    this.role = ChatMentionRole.addressee,
  });

  final String id;
  final String surface;
  final int start;
  final int end;
  final ChatMentionTargetDraft target;
  final ChatMentionRole role;

  factory ChatMessageMention.fromDraft(ChatMentionDraft draft) {
    return ChatMessageMention(
      id: draft.localId,
      surface: draft.surface,
      start: draft.start,
      end: draft.end,
      target: draft.target,
      role: draft.role,
    );
  }

  bool rangeMatches(String text) {
    return start >= 0 &&
        end >= start &&
        end <= text.length &&
        text.substring(start, end) == surface;
  }

  ChatMentionWireRange toWireRange(String text) {
    if (!rangeMatches(text)) {
      throw StateError('mention range no longer matches message text.');
    }
    return ChatMentionWireRange(
      start: codePointOffsetForCodeUnit(text, start),
      end: codePointOffsetForCodeUnit(text, end),
    );
  }

  static ChatMessageMention? tryParseP9({
    required String text,
    required Map<String, Object?> json,
    required Set<String> seenIds,
  }) {
    if (_containsForbiddenMentionField(json)) {
      return null;
    }
    final id = (json['id'] as String?)?.trim();
    if (id == null || id.isEmpty || !seenIds.add(id)) {
      return null;
    }
    final range = json['range'];
    final target = json['target'];
    if (range is! Map || target is! Map) {
      return null;
    }
    final unit = (range['unit'] as String?)?.trim().toLowerCase();
    final start = range['start'];
    final end = range['end'];
    if (unit != 'unicode_code_point' || start is! int || end is! int) {
      return null;
    }
    if (start < 0 || end <= start) {
      return null;
    }
    late final int startCodeUnit;
    late final int endCodeUnit;
    try {
      startCodeUnit = codeUnitOffsetForCodePoint(text, start);
      endCodeUnit = codeUnitOffsetForCodePoint(text, end);
    } on RangeError {
      return null;
    }
    if (endCodeUnit <= startCodeUnit || endCodeUnit > text.length) {
      return null;
    }
    final parsedTarget = _parseP9Target(target.cast<String, Object?>());
    if (parsedTarget == null) {
      return null;
    }
    final parsedRole = _parseP9Role(json['mention_role']);
    if (parsedRole == null) {
      return null;
    }
    return ChatMessageMention(
      id: id,
      surface: text.substring(startCodeUnit, endCodeUnit),
      start: startCodeUnit,
      end: endCodeUnit,
      target: parsedTarget,
      role: parsedRole,
    );
  }
}

class ChatMentionPayload {
  const ChatMentionPayload({required this.text, required this.mentions});

  final String text;
  final List<ChatMessageMention> mentions;

  bool get hasValidMentions => mentions.isNotEmpty;

  static ChatMentionPayload? tryParsePayloadJson(String? payloadJson) {
    final raw = payloadJson?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    final object = decoded.cast<String, Object?>();
    final text = object['text'];
    final mentions = object['mentions'];
    if (text is! String || mentions is! List) {
      return null;
    }
    final seenIds = <String>{};
    final parsedMentions = <ChatMessageMention>[];
    for (final item in mentions) {
      if (item is! Map) {
        continue;
      }
      final parsed = ChatMessageMention.tryParseP9(
        text: text,
        json: item.cast<String, Object?>(),
        seenIds: seenIds,
      );
      if (parsed != null) {
        parsedMentions.add(parsed);
      }
    }
    return ChatMentionPayload(text: text, mentions: parsedMentions);
  }

  static Map<String, Object?> toP9Json({
    required String text,
    required Iterable<ChatMentionDraft> draftMentions,
  }) {
    return <String, Object?>{
      'text': text,
      'mentions': <Map<String, Object?>>[
        for (final mention in draftMentions)
          if (mention.rangeMatches(text) && mention.target.isP9Sendable)
            mention.toP9Json(text),
      ],
    };
  }
}

class ChatMentionTrigger {
  const ChatMentionTrigger({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;

  static ChatMentionTrigger? detect({
    required String text,
    required int selectionBaseOffset,
    required int selectionExtentOffset,
    required int composingStart,
    required int composingEnd,
    required bool isGroup,
  }) {
    if (!isGroup || selectionBaseOffset != selectionExtentOffset) {
      return null;
    }
    if (composingStart >= 0 && composingEnd > composingStart) {
      return null;
    }
    final cursor = selectionExtentOffset;
    if (cursor < 1 || cursor > text.length) {
      return null;
    }
    var index = cursor - 1;
    while (index >= 0) {
      final codeUnit = text.codeUnitAt(index);
      if (codeUnit == 0x40) {
        if (!_hasMentionBoundaryBefore(text, index)) {
          return null;
        }
        return ChatMentionTrigger(
          start: index,
          end: cursor,
          query: text.substring(index + 1, cursor),
        );
      }
      if (_isMentionQueryBreak(codeUnit)) {
        return null;
      }
      index -= 1;
    }
    return null;
  }

  ChatMentionInsertion insert(ChatMentionCandidate candidate) {
    final surfaceWithSpace = '${candidate.surface} ';
    return ChatMentionInsertion(
      textStart: start,
      textEnd: end,
      insertedText: surfaceWithSpace,
      mentionSurface: candidate.surface,
      target: candidate.target,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChatMentionTrigger &&
        other.start == start &&
        other.end == end &&
        other.query == query;
  }

  @override
  int get hashCode => Object.hash(start, end, query);
}

class ChatMentionInsertion {
  ChatMentionInsertion({
    required this.textStart,
    required this.textEnd,
    required this.insertedText,
    required this.mentionSurface,
    required this.target,
  });

  final int textStart;
  final int textEnd;
  final String insertedText;
  final String mentionSurface;
  final ChatMentionTargetDraft target;

  ChatMentionInsertionResult applyTo(String text) {
    final nextText = text.replaceRange(textStart, textEnd, insertedText);
    final mention = ChatMentionDraft(
      localId: 'men_${DateTime.now().microsecondsSinceEpoch}',
      surface: mentionSurface,
      start: textStart,
      end: textStart + mentionSurface.length,
      target: target,
    );
    return ChatMentionInsertionResult(
      text: nextText,
      selectionOffset: textStart + insertedText.length,
      mention: mention,
    );
  }
}

class ChatMentionInsertionResult {
  const ChatMentionInsertionResult({
    required this.text,
    required this.selectionOffset,
    required this.mention,
  });

  final String text;
  final int selectionOffset;
  final ChatMentionDraft mention;
}

int codePointOffsetForCodeUnit(String text, int codeUnitOffset) {
  if (codeUnitOffset < 0 || codeUnitOffset > text.length) {
    throw RangeError.range(codeUnitOffset, 0, text.length, 'codeUnitOffset');
  }
  var codeUnits = 0;
  var codePoints = 0;
  for (final rune in text.runes) {
    final runeLength = rune > 0xFFFF ? 2 : 1;
    if (codeUnits >= codeUnitOffset) {
      break;
    }
    if (codeUnits + runeLength > codeUnitOffset) {
      break;
    }
    codeUnits += runeLength;
    codePoints += 1;
  }
  return codePoints;
}

int codeUnitOffsetForCodePoint(String text, int codePointOffset) {
  if (codePointOffset < 0) {
    throw RangeError.value(codePointOffset, 'codePointOffset');
  }
  var codeUnits = 0;
  var codePoints = 0;
  for (final rune in text.runes) {
    if (codePoints >= codePointOffset) {
      break;
    }
    codeUnits += rune > 0xFFFF ? 2 : 1;
    codePoints += 1;
  }
  if (codePointOffset > codePoints) {
    throw RangeError.range(codePointOffset, 0, codePoints, 'codePointOffset');
  }
  return codeUnits;
}

ChatMentionTargetDraft? _parseP9Target(Map<String, Object?> target) {
  final kind = (target['kind'] as String?)?.trim().toLowerCase();
  return switch (kind) {
    'group_selector' => _parseP9GroupSelectorTarget(target),
    'agent' => _parseP9MemberTarget(ChatMentionTargetKind.agent, target),
    'human' => _parseP9MemberTarget(ChatMentionTargetKind.human, target),
    _ => null,
  };
}

ChatMentionTargetDraft? _parseP9GroupSelectorTarget(
  Map<String, Object?> target,
) {
  final selector = switch ((target['selector'] as String?)
      ?.trim()
      .toLowerCase()) {
    'all' => ChatMentionSelector.all,
    'agents' => ChatMentionSelector.agents,
    'humans' => ChatMentionSelector.humans,
    _ => null,
  };
  if (selector == null) {
    return null;
  }
  return ChatMentionTargetDraft.groupSelector(selector);
}

ChatMentionTargetDraft? _parseP9MemberTarget(
  ChatMentionTargetKind kind,
  Map<String, Object?> target,
) {
  final did = (target['did'] as String?)?.trim();
  if (did == null || did.isEmpty) {
    return null;
  }
  return ChatMentionTargetDraft.member(
    kind: kind,
    did: did,
    handle: _handleFromDid(did),
    displayName: (target['display_name'] as String?)?.trim(),
  );
}

ChatMentionRole? _parseP9Role(Object? value) {
  final role = (value as String?)?.trim().toLowerCase();
  return switch (role == null || role.isEmpty ? 'addressee' : role) {
    'addressee' => ChatMentionRole.addressee,
    'cc' => ChatMentionRole.cc,
    _ => null,
  };
}

bool _containsForbiddenMentionField(Map<String, Object?> mention) {
  const forbidden = <String>{
    'sender',
    'sender_did',
    'from',
    'actor_did',
    'auth',
    'proof',
    'signature',
  };
  return mention.keys
      .map((key) => key.trim().toLowerCase())
      .any(forbidden.contains);
}

bool _hasMentionBoundaryBefore(String text, int atIndex) {
  if (atIndex == 0) {
    return true;
  }
  final previous = text.codeUnitAt(atIndex - 1);
  return _isWhitespace(previous) || _isMentionBoundaryPunctuation(previous);
}

bool _isMentionQueryBreak(int codeUnit) {
  return _isWhitespace(codeUnit) || codeUnit == 0x40;
}

bool _isWhitespace(int codeUnit) {
  return codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D;
}

bool _isMentionBoundaryPunctuation(int codeUnit) {
  return const <int>{
    0x28, // (
    0x5B, // [
    0x7B, // {
    0x22, // "
    0x27, // '
    0xFF08, // （
    0x3010, // 【
    0x300C, // 「
    0x201C, // “
  }.contains(codeUnit);
}

String _normalizeSearch(String value) {
  var text = value.trim().toLowerCase();
  while (text.startsWith('@')) {
    text = text.substring(1).trimLeft();
  }
  return text;
}

String _memberSubtitle(GroupMemberSummary member) {
  final handle = _mentionHandle(member.handle);
  final fields = <String>[
    if (handle != null) '@$handle',
    if (member.did.trim().isNotEmpty) _compactDid(member.did.trim()),
  ];
  return fields.isEmpty ? '群成员' : fields.join(' · ');
}

GroupMemberSubjectType _effectiveGroupMemberSubjectType(
  GroupMemberSummary member,
) {
  if (member.subjectType != GroupMemberSubjectType.unknown) {
    return member.subjectType;
  }
  return _inferGroupMemberSubjectType(did: member.did);
}

GroupMemberSubjectType _inferGroupMemberSubjectType({required String did}) {
  final normalizedDid = did.trim().toLowerCase();
  if (normalizedDid.startsWith('did:agent:') ||
      normalizedDid.contains(':agent:') ||
      normalizedDid.contains(':agents:') ||
      normalizedDid.contains(':runtime_agent:')) {
    return GroupMemberSubjectType.agent;
  }
  if (normalizedDid.startsWith('did:')) {
    return GroupMemberSubjectType.human;
  }
  return GroupMemberSubjectType.unknown;
}

String _memberMentionLabel({
  required GroupMemberSubjectType subjectType,
  required String? handle,
  required String? displayName,
  required String did,
}) {
  final safeDisplayName = _isDidLike(displayName) ? null : displayName;
  return switch (subjectType) {
    GroupMemberSubjectType.agent => _firstNonEmpty(<String?>[
      handle,
      safeDisplayName,
      _compactDid(did),
    ]),
    GroupMemberSubjectType.human || GroupMemberSubjectType.unknown =>
      _firstNonEmpty(<String?>[safeDisplayName, handle, _compactDid(did)]),
  };
}

String? _mentionHandle(String? value) {
  var trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  while (trimmed.startsWith('@')) {
    trimmed = trimmed.substring(1).trimLeft();
  }
  if (trimmed.startsWith('wba://')) {
    trimmed = trimmed.substring('wba://'.length).trimLeft();
  }
  if (trimmed.isEmpty || _isDidLike(trimmed)) {
    return null;
  }
  final dotIndex = trimmed.indexOf('.');
  if (dotIndex > 0) {
    trimmed = trimmed.substring(0, dotIndex);
  }
  return trimmed.isEmpty ? null : trimmed;
}

String? _mentionDisplayName(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

bool _isDidLike(String? value) => value?.trim().startsWith('did:') == true;

String? _handleFromDid(String? did) {
  final value = did?.trim() ?? '';
  if (value.isEmpty) {
    return null;
  }
  final parts = value.split(':');
  if (parts.length >= 6 && parts[0] == 'did' && parts[1] == 'wba') {
    if (parts[3] == 'user') {
      return _mentionHandle(parts[4]);
    }
    if (parts[3] == 'agent' && parts.length >= 7) {
      return _mentionHandle(parts[5]);
    }
    return _mentionHandle(parts[3]);
  }
  return null;
}

String _compactDid(String did) {
  final value = did.trim();
  if (value.length <= 18) {
    return value;
  }
  return '${value.substring(0, 10)}…${value.substring(value.length - 6)}';
}

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '成员';
}
