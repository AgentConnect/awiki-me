import 'dart:convert';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/group_application_service.dart';
import 'package:awiki_me/src/application/models/group_collection_page.dart';
import 'package:awiki_me/src/application/ports/group_encryption_core_port.dart';
import 'package:awiki_me/src/domain/entities/group_encryption_status.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';

import 'app_pair_protocol.dart';

/// Passive, bounded test evidence. Public group IDs stay in memory and are
/// reduced to a target comparison before serialization.
class Step4GroupDiagnostics {
  String phase = 'preparing';
  final _events = <Map<String, Object?>>[];
  final _lastStatus = <String, String>{};
  int droppedEvents = 0;

  void record(String group, String action, Map<String, Object?> facts) {
    if (action == 'status' && facts['outcome'] != 'error') {
      final key = '$phase:${jsonEncode(facts)}';
      if (_lastStatus[group] == key) return;
      _lastStatus[group] = key;
    }
    _events.add({'group': group, 'phase': phase, 'action': action, ...facts});
    if (_events.length > 32) {
      _events.removeAt(0);
      droppedEvents++;
    }
  }

  void failure(String group, String action, Object error) {
    record(group, action, {
      'outcome': 'error',
      'diagnostic': error is core.AwikiImCoreException
          ? safeCliFailureDiagnostic(
              exitCode: 1,
              stdout: null,
              stderr: jsonEncode({
                'error': {
                  'code': error.code,
                  'details': {'service_code': error.serviceCode},
                },
              }),
            )
          : 'other_error',
    });
  }

  List<Map<String, Object?>> summary(String target) => [
    for (final event in _events)
      {
        'target_group': event['group'] == target,
        for (final entry in event.entries)
          if (entry.key != 'group') entry.key: entry.value,
      },
  ];
}

class Step4ObservedGroups implements GroupApplicationService {
  Step4ObservedGroups(this.delegate, this.diagnostics);
  final GroupApplicationService delegate;
  final Step4GroupDiagnostics diagnostics;

  @override
  Future<GroupCollectionPage<GroupSummary>> listGroups({
    int limit = 100,
    String? cursor,
  }) async {
    try {
      final result = await delegate.listGroups(limit: limit, cursor: cursor);
      diagnostics.record('', 'list_groups', {
        'outcome': 'returned',
        'count': result.items.length,
        'has_more': result.hasMore,
      });
      return result;
    } catch (error) {
      diagnostics.failure('', 'list_groups', error);
      rethrow;
    }
  }

  @override
  Future<GroupSummary> getGroup(String groupDid) async {
    try {
      final result = await delegate.getGroup(groupDid);
      diagnostics.record(groupDid, 'get_group', {
        'outcome': 'returned',
        'encrypted': result.encrypted,
      });
      return result;
    } catch (error) {
      diagnostics.failure(groupDid, 'get_group', error);
      rethrow;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final methods = <Symbol, Function>{
      #createGroup: delegate.createGroup,
      #joinGroup: delegate.joinGroup,
      #listMembers: delegate.listMembers,
      #listMessages: delegate.listMessages,
      #leaveGroup: delegate.leaveGroup,
      #addMember: delegate.addMember,
      #removeMember: delegate.removeMember,
    };
    final method = methods[invocation.memberName];
    if (method == null) throw StateError('unexpected_group_diagnostic_method');
    return Function.apply(
      method,
      invocation.positionalArguments,
      invocation.namedArguments,
    );
  }
}

class Step4ObservedEncryption implements GroupEncryptionCorePort {
  Step4ObservedEncryption(this.delegate, this.diagnostics);
  final GroupEncryptionCorePort delegate;
  final Step4GroupDiagnostics diagnostics;

  Future<GroupEncryptionStatus> _call(
    String group,
    String action,
    Future<GroupEncryptionStatus> Function() invoke,
  ) async {
    try {
      final result = await invoke();
      diagnostics.record(group, action, {
        'outcome': 'returned',
        'readiness': result.readiness.name,
        'can_send': result.canSendSecure,
      });
      return result;
    } catch (error) {
      diagnostics.failure(group, action, error);
      rethrow;
    }
  }

  @override
  Future<GroupEncryptionStatus> status(String groupDid) =>
      _call(groupDid, 'status', () => delegate.status(groupDid));
  @override
  Future<GroupEncryptionStatus> retry(String groupDid) =>
      _call(groupDid, 'repair', () => delegate.retry(groupDid));
}
