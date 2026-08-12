// [INPUT]: Raw IDs held only in memory by Handle Recovery E2E setup, expected
//          fixture counts, observed canonical collections, and version/read
//          transitions.
// [OUTPUT]: A strict secret-free checkpoint plus fail-closed reusable oracles
//           for Fresh Root and Local Data recovery cases.
// [POS]: Test-harness-only contract. It must never become a Product/Core state
//        store and must never persist credentials, full identities, paths, or
//        message bodies.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const int handleRecoveryFixtureCheckpointSchemaVersion = 1;

enum HandleRecoveryFixtureKind {
  freshRoot('fresh_root'),
  localData('local_data');

  const HandleRecoveryFixtureKind(this.wireName);

  final String wireName;
}

enum HandleRecoveryFixtureStage {
  setup('setup'),
  identityReady('identity_ready'),
  directReady('direct_ready'),
  groupReady('group_ready'),
  agentReady('agent_ready'),
  checkpointReady('checkpoint_ready');

  const HandleRecoveryFixtureStage(this.wireName);

  final String wireName;
}

/// Opaque, non-reversible reference suitable for persisted E2E evidence.
String handleRecoveryFixtureReference(String rawValue) {
  if (rawValue.trim().isEmpty) {
    throw const FormatException('fixture reference source must not be empty');
  }
  return 'sha256:${sha256.convert(utf8.encode(rawValue))}';
}

class HandleRecoveryCrashCutHandoff {
  HandleRecoveryCrashCutHandoff._({
    required this.stage,
    required this.runRef,
    required Map<String, String> transitionReferences,
    required Map<String, int> expectedCounts,
    required this.fixtureCheckpoint,
  }) : transitionReferences = Map<String, String>.unmodifiable(
         transitionReferences,
       ),
       expectedCounts = Map<String, int>.unmodifiable(expectedCounts);

  factory HandleRecoveryCrashCutHandoff.fromRaw({
    required String runId,
    required Map<String, String> rawTransitionReferences,
    required Map<String, int> expectedCounts,
    HandleRecoveryFixtureCheckpoint? fixtureCheckpoint,
  }) {
    return HandleRecoveryCrashCutHandoff.fromJson(<String, Object?>{
      'schemaVersion': 1,
      'stage': 'recovery_commit_durable',
      'runRef': handleRecoveryFixtureReference(runId),
      'transitionReferences': <String, Object?>{
        for (final entry in rawTransitionReferences.entries)
          entry.key: handleRecoveryFixtureReference(entry.value),
      },
      'expectedCounts': <String, Object?>{
        for (final entry in expectedCounts.entries) entry.key: entry.value,
      },
      'fixtureCheckpoint': fixtureCheckpoint?.toJson(),
    });
  }

  factory HandleRecoveryCrashCutHandoff.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const <String>{
      'schemaVersion',
      'stage',
      'runRef',
      'transitionReferences',
      'expectedCounts',
      'fixtureCheckpoint',
    });
    if (json['schemaVersion'] != 1 ||
        json['stage'] != 'recovery_commit_durable') {
      throw const FormatException('crash-cut handoff schema or stage invalid');
    }
    final runRef = _requiredOpaqueReference(json, 'runRef');
    final transitionReferences = _stringMap(json, 'transitionReferences');
    final expectedCounts = _intMap(json, 'expectedCounts');
    if (!_sameStrings(
      transitionReferences.keys,
      _crashCutTransitionReferences,
    )) {
      throw const FormatException(
        'crash-cut transition reference shape is not exact',
      );
    }
    if (!_sameStrings(expectedCounts.keys, _crashCutExpectedCounts)) {
      throw const FormatException(
        'crash-cut expected count shape is not exact',
      );
    }
    for (final entry in transitionReferences.entries) {
      _requireSafeFieldName(entry.key, kind: 'transition reference');
      _requireOpaqueReference(entry.value, field: entry.key);
    }
    for (final entry in expectedCounts.entries) {
      _requireSafeFieldName(entry.key, kind: 'count');
      if (entry.value < 0) {
        throw FormatException('crash-cut count ${entry.key} is negative');
      }
    }
    final rawFixture = json['fixtureCheckpoint'];
    HandleRecoveryFixtureCheckpoint? fixtureCheckpoint;
    if (rawFixture != null) {
      if (rawFixture is! Map) {
        throw const FormatException(
          'fixtureCheckpoint must be an object or null',
        );
      }
      fixtureCheckpoint = HandleRecoveryFixtureCheckpoint.fromJson(
        <String, Object?>{
          for (final entry in rawFixture.entries)
            entry.key.toString(): entry.value,
        },
      );
    }
    return HandleRecoveryCrashCutHandoff._(
      stage: 'recovery_commit_durable',
      runRef: runRef,
      transitionReferences: transitionReferences,
      expectedCounts: expectedCounts,
      fixtureCheckpoint: fixtureCheckpoint,
    );
  }

  final String stage;
  final String runRef;
  final Map<String, String> transitionReferences;
  final Map<String, int> expectedCounts;
  final HandleRecoveryFixtureCheckpoint? fixtureCheckpoint;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'stage': stage,
    'runRef': runRef,
    'transitionReferences': transitionReferences,
    'expectedCounts': expectedCounts,
    'fixtureCheckpoint': fixtureCheckpoint?.toJson(),
  };

  void requireRunId(String runId) {
    if (runRef != handleRecoveryFixtureReference(runId)) {
      throw const HandleRecoveryOracleFailure('handoff_run_reference_mismatch');
    }
  }

  void requireTransitionReference(String name, String rawValue) {
    final expected = transitionReferences[name];
    if (expected == null ||
        expected != handleRecoveryFixtureReference(rawValue)) {
      throw const HandleRecoveryOracleFailure(
        'handoff_transition_reference_mismatch',
      );
    }
  }
}

class HandleRecoveryFixtureCheckpoint {
  HandleRecoveryFixtureCheckpoint._({
    required this.caseId,
    required this.kind,
    required this.stage,
    required this.runRef,
    required Map<String, String> references,
    required Map<String, int> expectedCounts,
  }) : references = Map<String, String>.unmodifiable(references),
       expectedCounts = Map<String, int>.unmodifiable(expectedCounts);

  factory HandleRecoveryFixtureCheckpoint.fromRaw({
    required String caseId,
    required HandleRecoveryFixtureKind kind,
    required HandleRecoveryFixtureStage stage,
    required String runId,
    required Map<String, String> rawReferences,
    required Map<String, int> expectedCounts,
  }) {
    return HandleRecoveryFixtureCheckpoint.fromJson(<String, Object?>{
      'schemaVersion': handleRecoveryFixtureCheckpointSchemaVersion,
      'caseId': caseId,
      'kind': kind.wireName,
      'stage': stage.wireName,
      'runRef': handleRecoveryFixtureReference(runId),
      'references': <String, Object?>{
        for (final entry in rawReferences.entries)
          entry.key: handleRecoveryFixtureReference(entry.value),
      },
      'expectedCounts': <String, Object?>{
        for (final entry in expectedCounts.entries) entry.key: entry.value,
      },
    });
  }

  factory HandleRecoveryFixtureCheckpoint.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const <String>{
      'schemaVersion',
      'caseId',
      'kind',
      'stage',
      'runRef',
      'references',
      'expectedCounts',
    });
    if (json['schemaVersion'] != handleRecoveryFixtureCheckpointSchemaVersion) {
      throw const FormatException('fixture checkpoint schemaVersion must be 1');
    }
    final caseId = _requiredString(json, 'caseId');
    if (!RegExp(r'^[A-Z0-9-]+$').hasMatch(caseId)) {
      throw const FormatException('fixture caseId must be a stable identifier');
    }
    final kind = _parseKind(_requiredString(json, 'kind'));
    final stage = _parseStage(_requiredString(json, 'stage'));
    final runRef = _requiredOpaqueReference(json, 'runRef');
    final references = _stringMap(json, 'references');
    final expectedCounts = _intMap(json, 'expectedCounts');
    if (references.isEmpty) {
      throw const FormatException('fixture references must not be empty');
    }
    for (final entry in references.entries) {
      _requireSafeFieldName(entry.key, kind: 'reference');
      _requireOpaqueReference(entry.value, field: entry.key);
    }
    for (final entry in expectedCounts.entries) {
      _requireSafeFieldName(entry.key, kind: 'count');
      if (entry.value < 0) {
        throw FormatException(
          'fixture count ${entry.key} must be non-negative',
        );
      }
    }
    _requireFixtureShape(
      kind: kind,
      stage: stage,
      references: references,
      expectedCounts: expectedCounts,
    );
    return HandleRecoveryFixtureCheckpoint._(
      caseId: caseId,
      kind: kind,
      stage: stage,
      runRef: runRef,
      references: references,
      expectedCounts: expectedCounts,
    );
  }

  static HandleRecoveryFixtureCheckpoint read(File file) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      throw const FormatException('fixture checkpoint must be an object');
    }
    return HandleRecoveryFixtureCheckpoint.fromJson(<String, Object?>{
      for (final entry in decoded.entries) entry.key.toString(): entry.value,
    });
  }

  final String caseId;
  final HandleRecoveryFixtureKind kind;
  final HandleRecoveryFixtureStage stage;
  final String runRef;
  final Map<String, String> references;
  final Map<String, int> expectedCounts;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': handleRecoveryFixtureCheckpointSchemaVersion,
    'caseId': caseId,
    'kind': kind.wireName,
    'stage': stage.wireName,
    'runRef': runRef,
    'references': references,
    'expectedCounts': expectedCounts,
  };

  String reference(String name) {
    final value = references[name];
    if (value == null) {
      throw const HandleRecoveryOracleFailure('fixture_reference_missing');
    }
    return value;
  }

  int expectedCount(String name) {
    final value = expectedCounts[name];
    if (value == null) {
      throw const HandleRecoveryOracleFailure('fixture_count_missing');
    }
    return value;
  }

  void requireReference(String name, String rawValue) {
    if (reference(name) != handleRecoveryFixtureReference(rawValue)) {
      throw const HandleRecoveryOracleFailure('fixture_reference_mismatch');
    }
  }

  Future<void> write(File file) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(toJson()), flush: true);
    await temporary.rename(file.path);
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['600', file.path]);
    }
  }

  void requireReplayOf(HandleRecoveryFixtureCheckpoint original) {
    if (caseId != original.caseId ||
        kind != original.kind ||
        runRef != original.runRef ||
        stage != original.stage ||
        !_sameMap(references, original.references) ||
        !_sameMap(expectedCounts, original.expectedCounts)) {
      throw const HandleRecoveryOracleFailure(
        'fixture_replay_created_or_replaced_resource',
      );
    }
  }
}

class HandleRecoveryOracleFailure implements Exception {
  const HandleRecoveryOracleFailure(this.code);

  final String code;

  @override
  String toString() => 'HandleRecoveryOracleFailure($code)';
}

T requireHandleRecoveryExactOne<T>({
  required Iterable<T> rawItems,
  required bool Function(T item) canonicalMatch,
  required bool Function(T item) semanticMatch,
}) {
  final items = rawItems.toList(growable: false);
  final canonicalIndexes = <int>[];
  final semanticIndexes = <int>[];
  for (var index = 0; index < items.length; index += 1) {
    final item = items[index];
    if (canonicalMatch(item)) canonicalIndexes.add(index);
    if (semanticMatch(item)) semanticIndexes.add(index);
  }
  if (canonicalIndexes.length != 1 || semanticIndexes.length != 1) {
    throw const HandleRecoveryOracleFailure('canonical_exact_one_failed');
  }
  if (canonicalIndexes.single != semanticIndexes.single) {
    throw const HandleRecoveryOracleFailure(
      'canonical_semantic_reference_mismatch',
    );
  }
  return items[canonicalIndexes.single];
}

T requireHandleRecoveryReferenceExactOne<T>({
  required Iterable<T> rawItems,
  required String expectedReference,
  required String Function(T item) rawReference,
  bool Function(T item)? semanticMatch,
}) {
  final items = rawItems.toList(growable: false);
  final referenceIndexes = <int>[];
  final semanticIndexes = <int>[];
  for (var index = 0; index < items.length; index += 1) {
    final item = items[index];
    if (handleRecoveryFixtureReference(rawReference(item)) ==
        expectedReference) {
      referenceIndexes.add(index);
    }
    if (semanticMatch == null || semanticMatch(item)) {
      semanticIndexes.add(index);
    }
  }
  if (referenceIndexes.isEmpty) {
    throw const HandleRecoveryOracleFailure('fixture_reference_not_found');
  }
  if (referenceIndexes.length > 1) {
    throw const HandleRecoveryOracleFailure('fixture_reference_duplicated');
  }
  if (semanticMatch != null &&
      (semanticIndexes.length != 1 ||
          semanticIndexes.single != referenceIndexes.single)) {
    throw const HandleRecoveryOracleFailure(
      'fixture_reference_semantic_mismatch',
    );
  }
  return items[referenceIndexes.single];
}

void requireHandleRecoveryGenerationAdvance({
  required String previous,
  required String current,
}) {
  final before = BigInt.tryParse(previous);
  final after = BigInt.tryParse(current);
  if (before == null || after == null || after != before + BigInt.one) {
    throw const HandleRecoveryOracleFailure(
      'identity_generation_not_advanced_once',
    );
  }
}

void requireHandleRecoveryReadWatermark({
  required String previousThreadSequence,
  required String currentThreadSequence,
  String? expectedThreadSequence,
}) {
  final previous = BigInt.tryParse(previousThreadSequence);
  final current = BigInt.tryParse(currentThreadSequence);
  final expected = expectedThreadSequence == null
      ? null
      : BigInt.tryParse(expectedThreadSequence);
  if (previous == null ||
      current == null ||
      (expectedThreadSequence != null && expected == null)) {
    throw const HandleRecoveryOracleFailure('read_watermark_not_canonical');
  }
  if (current < previous) {
    throw const HandleRecoveryOracleFailure('read_watermark_regressed');
  }
  if (expected != null && current != expected) {
    throw const HandleRecoveryOracleFailure('read_watermark_not_exact');
  }
}

void requireHandleRecoveryAccountStateVersions({
  required Map<String, String> previous,
  required Map<String, String> current,
  required Set<String> advancedDomains,
}) {
  if (previous.isEmpty ||
      previous.length != current.length ||
      previous.length != previous.keys.toSet().length ||
      current.length != current.keys.toSet().length ||
      !_sameStrings(previous.keys, current.keys)) {
    throw const HandleRecoveryOracleFailure('account_state_domain_set_changed');
  }
  for (final domain in previous.keys) {
    final before = BigInt.tryParse(previous[domain]!);
    final after = BigInt.tryParse(current[domain]!);
    if (before == null || after == null) {
      throw const HandleRecoveryOracleFailure(
        'account_state_version_not_canonical',
      );
    }
    if (after < before) {
      throw const HandleRecoveryOracleFailure(
        'account_state_version_regressed',
      );
    }
    if (advancedDomains.contains(domain) && after <= before) {
      throw const HandleRecoveryOracleFailure(
        'account_state_domain_did_not_advance',
      );
    }
  }
  if (!previous.keys.toSet().containsAll(advancedDomains)) {
    throw const HandleRecoveryOracleFailure(
      'account_state_unknown_advanced_domain',
    );
  }
}

void requireHandleRecoveryStaleGenerationRejected({
  required String staleGeneration,
  required String currentGeneration,
  required bool accepted,
}) {
  final stale = BigInt.tryParse(staleGeneration);
  final current = BigInt.tryParse(currentGeneration);
  if (stale == null || current == null || stale >= current) {
    throw const HandleRecoveryOracleFailure(
      'stale_generation_precondition_invalid',
    );
  }
  if (accepted) {
    throw const HandleRecoveryOracleFailure('stale_generation_was_accepted');
  }
}

typedef HandleRecoveryFixtureFailureRecorder =
    Future<void> Function({
      required String caseId,
      required String stage,
      required String code,
    });

class HandleRecoveryFixtureProgress {
  HandleRecoveryFixtureProgress({
    HandleRecoveryFixtureStage initial = HandleRecoveryFixtureStage.setup,
  }) : _stage = initial;

  HandleRecoveryFixtureStage _stage;

  HandleRecoveryFixtureStage get stage => _stage;

  void advance(HandleRecoveryFixtureStage next) {
    if (next.index < _stage.index) {
      throw const HandleRecoveryOracleFailure('fixture_stage_regressed');
    }
    _stage = next;
  }
}

Future<T> runHandleRecoveryFixtureStage<T>({
  required String caseId,
  required HandleRecoveryFixtureProgress progress,
  required Future<T> Function() action,
  required HandleRecoveryFixtureFailureRecorder recordFailure,
}) async {
  try {
    return await action();
  } catch (_) {
    await recordFailure(
      caseId: caseId,
      stage: progress.stage.wireName,
      code: 'recovery_fixture_${progress.stage.wireName}_failed',
    );
    rethrow;
  }
}

const Set<String> _freshRootReferences = <String>{
  'admin_identity',
  'daemon_agent',
  'direct_peer',
  'external_group_member',
  'transport_group',
  'runtime_agent',
  'runtime_handle',
};

const Set<String> _localDataReferences = <String>{
  ..._freshRootReferences,
  'direct_conversation',
  'peer_direct_conversation',
  'direct_outgoing_message',
  'direct_outgoing_semantic',
  'direct_incoming_message',
  'direct_incoming_semantic',
  'direct_read_message',
  'group_conversation',
  'group_outgoing_message',
  'group_outgoing_semantic',
  'group_incoming_message',
  'group_incoming_semantic',
  'group_read_message',
  'agent_conversation',
  'agent_prompt_message',
  'agent_prompt_semantic',
  'agent_reply_message',
  'agent_reply_semantic',
  'conversation_inventory',
  'agent_inventory',
};

const Set<String> _freshRootCounts = <String>{
  'admin_identities',
  'daemon_agents',
  'direct_peers',
  'external_group_members',
  'transport_groups',
  'runtime_agents',
};

const Set<String> _localDataCounts = <String>{
  ..._freshRootCounts,
  'direct_messages',
  'group_messages',
  'group_members',
  'agent_messages',
  'agent_inventory_items',
  'conversations',
};

const Set<String> _crashCutTransitionReferences = <String>{
  'owner_identity',
  'account',
  'handle',
  'previous_identity',
  'current_identity',
  'operation',
  'previous_generation',
  'current_generation',
};

const Set<String> _crashCutExpectedCounts = <String>{
  'local_identities',
  'pre_reset_registry_devices',
};

void _requireFixtureShape({
  required HandleRecoveryFixtureKind kind,
  required HandleRecoveryFixtureStage stage,
  required Map<String, String> references,
  required Map<String, int> expectedCounts,
}) {
  final requiredReferences = kind == HandleRecoveryFixtureKind.freshRoot
      ? _freshRootReferences
      : _localDataReferences;
  final requiredCounts = kind == HandleRecoveryFixtureKind.freshRoot
      ? _freshRootCounts
      : _localDataCounts;
  if (stage == HandleRecoveryFixtureStage.checkpointReady &&
      (!_sameStrings(references.keys, requiredReferences) ||
          !_sameStrings(expectedCounts.keys, requiredCounts))) {
    throw const FormatException(
      'ready fixture checkpoint has an incomplete or unexpected shape',
    );
  }
}

HandleRecoveryFixtureKind _parseKind(String value) {
  for (final kind in HandleRecoveryFixtureKind.values) {
    if (kind.wireName == value) return kind;
  }
  throw FormatException('unsupported fixture kind "$value"');
}

HandleRecoveryFixtureStage _parseStage(String value) {
  for (final stage in HandleRecoveryFixtureStage.values) {
    if (stage.wireName == value) return stage;
  }
  throw FormatException('unsupported fixture stage "$value"');
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty || value != value.trim()) {
    throw FormatException('fixture field $key must be a non-empty string');
  }
  return value;
}

String _requiredOpaqueReference(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  _requireOpaqueReference(value, field: key);
  return value;
}

void _requireOpaqueReference(String value, {required String field}) {
  if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('fixture field $field must be an opaque reference');
  }
}

void _requireSafeFieldName(String value, {required String kind}) {
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value)) {
    throw FormatException('fixture $kind name must be stable snake_case');
  }
  if (RegExp(
    r'(otp|token|secret|password|private|credential|authorization|path|body|content|payload|cursor|did$|identity_id$)',
  ).hasMatch(value)) {
    throw FormatException('fixture $kind name is prohibited');
  }
}

Map<String, String> _stringMap(Map<String, Object?> json, String key) {
  final raw = json[key];
  if (raw is! Map) {
    throw FormatException('fixture field $key must be an object');
  }
  return <String, String>{
    for (final entry in raw.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
  }..validateExactLength(raw.length, key);
}

Map<String, int> _intMap(Map<String, Object?> json, String key) {
  final raw = json[key];
  if (raw is! Map) {
    throw FormatException('fixture field $key must be an object');
  }
  return <String, int>{
    for (final entry in raw.entries)
      if (entry.key is String && entry.value is int)
        entry.key as String: entry.value as int,
  }..validateExactLength(raw.length, key);
}

extension<T> on Map<String, T> {
  void validateExactLength(int rawLength, String field) {
    if (length != rawLength) {
      throw FormatException('fixture field $field has an invalid entry');
    }
  }
}

void _requireExactKeys(Map<String, Object?> json, Set<String> expected) {
  if (!_sameStrings(json.keys, expected)) {
    throw const FormatException('fixture checkpoint fields are not exact');
  }
}

bool _sameStrings(Iterable<String> left, Iterable<String> right) {
  final a = left.toList(growable: false)..sort();
  final b = right.toList(growable: false)..sort();
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _sameMap<K, V>(Map<K, V> left, Map<K, V> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
