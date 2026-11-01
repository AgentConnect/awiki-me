import 'dart:convert';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/group_application_service.dart';
import 'package:awiki_me/src/application/models/group_collection_page.dart';
import 'package:awiki_me/src/application/ports/group_encryption_core_port.dart';
import 'package:awiki_me/src/domain/entities/group_encryption_status.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/step4_group_diagnostics.dart';

const group = GroupSummary(
  conversationId: 'conversation',
  groupId: 'private-group-identifier',
  description: 'private-content',
  memberCount: 1,
  lastMessageAt: null,
  encrypted: false,
);

class Groups extends Fake implements GroupApplicationService {
  Object? error;
  @override
  Future<GroupSummary> getGroup(String groupDid) async {
    if (error != null) throw error!;
    return group;
  }

  @override
  Future<void> leaveGroup(String groupDid) async {
    if (groupDid != group.groupId) throw StateError('wrong delegated argument');
  }

  @override
  Future<GroupCollectionPage<GroupSummary>> listGroups({
    int limit = 100,
    String? cursor,
  }) async => GroupCollectionPage(items: [group], hasMore: false);
}

class Encryption extends Fake implements GroupEncryptionCorePort {
  final result = const GroupEncryptionStatus(
    groupDid: 'private-group-identifier',
    readiness: GroupEncryptionReadiness.ready,
    canSendSecure: true,
    retryable: false,
  );
  Object? error;
  @override
  Future<GroupEncryptionStatus> status(String groupDid) async => result;
  @override
  Future<GroupEncryptionStatus> retry(String groupDid) async {
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  test(
    'group reads preserve results and omit identifiers and content',
    () async {
      final diagnostics = Step4GroupDiagnostics();
      final delegate = Groups();
      final port = Step4ObservedGroups(delegate, diagnostics);
      expect(await port.getGroup(group.groupId), same(group));
      await port.leaveGroup(group.groupId);
      expect((await port.listGroups(limit: 1)).items.single, same(group));
      final value = jsonEncode(diagnostics.summary(group.groupId));
      expect(value, contains('"encrypted":false'));
      expect(value, isNot(contains(group.groupId)));
      expect(value, isNot(contains(group.description)));
    },
  );
  test(
    'errors are rethrown unchanged and only stable codes are recorded',
    () async {
      const error = core.AwikiImCoreException(
        code: 'service_error',
        serviceCode: 'group.local_cursor_stale',
        message: 'Bearer private-token',
      );
      final diagnostics = Step4GroupDiagnostics();
      final delegate = Groups()..error = error;
      final port = Step4ObservedGroups(delegate, diagnostics);
      await expectLater(port.getGroup(group.groupId), throwsA(same(error)));
      final value = jsonEncode(diagnostics.summary(group.groupId));
      expect(value, contains('group.local_cursor_stale'));
      expect(value, isNot(contains('private-token')));
    },
  );
  test(
    'encryption forwarding is passive and repeated status is deduplicated',
    () async {
      final diagnostics = Step4GroupDiagnostics();
      final delegate = Encryption();
      final port = Step4ObservedEncryption(delegate, diagnostics);
      for (var i = 0; i < 5; i++) {
        expect(await port.status(group.groupId), same(delegate.result));
      }
      expect(diagnostics.summary(group.groupId), hasLength(1));
      expect(await port.retry(group.groupId), same(delegate.result));
      final error = StateError('private-message');
      delegate.error = error;
      await expectLater(port.retry(group.groupId), throwsA(same(error)));
      expect(
        jsonEncode(diagnostics.summary(group.groupId)),
        isNot(contains('private-message')),
      );
    },
  );
  test('retained evidence is bounded', () async {
    final diagnostics = Step4GroupDiagnostics();
    final port = Step4ObservedGroups(Groups(), diagnostics);
    for (var i = 0; i < 100; i++) {
      await port.getGroup(group.groupId);
    }
    expect(diagnostics.summary(group.groupId), hasLength(32));
    expect(diagnostics.droppedEvents, 68);
  });
}
