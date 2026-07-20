import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/ports/group_encryption_core_port.dart';
import 'package:awiki_me/src/domain/entities/group_encryption_status.dart';
import 'package:awiki_me/src/presentation/group/group_encryption_provider.dart';
import 'package:awiki_me/src/presentation/group/group_encryption_status_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  const groupDid = 'did:wba:awiki.info:group:e1_group';

  testWidgets('default-off gate hides status and does not call Core', (
    tester,
  ) async {
    final port = _FakeGroupEncryptionPort(
      status: _status(GroupEncryptionReadiness.ready),
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const GroupEncryptionStatusCard(groupDid: groupDid),
        providerOverrides: <Override>[
          multiDeviceGroupE2eeEnabledProvider.overrideWithValue(false),
          groupEncryptionCorePortProvider.overrideWithValue(port),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('group-encryption-status-card')), findsNothing);
    expect(port.statusCalls, 0);
  });

  testWidgets('shows preparing and ready without MLS private details', (
    tester,
  ) async {
    final port = _FakeGroupEncryptionPort(
      status: _status(GroupEncryptionReadiness.preparing),
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const CupertinoPageScaffold(
          child: GroupEncryptionStatusCard(groupDid: groupDid),
        ),
        providerOverrides: <Override>[
          multiDeviceGroupE2eeEnabledProvider.overrideWithValue(true),
          groupEncryptionCorePortProvider.overrideWithValue(port),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('正在加入群加密'), findsOneWidget);
    expect(find.textContaining('Leaf'), findsNothing);
    expect(find.textContaining('私钥'), findsNothing);
    expect(
      find.byKey(const Key('group-encryption-retry-button')),
      findsNothing,
    );

    port.nextStatus = _status(GroupEncryptionReadiness.ready);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GroupEncryptionStatusCard)),
    );
    await container.read(groupEncryptionProvider(groupDid).notifier).load();
    await tester.pumpAndSettle();

    expect(find.text('群加密已就绪'), findsOneWidget);
  });

  testWidgets('retry action projects only the refreshed ready state', (
    tester,
  ) async {
    final port = _FakeGroupEncryptionPort(
      status: _status(GroupEncryptionReadiness.needsRetry),
      retryResult: _status(GroupEncryptionReadiness.ready),
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const CupertinoPageScaffold(
          child: GroupEncryptionStatusCard(groupDid: groupDid),
        ),
        providerOverrides: <Override>[
          multiDeviceGroupE2eeEnabledProvider.overrideWithValue(true),
          groupEncryptionCorePortProvider.overrideWithValue(port),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('群加密需要重试'), findsOneWidget);
    await tester.tap(find.byKey(const Key('group-encryption-retry-button')));
    await tester.pumpAndSettle();

    expect(port.retryCalls, 1);
    expect(find.text('群加密已就绪'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

GroupEncryptionStatus _status(GroupEncryptionReadiness readiness) =>
    GroupEncryptionStatus(
      groupDid: 'did:wba:awiki.info:group:e1_group',
      readiness: readiness,
      canSendSecure: readiness == GroupEncryptionReadiness.ready,
      retryable: readiness == GroupEncryptionReadiness.needsRetry,
    );

class _FakeGroupEncryptionPort implements GroupEncryptionCorePort {
  _FakeGroupEncryptionPort({
    required GroupEncryptionStatus status,
    this.retryResult,
  }) : currentStatus = status;

  GroupEncryptionStatus currentStatus;
  GroupEncryptionStatus? retryResult;
  GroupEncryptionStatus? nextStatus;
  int statusCalls = 0;
  int retryCalls = 0;

  @override
  Future<GroupEncryptionStatus> retry(String groupDid) async {
    retryCalls += 1;
    return retryResult ?? currentStatus;
  }

  @override
  Future<GroupEncryptionStatus> status(String groupDid) async {
    statusCalls += 1;
    final next = nextStatus;
    if (next != null) {
      nextStatus = null;
      currentStatus = next;
    }
    return currentStatus;
  }
}
