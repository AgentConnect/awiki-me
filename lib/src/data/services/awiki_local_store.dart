class AwikiLocalStoreSchema {
  const AwikiLocalStoreSchema._();

  static const int schemaVersion = 9;

  static const List<String> tables = <String>[
    'threads',
    'messages',
    'groups',
    'group_members',
    'contacts',
    'pending_ops',
  ];

  static const List<String> mirroredRemoteFields = <String>[
    'owner_did',
    'thread_id',
    'msg_id',
    'server_seq',
    'group_id',
    'last_read_seq',
    'credential_name',
  ];
}
