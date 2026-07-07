import 'dart:convert';

const String groupSystemEventSchema = 'awiki.group.system_event.v1';

class GroupSystemEvent {
  const GroupSystemEvent({
    required this.type,
    required this.groupDid,
    required this.groupEventSeq,
    this.groupStateVersion,
    this.actorDid,
    this.subjectDid,
    this.membershipStatus,
    this.changedAt,
  });

  final String type;
  final String groupDid;
  final int? groupEventSeq;
  final String? groupStateVersion;
  final String? actorDid;
  final String? subjectDid;
  final String? membershipStatus;
  final DateTime? changedAt;

  bool get isMemberAdded => type == 'member_added';
  bool get isMemberRemoved => type == 'member_removed';
  bool get isMemberLeft => type == 'member_left';
  bool get isGroupProfileUpdated => type == 'group_profile_updated';

  static GroupSystemEvent? tryParse(String? payloadJson) {
    final raw = payloadJson?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    if (_string(decoded['schema']) != groupSystemEventSchema) {
      return null;
    }
    final type = _normalizeType(_string(decoded['type']));
    final groupDid = _string(decoded['group_did']);
    if (type.isEmpty || groupDid.isEmpty) {
      return null;
    }
    return GroupSystemEvent(
      type: type,
      groupDid: groupDid,
      groupEventSeq: _int(decoded['group_event_seq']),
      groupStateVersion: _string(decoded['group_state_version']),
      actorDid: _string(decoded['actor_did']),
      subjectDid: _string(decoded['subject_did']),
      membershipStatus: _string(decoded['membership_status']),
      changedAt: _dateTime(decoded['changed_at']),
    );
  }
}

String _normalizeType(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('-', '_');
  return switch (normalized) {
    'member_activated' => 'member_added',
    'profile_updated' => 'group_profile_updated',
    _ => normalized,
  };
}

String _string(Object? value) {
  if (value is String) {
    return value.trim();
  }
  if (value is num) {
    return value.toString();
  }
  return '';
}

int? _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

DateTime? _dateTime(Object? value) {
  final raw = _string(value);
  if (raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}
