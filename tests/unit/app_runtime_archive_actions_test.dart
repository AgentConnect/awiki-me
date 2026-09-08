import 'dart:async';

import 'package:awiki_me/src/application/models/conversation_patch.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/friends/friends_navigation_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  group('AppRuntime archive actions', () {
    late FakeAwikiGateway gateway;
    late FakeProductLocalStore productLocalStore;
    late ProviderContainer container;

    setUp(() {
      gateway = FakeAwikiGateway();
      productLocalStore = FakeProductLocalStore();
      container = ProviderContainer(
        overrides: <Override>[
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            productLocalStore: productLocalStore,
          ),
          realtimeGatewayProvider.overrideWithValue(FakeRealtimeGateway()),
          notificationFacadeProvider.overrideWithValue(
            FakeNotificationFacade(),
          ),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      addTearDown(container.dispose);
    });

    test('导入本地凭证显示暂未实现普通提示', () async {
      gateway.importedCredential = const SessionIdentity(
        did: 'did:test:123',
        credentialName: 'default',
        displayName: 'Alice',
        handle: 'alice',
        jwtToken: 'token-123',
      );
      gateway.localCredentials = <SessionIdentity>[gateway.importedCredential!];

      await container
          .read(appRuntimeProvider.notifier)
          .importCredentialArchive();

      expect(gateway.importCalls, 0);
      expect(container.read(sessionProvider).localCredentials, isEmpty);
      final feedback = container.read(uiFeedbackProvider);
      expect(feedback?.danger, isFalse);
      expect(feedback?.message.id, 'featureNotImplemented');
    });

    test('导出本地凭证显示暂未实现普通提示', () async {
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:test:123',
              credentialName: 'default',
              displayName: 'Alice',
              handle: 'alice',
              jwtToken: 'token-123',
            ),
          );
      gateway.exportedPath = '/tmp/awiki-credential-alice-default.zip';

      await container
          .read(appRuntimeProvider.notifier)
          .exportCurrentCredential();

      expect(gateway.exportCalls, 0);
      expect(container.read(uiFeedbackProvider)?.danger, isFalse);
      expect(
        container.read(uiFeedbackProvider)?.message.id,
        'featureNotImplemented',
      );
    });

    test('注销当前凭证会删除本地凭证并清空当前会话', () async {
      const session = SessionIdentity(
        did: 'did:test:123',
        credentialName: 'default',
        displayName: 'Alice',
        handle: 'alice',
        jwtToken: 'token-123',
      );
      gateway.localCredentials = const <SessionIdentity>[session];
      container.read(sessionProvider.notifier).setSession(session);
      container.read(sessionProvider.notifier).setLocalCredentials([session]);
      container
          .read(friendsWorkspaceNavigationProvider.notifier)
          .showProfileDid('did:test:stale-contact');

      await container
          .read(appRuntimeProvider.notifier)
          .deleteCurrentCredential();

      expect(gateway.deleteLocalCredentialCalls, 1);
      expect(gateway.logoutCalls, 0);
      expect(container.read(sessionProvider).session, isNull);
      expect(container.read(sessionProvider).localCredentials, isEmpty);
      expect(container.read(uiFeedbackProvider), isNull);
      final friendsNavigation = container.read(
        friendsWorkspaceNavigationProvider,
      );
      expect(friendsNavigation.detail, FriendsWorkspaceDetail.overview);
      expect(friendsNavigation.selectedDid, isNull);
    });

    test('退出并删除当前数据按稳定身份清理 App 和 Core 本地数据', () async {
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:users:alice-current',
        localIdentityId: 'identity-alice',
        credentialName: 'alice-local',
        displayName: 'Alice',
        handle: 'alice.awiki.info',
        jwtToken: 'token-alice',
      );
      gateway.localCredentials = const <SessionIdentity>[session];
      container.read(sessionProvider.notifier).setSession(session);
      container.read(sessionProvider.notifier).setLocalCredentials([session]);

      await container.read(appRuntimeProvider.notifier).deleteCurrentData();

      expect(productLocalStore.deleteOwnerDataCalls, 1);
      expect(productLocalStore.lastDeletedOwnerIdentityId, 'identity-alice');
      expect(
        productLocalStore.lastDeletedOwnerDid,
        'did:wba:awiki.info:users:alice-current',
      );
      expect(gateway.lastDeletedLocalCredentialSelector, 'identity-alice');
      expect(gateway.deleteLocalIdentityDataCalls, 1);
      expect(gateway.prepareLocalIdentityDataDeletionCalls, 1);
      expect(gateway.completeLocalIdentityDataDeletionCalls, 1);
      expect(container.read(sessionProvider).session, isNull);
      expect(container.read(sessionProvider).localCredentials, isEmpty);
      expect(container.read(uiFeedbackProvider), isNull);
    });

    test('恢复已切换 DID 时按删除单的权威范围清理当前数据', () async {
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:users:alice-old',
        localIdentityId: 'identity-alice',
        credentialName: 'alice-local',
        displayName: 'Alice',
        handle: 'alice.awiki.info',
      );
      const ticket = LocalIdentityDeletionTicket(
        deletionId: 'delete-after-recovery',
        ownerIdentityId: 'identity-alice',
        currentDid: 'did:wba:awiki.info:users:alice-new',
      );
      gateway.localCredentials = [session];
      gateway.pendingLocalIdentityDeletionTickets.add(ticket);
      container.read(sessionProvider.notifier).setSession(session);
      container.read(sessionProvider.notifier).setLocalCredentials([session]);

      await container.read(appRuntimeProvider.notifier).deleteCurrentData();

      expect(
        productLocalStore.lastDeletedOwnerIdentityId,
        ticket.ownerIdentityId,
      );
      expect(productLocalStore.lastDeletedOwnerDid, ticket.currentDid);
      expect(gateway.completeLocalIdentityDataDeletionCalls, 1);
      expect(container.read(sessionProvider).session, isNull);
      expect(container.read(uiFeedbackProvider), isNull);
    });

    test('退出并删除当前数据在运行时销毁后仍完成已确认的本地删除', () async {
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:users:alice-dispose',
        localIdentityId: 'identity-alice-dispose',
        credentialName: 'alice-dispose',
        displayName: 'Alice',
        handle: 'alice.awiki.info',
        jwtToken: 'token-alice',
      );
      final deferredStore = _DeferredDeleteProductLocalStore();
      final isolatedContainer = ProviderContainer(
        overrides: <Override>[
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            productLocalStore: deferredStore,
          ),
          realtimeGatewayProvider.overrideWithValue(FakeRealtimeGateway()),
          notificationFacadeProvider.overrideWithValue(
            FakeNotificationFacade(),
          ),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      var disposed = false;
      addTearDown(() {
        if (!disposed) isolatedContainer.dispose();
      });
      gateway.localCredentials = const <SessionIdentity>[session];
      isolatedContainer.read(sessionProvider.notifier).setSession(session);
      isolatedContainer.read(sessionProvider.notifier).setLocalCredentials([
        session,
      ]);

      final deletion = isolatedContainer
          .read(appRuntimeProvider.notifier)
          .deleteCurrentData();
      await deferredStore.deleteStarted.future;
      expect(gateway.prepareLocalIdentityDataDeletionCalls, 1);
      expect(gateway.completeLocalIdentityDataDeletionCalls, 0);
      isolatedContainer.dispose();
      disposed = true;
      deferredStore.allowDelete.complete();

      await expectLater(deletion, completes);
      expect(deferredStore.deleteOwnerDataCalls, 1);
      expect(gateway.deleteLocalIdentityDataCalls, 1);
      expect(gateway.completeLocalIdentityDataDeletionCalls, 1);
    });

    test('Core 删除准备失败时不修改 App 产品数据或当前会话', () async {
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:users:alice-guarded',
        localIdentityId: 'identity-alice-guarded',
        credentialName: 'alice-guarded',
        displayName: 'Alice',
        handle: 'alice.awiki.info',
        jwtToken: 'token-alice',
      );
      gateway.localCredentials = const <SessionIdentity>[session];
      gateway.prepareLocalIdentityDataDeletionError = StateError(
        'identity.local_deletion_conflict',
      );
      container.read(sessionProvider.notifier).setSession(session);
      container.read(sessionProvider.notifier).setLocalCredentials([session]);

      await container.read(appRuntimeProvider.notifier).deleteCurrentData();

      expect(gateway.prepareLocalIdentityDataDeletionCalls, 1);
      expect(gateway.completeLocalIdentityDataDeletionCalls, 0);
      expect(productLocalStore.deleteOwnerDataCalls, 0);
      expect(container.read(sessionProvider).session, session);
      expect(gateway.localCredentials, const <SessionIdentity>[session]);
      expect(container.read(uiFeedbackProvider), isNotNull);
    });

    test('启动时优先重放未完成删除单并幂等清理产品数据', () async {
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:users:alice-resume',
        localIdentityId: 'identity-alice-resume',
        credentialName: 'alice-resume',
        displayName: 'Alice',
        handle: 'alice.awiki.info',
        jwtToken: 'token-alice',
      );
      gateway.localCredentials = const <SessionIdentity>[session];
      gateway.pendingLocalIdentityDeletionTickets.add(
        const LocalIdentityDeletionTicket(
          deletionId: 'delete-resume-1',
          ownerIdentityId: 'identity-alice-resume',
          currentDid: 'did:wba:awiki.info:users:alice-resume',
        ),
      );

      await container.read(appRuntimeProvider.notifier).initialize();

      expect(productLocalStore.deleteOwnerDataCalls, 1);
      expect(gateway.completeLocalIdentityDataDeletionCalls, 1);
      expect(gateway.pendingLocalIdentityDeletionTickets, isEmpty);
      expect(gateway.localCredentials, isEmpty);
      expect(container.read(sessionProvider).localCredentials, isEmpty);
    });

    test('启动续跑时 Product 删除失败显示稳定 pending 状态并保留 ticket', () async {
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:users:alice-bootstrap-product-failure',
        localIdentityId: 'identity-alice-bootstrap-product-failure',
        credentialName: 'alice-bootstrap-product-failure',
        displayName: 'Alice',
        handle: 'alice.awiki.info',
        jwtToken: 'token-alice',
      );
      final failOnceStore = _FailOnceDeleteProductLocalStore();
      final isolatedContainer = ProviderContainer(
        overrides: <Override>[
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            productLocalStore: failOnceStore,
          ),
          realtimeGatewayProvider.overrideWithValue(FakeRealtimeGateway()),
          notificationFacadeProvider.overrideWithValue(
            FakeNotificationFacade(),
          ),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      addTearDown(isolatedContainer.dispose);
      gateway.localCredentials = const <SessionIdentity>[session];
      gateway.pendingLocalIdentityDeletionTickets.add(
        const LocalIdentityDeletionTicket(
          deletionId: 'delete-bootstrap-product-failure-1',
          ownerIdentityId: 'identity-alice-bootstrap-product-failure',
          currentDid:
              'did:wba:awiki.info:users:alice-bootstrap-product-failure',
        ),
      );

      await isolatedContainer.read(appRuntimeProvider.notifier).initialize();

      expect(failOnceStore.deleteAttempts, 1);
      expect(gateway.completeLocalIdentityDataDeletionCalls, 0);
      expect(gateway.pendingLocalIdentityDeletionTickets, hasLength(1));
      expect(
        isolatedContainer.read(uiFeedbackProvider)?.message.id,
        'identityDeletionPendingWillResume',
      );
      expect(isolatedContainer.read(sessionProvider).session, isNull);
    });

    test('Product 删除失败保留同一 ticket，重试后才调用 Core complete', () async {
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:users:alice-product-retry',
        localIdentityId: 'identity-alice-product-retry',
        credentialName: 'alice-product-retry',
        displayName: 'Alice',
        handle: 'alice.awiki.info',
        jwtToken: 'token-alice',
      );
      final failOnceStore = _FailOnceDeleteProductLocalStore();
      final isolatedContainer = ProviderContainer(
        overrides: <Override>[
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            productLocalStore: failOnceStore,
          ),
          realtimeGatewayProvider.overrideWithValue(FakeRealtimeGateway()),
          notificationFacadeProvider.overrideWithValue(
            FakeNotificationFacade(),
          ),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      addTearDown(isolatedContainer.dispose);
      gateway.localCredentials = const <SessionIdentity>[session];
      isolatedContainer.read(sessionProvider.notifier).setSession(session);
      isolatedContainer.read(sessionProvider.notifier).setLocalCredentials([
        session,
      ]);

      await isolatedContainer
          .read(appRuntimeProvider.notifier)
          .deleteCurrentData();
      expect(gateway.prepareLocalIdentityDataDeletionCalls, 1);
      expect(gateway.completeLocalIdentityDataDeletionCalls, 0);
      expect(gateway.pendingLocalIdentityDeletionTickets, hasLength(1));
      final firstDeletionId =
          gateway.pendingLocalIdentityDeletionTickets.single.deletionId;
      expect(isolatedContainer.read(sessionProvider).session, session);
      expect(
        isolatedContainer.read(uiFeedbackProvider)?.message.id,
        'identityDeletionPendingWillResume',
      );

      await isolatedContainer
          .read(appRuntimeProvider.notifier)
          .deleteCurrentData();
      expect(gateway.prepareLocalIdentityDataDeletionCalls, 2);
      expect(gateway.completeLocalIdentityDataDeletionCalls, 1);
      expect(gateway.deleteLocalIdentityDataCalls, 1);
      expect(gateway.pendingLocalIdentityDeletionTickets, isEmpty);
      expect(firstDeletionId, 'delete-1');
      expect(failOnceStore.deleteAttempts, 2);
      expect(failOnceStore.deleteOwnerDataCalls, 1);
      expect(isolatedContainer.read(sessionProvider).session, isNull);
    });

    test('会话 Patch 取消挂起时仍会删除本地凭证', () async {
      const session = SessionIdentity(
        did: 'did:test:123',
        credentialName: 'default',
        displayName: 'Alice',
        handle: 'alice',
        jwtToken: 'token-123',
      );
      final hangingConversationService = _HangingCancelConversationService(
        gateway,
      );
      final isolatedContainer = ProviderContainer(
        overrides: <Override>[
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            conversationService: hangingConversationService,
          ),
          realtimeGatewayProvider.overrideWithValue(FakeRealtimeGateway()),
          notificationFacadeProvider.overrideWithValue(
            FakeNotificationFacade(),
          ),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      addTearDown(isolatedContainer.dispose);
      gateway.localCredentials = const <SessionIdentity>[session];
      isolatedContainer.read(sessionProvider.notifier).setSession(session);
      isolatedContainer.read(sessionProvider.notifier).setLocalCredentials([
        session,
      ]);
      await isolatedContainer
          .read(conversationListProvider.notifier)
          .refreshFastLocal();

      await isolatedContainer
          .read(appRuntimeProvider.notifier)
          .deleteCurrentCredential()
          .timeout(const Duration(seconds: 1));

      expect(hangingConversationService.cancelStarted.isCompleted, isTrue);
      expect(gateway.deleteLocalCredentialCalls, 1);
      expect(isolatedContainer.read(sessionProvider).session, isNull);
      expect(isolatedContainer.read(appRuntimeProvider).isBusy, isFalse);
    });

    test('删除非当前本地身份使用稳定 ID 且保留当前会话', () async {
      const current = SessionIdentity(
        did: 'did:test:alice',
        localIdentityId: 'identity-alice',
        credentialName: 'alice-local',
        displayName: 'Alice',
        handle: 'alice',
        jwtToken: 'token-alice',
      );
      const other = SessionIdentity(
        did: 'did:test:bob',
        localIdentityId: 'identity-bob',
        credentialName: 'bob-local',
        displayName: 'Bob',
        handle: 'bob',
        jwtToken: 'token-bob',
      );
      gateway.localCredentials = const <SessionIdentity>[current, other];
      container.read(sessionProvider.notifier).setSession(current);
      container.read(sessionProvider.notifier).setLocalCredentials([
        current,
        other,
      ]);

      final deleted = await container
          .read(appRuntimeProvider.notifier)
          .deleteLocalCredential(other);

      expect(deleted, isTrue);
      expect(gateway.lastDeletedLocalCredentialSelector, 'identity-bob');
      expect(container.read(sessionProvider).session?.did, current.did);
      expect(
        container
            .read(sessionProvider)
            .localCredentials
            .map((identity) => identity.localIdentityId),
        <String?>['identity-alice'],
      );
      expect(gateway.logoutCalls, 0);
      expect(container.read(uiFeedbackProvider), isNull);
    });

    test('重新识别本地凭证会刷新列表并写入反馈', () async {
      gateway.localCredentials = const <SessionIdentity>[
        SessionIdentity(
          did: 'did:test:123',
          credentialName: 'default',
          displayName: 'Alice',
          handle: 'alice',
          jwtToken: 'token-123',
        ),
      ];
      await container.read(appRuntimeProvider.notifier).initialize();
      expect(gateway.listLocalCredentialsCalls, 1);

      gateway.localCredentials = const <SessionIdentity>[
        SessionIdentity(
          did: 'did:test:456',
          credentialName: 'bob',
          displayName: 'Bob',
          handle: 'bob',
          jwtToken: 'token-456',
        ),
      ];

      await container
          .read(appRuntimeProvider.notifier)
          .refreshLocalCredentials();

      expect(gateway.listLocalCredentialsCalls, 2);
      expect(
        container.read(sessionProvider).localCredentials.single.credentialName,
        'bob',
      );
      expect(
        container.read(uiFeedbackProvider)?.message.id,
        'localCredentialsRefreshed',
      );
      expect(container.read(uiFeedbackProvider)?.message.value, '1');
    });
  });
}

class _HangingCancelConversationService extends FakeConversationService {
  _HangingCancelConversationService(super.gateway) {
    _controller = StreamController<ConversationListPatch>(
      onCancel: () {
        if (!cancelStarted.isCompleted) {
          cancelStarted.complete();
        }
        return _neverCancelled.future;
      },
    );
  }

  final Completer<void> cancelStarted = Completer<void>();
  final Completer<void> _neverCancelled = Completer<void>();
  late final StreamController<ConversationListPatch> _controller;

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) {
    return _controller.stream;
  }
}

class _DeferredDeleteProductLocalStore extends FakeProductLocalStore {
  final Completer<void> deleteStarted = Completer<void>();
  final Completer<void> allowDelete = Completer<void>();

  @override
  Future<void> deleteOwnerData({
    required String ownerIdentityId,
    required String currentDid,
  }) async {
    deleteStarted.complete();
    await allowDelete.future;
    await super.deleteOwnerData(
      ownerIdentityId: ownerIdentityId,
      currentDid: currentDid,
    );
  }
}

class _FailOnceDeleteProductLocalStore extends FakeProductLocalStore {
  int deleteAttempts = 0;

  @override
  Future<void> deleteOwnerData({
    required String ownerIdentityId,
    required String currentDid,
  }) async {
    deleteAttempts += 1;
    if (deleteAttempts == 1) {
      throw StateError('injected_product_delete_failure');
    }
    await super.deleteOwnerData(
      ownerIdentityId: ownerIdentityId,
      currentDid: currentDid,
    );
  }
}
