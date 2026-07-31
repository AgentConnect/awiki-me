# Android EMAS Direct-Message MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the Android Aliyun EMAS loop for incoming one-to-one AWiki messages, including ordinary one-to-one Coding Agent replies, from authenticated installation registration through reliable Core sync, exact-once presentation, pending-event acknowledgement, and safe notification-open routing.

**Architecture:** Keep EMAS as an App-owned wake-up and presentation transport. A bootstrap-owned installation coordinator binds the provider DeviceId and Android AppKey to the active authenticated session through User Service. A session-fenced remote-push coordinator sends accepted callbacks through the existing `MessageSyncCoordinator`; Core remains the sole message/conversation fact source. Remote-push sync records committed identities but suppresses a second App notification, and notification opening resolves only an opaque message reference after Core commit.

**Tech Stack:** Flutter 3.41+, Dart 3.8+, Riverpod, Android Kotlin MethodChannel, Aliyun EMAS Push 3.10.1, authenticated User Service JSON-RPC, `crypto` SHA-256, `flutter_test`, awiki-system-test pytest.

## Global Constraints

- Work in `/Users/howard/ANP-Workspace/Feature/awiki-me-android-emas-mvp` on `codex/android-emas-mvp`.
- Keep `/Users/howard/ANP-Workspace/Feature/awiki-me`, PR #3, `/Users/howard/ANP-Workspace/awiki-me-ios-push-mvp`, and the existing uncommitted `macos/Podfile.lock` untouched.
- Follow strict red-green-refactor. Run each focused test once before implementation and confirm that it fails for the expected missing behavior.
- Android platform files and strictly required shared Dart files are in scope. Do not change iOS, macOS, Windows, web, generated registrants, Rust IM Core, Pod metadata, signing, or bundle identifiers.
- Push payloads are dirty hints. They must never write conversation rows, timelines, unread state, or message bodies directly.
- Never log or persist a full EMAS DeviceId, AppSecret, notification body, DID, bearer token, RAM credential, raw conversation ID, or raw message ID.
- `RemotePushRegistration.logicalDeviceId` may carry the current protocol device ID as optional User Service metadata. It must never replace EMAS `providerDeviceId` or become an App installation identity.
- Every async installation, sync, acknowledgement, and navigation result must be fenced by tenant storage scope plus current `SessionEpoch`.
- A pending native delivery ID is acknowledged only after Core sync and App projection refresh succeed for the same session. Retryable, recovery-required, auth-revoked, stale, or thrown outcomes retain it.
- EMAS `NOTICE` owns Android system presentation. A remote-push-triggered sync records message identities in the existing deduplication ledgers but does not create a second App banner/system notification.
- Commit, push, PR creation, deployment, credentials, EMAS console sends, and physical-device provider tests remain separate actions.
- Before editing tests, read `/Users/howard/.codex/plugins/cache/openai-curated-remote/superpowers/6.2.0/skills/test-driven-development/writing-good-tests.md` completely.

---

## Task 1: Expose the Android EMAS AppKey in the provider registration

**Files:**

- Modify: `lib/src/domain/services/remote_push_client.dart`
- Modify: `lib/src/data/push/aliyun_emas_platform.dart`
- Modify: `lib/src/data/push/aliyun_emas_remote_push_client.dart`
- Modify: `android/app/src/main/kotlin/ai/awiki/awikime/push/RemotePushEventBridge.kt`
- Test: `tests/unit/data/push/aliyun_emas_remote_push_client_test.dart`
- Test: `tests/unit/data/push/android_remote_push_configuration_test.dart`

- [ ] **Step 1: Add failing Dart registration tests**

  Extend `_FakeAliyunEmasPlatform` with an `appId` field and `getAppId()`. Assert:

  ```dart
  expect(first?.appId, '12345678');
  expect(first?.logicalDeviceId, isNull);
  ```

  Add a failure case proving an enabled Android registration rejects an empty AppKey with:

  ```dart
  RemotePushInitializationException(
    operation: 'get_app_id',
    code: 'empty_app_id',
  )
  ```

  Keep the existing iOS shared-client test green by asserting `registration?.appId` is null and that `getAppId()` is not called for `clientPlatform == 'ios'`.

- [ ] **Step 2: Add a failing native configuration assertion**

  In `android_remote_push_configuration_test.dart`, assert that the Kotlin bridge:

  ```dart
  expect(bridge, contains('"getAppId"'));
  expect(bridge, contains('BuildConfig.AWIKI_EMAS_APP_KEY'));
  expect(bridge, isNot(contains('"getAppSecret"')));
  ```

- [ ] **Step 3: Run the focused tests and confirm RED**

  Run:

  ```bash
  flutter test \
    tests/unit/data/push/aliyun_emas_remote_push_client_test.dart \
    tests/unit/data/push/android_remote_push_configuration_test.dart
  ```

  Expected failure: `RemotePushRegistration.appId`, `AliyunEmasPlatform.getAppId`, and the native method are absent.

- [ ] **Step 4: Implement the minimal shared registration contract**

  Change the value object to:

  ```dart
  class RemotePushRegistration {
    const RemotePushRegistration({
      required this.provider,
      required this.providerDeviceId,
      required this.platform,
      this.appId,
      this.logicalDeviceId,
    });

    final String provider;
    final String providerDeviceId;
    final String platform;
    final String? appId;
    final String? logicalDeviceId;

    RemotePushRegistration withLogicalDeviceId(String? value) {
      final normalized = value?.trim();
      return RemotePushRegistration(
        provider: provider,
        providerDeviceId: providerDeviceId,
        platform: platform,
        appId: appId,
        logicalDeviceId:
            normalized == null || normalized.isEmpty ? null : normalized,
      );
    }
  }
  ```

  Add `Future<String> getAppId()` to `AliyunEmasPlatform` and its MethodChannel implementation.

  In `AliyunEmasRemotePushClient`, read and require a non-empty AppKey only for Android. Preserve the AppKey when `_refreshRegistration()` handles `registration_changed`.

- [ ] **Step 5: Implement the Android bridge method**

  Add:

  ```kotlin
  "getAppId" -> result.success(
      if (ai.awiki.awikime.BuildConfig.AWIKI_EMAS_ENABLED) {
          ai.awiki.awikime.BuildConfig.AWIKI_EMAS_APP_KEY
      } else {
          ""
      },
  )
  ```

  Do not add any method or diagnostic that returns `AWIKI_EMAS_APP_SECRET`.

- [ ] **Step 6: Run focused tests and confirm GREEN**

  Run the command from Step 3. Confirm both files pass without changing another platform.

- [ ] **Step 7: Commit**

  ```bash
  git add \
    lib/src/domain/services/remote_push_client.dart \
    lib/src/data/push/aliyun_emas_platform.dart \
    lib/src/data/push/aliyun_emas_remote_push_client.dart \
    android/app/src/main/kotlin/ai/awiki/awikime/push/RemotePushEventBridge.kt \
    tests/unit/data/push/aliyun_emas_remote_push_client_test.dart \
    tests/unit/data/push/android_remote_push_configuration_test.dart
  git commit -m "feat: expose Android EMAS registration metadata"
  ```

---

## Task 2: Add the authenticated User Service installation adapter

**Files:**

- Create: `lib/src/application/models/push_installation.dart`
- Create: `lib/src/application/ports/push_installation_port.dart`
- Create: `lib/src/data/push/user_service_push_installation_adapter.dart`
- Create: `tests/unit/data/push/user_service_push_installation_adapter_test.dart`

- [ ] **Step 1: Write failing adapter contract tests**

  Cover these exact requests:

  ```text
  POST /user-service/push/rpc
  method upsert_installation
  params provider, provider_device_id, platform, logical_device_id, app_id

  POST /user-service/push/rpc
  method disable_installation
  params installation_id
  ```

  Assert that the adapter:

  - uses `AuthenticatedUserServiceRpcClient`;
  - sends Android `app_id` and the optional protocol `logical_device_id`;
  - returns the exact server `installation_id`;
  - rejects a response whose provider, DeviceId, platform, AppKey, or status does not match the request;
  - rejects a missing authenticated client instead of falling back to an unauthenticated request; and
  - never includes an AppSecret or bearer token in params.

- [ ] **Step 2: Run the new test and confirm RED**

  ```bash
  flutter test tests/unit/data/push/user_service_push_installation_adapter_test.dart
  ```

  Expected failure: the model, port, and adapter do not exist.

- [ ] **Step 3: Add the application model and port**

  Use this narrow contract:

  ```dart
  final class PushInstallation {
    const PushInstallation({
      required this.installationId,
      required this.provider,
      required this.providerDeviceId,
      required this.platform,
      required this.status,
      this.logicalDeviceId,
      this.appId,
    });

    final String installationId;
    final String provider;
    final String providerDeviceId;
    final String platform;
    final String status;
    final String? logicalDeviceId;
    final String? appId;
  }

  abstract interface class PushInstallationPort {
    Future<PushInstallation> upsert(RemotePushRegistration registration);
    Future<PushInstallation> disable(String installationId);
  }
  ```

- [ ] **Step 4: Implement the authenticated adapter**

  Follow the existing User Service adapter shape:

  ```dart
  class UserServicePushInstallationAdapter implements PushInstallationPort {
    static const endpoint = '/user-service/push/rpc';

    UserServicePushInstallationAdapter({
      required String userServiceUrl,
      AwikiOnboardingUtilityHttpClient? client,
      AuthenticatedUserServiceRpcClient? authenticatedClient,
    });

    UserServicePushInstallationAdapter withAuthenticatedClient(
      AuthenticatedUserServiceRpcClient authenticatedClient,
    );
  }
  ```

  `upsert()` must send:

  ```dart
  <String, Object?>{
    'provider': registration.provider,
    'provider_device_id': registration.providerDeviceId,
    'platform': registration.platform,
    if (registration.logicalDeviceId != null)
      'logical_device_id': registration.logicalDeviceId,
    if (registration.appId != null) 'app_id': registration.appId,
  }
  ```

  Parse only the safe installation fields needed by the App. Require `status == 'active'` for upsert and `status == 'disabled'` for disable.

- [ ] **Step 5: Run focused tests and confirm GREEN**

  ```bash
  flutter test tests/unit/data/push/user_service_push_installation_adapter_test.dart
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add \
    lib/src/application/models/push_installation.dart \
    lib/src/application/ports/push_installation_port.dart \
    lib/src/data/push/user_service_push_installation_adapter.dart \
    tests/unit/data/push/user_service_push_installation_adapter_test.dart
  git commit -m "feat: add authenticated push installation adapter"
  ```

---

## Task 3: Implement the serialized installation lifecycle coordinator

**Files:**

- Create: `lib/src/application/remote_push_installation_coordinator.dart`
- Create: `tests/unit/application/remote_push_installation_coordinator_test.dart`

- [ ] **Step 1: Write failing lifecycle tests**

  Use fake `RemotePushClient` and `PushInstallationPort` implementations. Cover:

  - first bind initializes Push and upserts once;
  - rebinding the same session and same registration is idempotent;
  - `registration_changed` refresh re-upserts the new DeviceId;
  - identity generation or tenant scope replacement disables the old installation before binding the new one;
  - logout disable uses the last successful server `installationId`;
  - a stale bind completion cannot become the active installation;
  - failed upsert does not record an active installation;
  - failed disable leaves no locally active session after `deactivateLocally()`; and
  - concurrent bind/refresh/disable operations execute serially.

- [ ] **Step 2: Run the test and confirm RED**

  ```bash
  flutter test tests/unit/application/remote_push_installation_coordinator_test.dart
  ```

- [ ] **Step 3: Implement the session key and coordinator**

  Define:

  ```dart
  final class RemotePushInstallationSession {
    const RemotePushInstallationSession({
      required this.storageScopeId,
      required this.ownerDid,
      required this.generation,
      this.logicalDeviceId,
    });

    final StorageScopeId storageScopeId;
    final String ownerDid;
    final int generation;
    final String? logicalDeviceId;
  }
  ```

  Expose:

  ```dart
  class RemotePushInstallationCoordinator {
    Future<void> bindActiveSession(RemotePushInstallationSession session);
    Future<void> refreshActiveSession(RemotePushInstallationSession session);
    Future<void> disableActiveInstallation(
      RemotePushInstallationSession session,
    );
    Future<void> disableCurrentInstallation();
    void deactivateLocally(RemotePushInstallationSession session);
  }
  ```

  Serialize all mutations through one tail future. Before accepting a result, compare the requested session with the current desired session. Store only:

  - the current session key;
  - the last successful server installation ID; and
  - the last successfully bound registration fingerprint in memory.

  Do not persist a DeviceId, installation ID, token, or AppKey.

- [ ] **Step 4: Run the test and confirm GREEN**

  ```bash
  flutter test tests/unit/application/remote_push_installation_coordinator_test.dart
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add \
    lib/src/application/remote_push_installation_coordinator.dart \
    tests/unit/application/remote_push_installation_coordinator_test.dart
  git commit -m "feat: coordinate push installation lifecycle"
  ```

---

## Task 4: Compose the Push installation lifecycle into bootstrap and authenticated runtime

**Files:**

- Modify: `lib/src/app/bootstrap.dart`
- Modify: `lib/src/app/app_services.dart`
- Modify: `lib/src/app/awiki_me_app.dart`
- Modify: `lib/src/app/tenant_aware_awiki_me_app.dart`
- Modify: `lib/src/presentation/app_shell/providers/app_runtime_provider.dart`
- Modify: `tests/unit/bootstrap_test.dart`
- Modify: `tests/unit/app_runtime_notification_test.dart`

- [ ] **Step 1: Add failing bootstrap ownership tests**

  In `bootstrap_test.dart`, prove that:

  - `AppBootstrap.create(remotePushClient: fake)` exposes the same client;
  - it constructs a `RemotePushInstallationCoordinator` backed by the authenticated User Service adapter; and
  - `AppBootstrap.dispose()` attempts installation disable before disposing the Core session runtime.

  The dispose test must use an ordered call log:

  ```dart
  expect(calls, <String>['disable_installation', 'dispose_runtime']);
  ```

- [ ] **Step 2: Add failing App runtime lifecycle tests**

  In `app_runtime_notification_test.dart`, override the coordinator with a recording fake and assert:

  - session activation binds after `SessionEpoch` exists;
  - the binding contains tenant scope, owner DID, generation, and current protocol device ID;
  - normal logout, identity replacement, and credential deletion attempt disable before `sessionProvider` is cleared;
  - auth revocation deactivates locally but does not require a successful remote disable;
  - bind/disable failures do not fail login/logout; and
  - App resume requests a best-effort installation refresh.

- [ ] **Step 3: Run focused tests and confirm RED**

  ```bash
  flutter test \
    tests/unit/bootstrap_test.dart \
    tests/unit/app_runtime_notification_test.dart
  ```

- [ ] **Step 4: Build the bootstrap-owned coordinator**

  Add optional fields to `AppBootstrap`:

  ```dart
  final RemotePushClient? remotePushClient;
  final RemotePushInstallationCoordinator? remotePushInstallationCoordinator;
  ```

  Add `RemotePushClient? remotePushClient` to `AppBootstrap.create()`. After `appSessionService` exists, build:

  ```dart
  final pushHttpClient = AwikiOnboardingUtilityHttpClient(
    baseUrl: effectiveEnvironment.userServiceUrl,
  );
  final pushAuthenticatedClient = AuthenticatedUserServiceRpcClient(
    client: pushHttpClient,
    sessions: AuthSessionCoordinator(sessions: appSessionService),
  );
  final pushInstallations = UserServicePushInstallationAdapter(
    userServiceUrl: effectiveEnvironment.userServiceUrl,
    client: pushHttpClient,
    authenticatedClient: pushAuthenticatedClient,
  );
  final pushInstallationCoordinator = remotePushClient == null
      ? null
      : RemotePushInstallationCoordinator(
          client: remotePushClient,
          installations: pushInstallations,
        );
  ```

  In `_disposeResources()`, call `disableCurrentInstallation()` inside the
  existing best-effort disposal step before `disposeRuntime`. This is the
  tenant-switch/tenant-replacement safety net.

- [ ] **Step 5: Add Riverpod providers and overrides**

  Add providers in `app_services.dart`:

  ```dart
  final remotePushClientProvider = Provider<RemotePushClient>(
    (ref) => throw StateError('remote_push_client_unavailable'),
  );

  final remotePushInstallationCoordinatorProvider =
      Provider<RemotePushInstallationCoordinator>(
        (ref) => throw StateError('remote_push_installation_unavailable'),
      );
  ```

  Override both from `AppBootstrap` in `AwikiMeApp`.

  Pass the existing app-lifetime `_remotePushClient` into `AppBootstrap.create()` from `TenantAwareAwikiMeApp`. Remove the logging-only event subscription; retain idempotent early initialization. Dispose the app-lifetime client only after the current bootstrap has finished disposal.

- [ ] **Step 6: Bind and disable at the App runtime gates**

  Add helpers in `AppRuntimeController`:

  ```dart
  RemotePushInstallationSession? _currentRemotePushInstallationSession();
  Future<void> _bindRemotePushBestEffort(SessionEpoch epoch);
  Future<void> _disableRemotePushBestEffort();
  void _deactivateRemotePushLocally();
  ```

  Call bind after `preparePatchGeneration()` and the active-state assignment, without delaying the existing startup sync.

  Call local deactivation first and best-effort disable while authentication is still available for:

  - `logout()`;
  - `prepareIdentityActivation()`;
  - `loginWithLocalCredential()` when replacing an active identity;
  - `deleteCurrentCredential()`; and
  - normal tenant bootstrap disposal.

  On auth revocation, deactivate locally before clearing the session and continue logout even if remote disable is impossible.

- [ ] **Step 7: Run focused tests and confirm GREEN**

  Run the command from Step 3.

- [ ] **Step 8: Commit**

  ```bash
  git add \
    lib/src/app/bootstrap.dart \
    lib/src/app/app_services.dart \
    lib/src/app/awiki_me_app.dart \
    lib/src/app/tenant_aware_awiki_me_app.dart \
    lib/src/presentation/app_shell/providers/app_runtime_provider.dart \
    tests/unit/bootstrap_test.dart \
    tests/unit/app_runtime_notification_test.dart
  git commit -m "feat: bind EMAS installation to active sessions"
  ```

---

## Task 5: Add a typed remote-Push sync receipt and presentation suppression

**Files:**

- Create: `lib/src/application/models/remote_push_sync_receipt.dart`
- Modify: `lib/src/application/message_sync_service.dart`
- Modify: `lib/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart`
- Modify: `tests/unit/message_sync_service_test.dart`
- Modify: `tests/unit/message_sync_coordinator_test.dart`

- [ ] **Step 1: Add a failing reason-mapping test**

  In `message_sync_service_test.dart`, assert:

  ```dart
  await service.syncNow(reason: 'remote_push');
  expect(core.lastReason, 'remote_push');
  ```

  The test must fail because `_coreMessageSyncReason` currently maps unknown reasons to `manual_refresh`.

- [ ] **Step 2: Add failing typed-receipt tests**

  In `message_sync_coordinator_test.dart`, specify the application model:

  ```dart
  enum RemotePushSyncDisposition {
    succeeded,
    retryableFailure,
    recoveryRequired,
    authRevoked,
    staleSession,
    ignored,
  }

  final class RemotePushSyncReceipt {
    const RemotePushSyncReceipt({
      required this.disposition,
      this.committedIncomingMessages = const <CommittedIncomingMessage>[],
    });

    final RemotePushSyncDisposition disposition;
    final List<CommittedIncomingMessage> committedIncomingMessages;
    bool get canAcknowledge =>
        disposition == RemotePushSyncDisposition.succeeded;
  }
  ```

  Add tests proving:

  - `requestRemotePushSync()` is immediate and returns `succeeded` only after conversation fast-local refresh completes;
  - retryable, recovery-required, auth-revoked, thrown, and stale-session paths return their exact non-success disposition;
  - an active normal sync and an arriving remote-Push request share one run when presentation is not finalized;
  - suppression is logical OR across coalesced requests;
  - a queued follow-up preserves suppression;
  - committed event/logical/message IDs are remembered even when presentation is suppressed;
  - suppressed ordinary and Runtime Agent messages do not call in-App or system notification methods; and
  - normal WebSocket/startup sync retains existing notification behavior.

- [ ] **Step 3: Run focused tests and confirm RED**

  ```bash
  flutter test \
    tests/unit/message_sync_service_test.dart \
    tests/unit/message_sync_coordinator_test.dart
  ```

- [ ] **Step 4: Preserve `remote_push` at the Core boundary**

  Add:

  ```dart
  'remote_push' => 'remote_push',
  ```

  to `_coreMessageSyncReason`.

- [ ] **Step 5: Refactor internal sync requests around a typed run receipt**

  Keep the public normal API source-compatible:

  ```dart
  Future<void> requestSync(String reason, {bool immediate = false});
  Future<RemotePushSyncReceipt> requestRemotePushSync();
  ```

  Internally replace the bare `Future<void>` active/queued state with:

  ```dart
  final class _MessageSyncRequestPolicy {
    bool suppressNotificationPresentation;

    void merge({required bool suppressNotificationPresentation}) {
      this.suppressNotificationPresentation =
          this.suppressNotificationPresentation ||
          suppressNotificationPresentation;
    }
  }
  ```

  An active request owns one mutable policy and one
  `Future<RemotePushSyncReceipt>`. Queued requests merge suppression with
  logical OR. Normal callers map the receipt future back to `Future<void>`.

  Map outcomes as follows:

  | Coordinator outcome | Receipt |
  | --- | --- |
  | `idle` or `changed`, diagnostics handled, Join inbox handled, conversation projection refresh completed | `succeeded` |
  | retryable result or thrown error | `retryableFailure` |
  | Core recovery required | `recoveryRequired` |
  | auth revoked | `authRevoked` |
  | epoch/session fence changed before completion | `staleSession` |
  | no active authenticated session at request time | `ignored` |

- [ ] **Step 6: Suppress presentation without suppressing identity ledgers**

  Change:

  ```dart
  void _dispatchCommittedIncomingNotifications(
    MessageSyncOutcome outcome, {
    required bool suppressPresentation,
  })
  ```

  For every eligible committed incoming message:

  1. record event ID and logical message ID in the existing bounded sets;
  2. if `suppressPresentation` is true, pass logical/remote/local IDs through
     `acceptMessageIds` and stop before any banner/system call;
  3. otherwise preserve the existing Runtime Agent
     `acceptRuntimeMessageIds` path and the non-Runtime
     `acceptMessageIds` path exactly.

  This must not change conversation refresh, Core projection, unread state, or committed-message filtering.

  Any automatic retry queued by a remote-Push run must inherit the run's
  suppression policy. A later normal request may merge with it, but cannot
  turn suppression off.

- [ ] **Step 7: Run focused tests and confirm GREEN**

  Run the command from Step 3.

- [ ] **Step 8: Commit**

  ```bash
  git add \
    lib/src/application/models/remote_push_sync_receipt.dart \
    lib/src/application/message_sync_service.dart \
    lib/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart \
    tests/unit/message_sync_service_test.dart \
    tests/unit/message_sync_coordinator_test.dart
  git commit -m "feat: add remote push sync receipts"
  ```

---

## Task 6: Implement opaque message matching and the remote Push event coordinator

**Files:**

- Create: `lib/src/application/remote_push_message_reference.dart`
- Create: `lib/src/application/ports/remote_push_sync_port.dart`
- Create: `lib/src/application/remote_push_message_sync_coordinator.dart`
- Create: `tests/unit/application/remote_push_message_reference_test.dart`
- Create: `tests/unit/application/remote_push_message_sync_coordinator_test.dart`

- [ ] **Step 1: Write the failing opaque-reference vector test**

  Use the Message Service algorithm:

  ```text
  SHA-256(
    "awiki-push-envelope-v1\0" +
    "message" +
    "\0" +
    raw_message_id
  )[0..18]
  ```

  Encode with base64url without padding and prefix with `message_`.

  Add at least two fixed vectors generated independently from the release/0714 Rust implementation, including:

  ```text
  message-sensitive-id
    -> message_xoHiCNuDN3nIPLC3HI_ay7zP
  skill-greeting-9280d474542be461e0ec5fd2dedc2937
    -> message_2Tk1yCrJgbyEnIDR2mIcvFQ8
  ```

  Assert that raw IDs do not occur in the opaque output.

- [ ] **Step 2: Write failing coordinator tests**

  Use fake ports and a broadcast `RemotePushClient`. Cover:

  - pending events drain after activation;
  - live and pending copies of the same delivery ID trigger one sync;
  - `message_received`, `notification_received`,
    `notification_received_in_app`, and `notification_opened` request
    immediate remote-Push sync;
  - `registration_changed` calls installation refresh and does not sync;
  - `notification_removed` does nothing;
  - successful sync acknowledges exactly the delivery IDs included in that run;
  - retryable, recovery-required, auth-revoked, ignored, stale, and thrown outcomes do not acknowledge;
  - a successful acknowledgement failure leaves the native event pending;
  - a stale tenant/session completion does not acknowledge or navigate;
  - a valid opened `mid` matching logical, remote, or local committed message ID selects its canonical conversation;
  - absent, expired, malformed, or unmatched `mid` lands on the conversation list without selecting a conversation; and
  - group/system/structured payload metadata never becomes message or navigation truth.

- [ ] **Step 3: Run the new tests and confirm RED**

  ```bash
  flutter test \
    tests/unit/application/remote_push_message_reference_test.dart \
    tests/unit/application/remote_push_message_sync_coordinator_test.dart
  ```

- [ ] **Step 4: Implement the pure opaque reference helper**

  Use `package:crypto/crypto.dart` and `dart:convert`:

  ```dart
  String remotePushOpaqueMessageReference(String messageId) {
    final digest = sha256.convert(<int>[
      ...utf8.encode('awiki-push-envelope-v1'),
      0,
      ...utf8.encode('message'),
      0,
      ...utf8.encode(messageId),
    ]);
    return 'message_${base64Url.encode(digest.bytes.take(18).toList()).replaceAll('=', '')}';
  }
  ```

  Reject empty, untrimmed, control-character, or over-256-character input.

- [ ] **Step 5: Add the sync/navigation port**

  Define:

  ```dart
  abstract interface class RemotePushSyncPort {
    Future<RemotePushSyncReceipt> requestRemotePushSync();
  }

  abstract interface class RemotePushNavigationPort {
    Future<void> showConversationList(RemotePushSessionContext context);
    Future<void> openConversation(
      RemotePushSessionContext context,
      String conversationId,
    );
  }
  ```

  Define `RemotePushSessionContext` in the same port file. It contains storage
  scope ID, owner DID, and session generation. It carries no token.

- [ ] **Step 6: Implement one serialized event drain**

  `RemotePushMessageSyncCoordinator` must:

  - listen to the client event stream only after `start()`;
  - merge `client.pendingEvents` on `activateSession()` and `resume()`;
  - use a `LinkedHashMap<String, RemotePushEvent>` keyed by delivery ID;
  - run at most one drain at a time;
  - capture one session context per run and compare it after every await;
  - call `requestRemotePushSync()` exactly once for the current batch;
  - resolve opened `mid` only from the receipt's committed messages;
  - call list fallback before optional exact conversation open;
  - acknowledge the captured IDs only after successful sync, current fence, and completed routing; and
  - leave failed IDs in the native queue for a later real trigger.

  Do not add a polling timer or busy retry loop. Retry occurs on App resume, a new callback, registration refresh, or the next authenticated activation.

- [ ] **Step 7: Run the new tests and confirm GREEN**

  Run the command from Step 3.

- [ ] **Step 8: Commit**

  ```bash
  git add \
    lib/src/application/remote_push_message_reference.dart \
    lib/src/application/ports/remote_push_sync_port.dart \
    lib/src/application/remote_push_message_sync_coordinator.dart \
    tests/unit/application/remote_push_message_reference_test.dart \
    tests/unit/application/remote_push_message_sync_coordinator_test.dart
  git commit -m "feat: coordinate remote push message sync"
  ```

---

## Task 7: Wire Push event handling, session fencing, and notification-open navigation

**Files:**

- Create: `lib/src/presentation/app_shell/providers/remote_push_coordinator_provider.dart`
- Modify: `lib/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart`
- Modify: `lib/src/presentation/app_shell/providers/app_runtime_provider.dart`
- Modify: `tests/unit/app_runtime_notification_test.dart`
- Modify: `tests/unit/message_sync_coordinator_test.dart`

- [ ] **Step 1: Add failing provider/runtime integration tests**

  In `app_runtime_notification_test.dart`, construct the production coordinator through overrides and prove:

  - cold-start pending event processing waits for session activation and patch readiness;
  - background/open event triggers `remote_push` sync;
  - Core-committed direct message appears in the conversation projection;
  - the App notification facade receives zero additional presentation calls for that run;
  - native acknowledgement occurs after the conversation fast-local refresh;
  - an opened matching `mid` selects the committed canonical conversation;
  - an unmatched `mid` selects `ShellDestination.messages` and clears the old selection;
  - logout during sync prevents acknowledgement and selection;
  - identity A completion cannot select a conversation for identity B; and
  - App resume drains retained pending events and refreshes installation registration.

- [ ] **Step 2: Run focused tests and confirm RED**

  ```bash
  flutter test \
    tests/unit/app_runtime_notification_test.dart \
    tests/unit/message_sync_coordinator_test.dart
  ```

- [ ] **Step 3: Implement the presentation adapters**

  In `remote_push_coordinator_provider.dart`:

  - adapt `MessageSyncCoordinator.requestRemotePushSync()` to `RemotePushSyncPort`;
  - capture `RemotePushSessionContext` only from
    `activeAppTenantProvider` plus `sessionProvider.activeEpoch`;
  - adapt list fallback to `shellDestinationProvider` and
    `selectedConversationProvider.clearSelection()`;
  - adapt exact navigation to
    `conversationListProvider.commitConversationId(... expectedEpoch:)`,
    `chatThreadsProvider.openConversation()`, and
    `selectedConversationProvider.selectConversation()`; and
  - call installation `refreshActiveSession()` for `registration_changed`.

  Reuse the current notification-activation navigation sequence. Do not invent a second conversation resolver.

- [ ] **Step 4: Start and stop the coordinator from App runtime**

  `AppRuntimeController` must:

  - instantiate/start the provider-owned event coordinator during controller construction;
  - call `activateSession()` after patch readiness and active-state assignment;
  - call `resume()` from the existing App-resumed lifecycle path;
  - call `deactivateSession()` before every authenticated-state clear; and
  - dispose its subscription with the provider.

  Preserve current WebSocket, foreground reconciliation, and desktop notification activation behavior.

- [ ] **Step 5: Run focused tests and confirm GREEN**

  Run the command from Step 2.

- [ ] **Step 6: Run all Push and App runtime unit tests**

  ```bash
  flutter test \
    tests/unit/data/push \
    tests/unit/application/remote_push_installation_coordinator_test.dart \
    tests/unit/application/remote_push_message_reference_test.dart \
    tests/unit/application/remote_push_message_sync_coordinator_test.dart \
    tests/unit/message_sync_service_test.dart \
    tests/unit/message_sync_coordinator_test.dart \
    tests/unit/bootstrap_test.dart \
    tests/unit/app_runtime_notification_test.dart
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add \
    lib/src/presentation/app_shell/providers/remote_push_coordinator_provider.dart \
    lib/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart \
    lib/src/presentation/app_shell/providers/app_runtime_provider.dart \
    tests/unit/app_runtime_notification_test.dart \
    tests/unit/message_sync_coordinator_test.dart
  git commit -m "feat: route Android EMAS events through Core sync"
  ```

---

## Task 8: Update architecture, Android operations, and E2E acceptance contracts

**Files:**

- Modify: `docs/android-remote-push.md`
- Modify: `docs/conversation-presentation-ownership.md`
- Create: `tests/e2e/planned/android_remote_push_future_cases.md`
- Modify: `tests/e2e/case_catalog.json`
- Modify: `tests/e2e/suite_manifest.json`
- Modify: `tests/unit/e2e_harness/test_catalog_test.dart`

- [ ] **Step 1: Add failing catalog assertions**

  Add planned cases:

  ```text
  ANDROID-PUSH-PRODUCT-E2E-001
  ANDROID-PUSH-NATIVE-E2E-001
  ```

  Update the expected catalog count from 91 to 93 and assert both case IDs are `planned`.

- [ ] **Step 2: Run the catalog test and confirm RED**

  ```bash
  flutter test tests/unit/e2e_harness/test_catalog_test.dart
  ```

- [ ] **Step 3: Write the planned physical-device contracts**

  `ANDROID-PUSH-PRODUCT-E2E-001` must require:

  - authenticated Android installation upsert;
  - one real direct message through Message Service outbox and EMAS;
  - foreground silent refresh;
  - background exactly one visible notification;
  - terminated-process tap, Core sync, and exact conversation open;
  - WebSocket plus Push convergence to one committed message;
  - offline/retry retention and later acknowledgement; and
  - logout disable followed by old-DID installation exclusion.

  `ANDROID-PUSH-NATIVE-E2E-001` must require:

  - Nubia P0110 or an explicitly named equivalent physical Android device;
  - notification permission denial then settings recovery;
  - EMAS registration with non-sensitive suffix evidence;
  - background and terminated-process delivery; and
  - no claim of pass from provider API success, outbox `done`, fake facade, or emulator-only evidence.

  Both remain `planned` and are not added to an executable suite.

- [ ] **Step 4: Update catalog revisions consistently**

  Set both JSON files to:

  ```json
  "sourceRevision": "2026-07-30.release0714-android-emas-direct-message-mvp-v1"
  ```

  Add the two planned catalog entries with
  `implementationPath: tests/e2e/planned/android_remote_push_future_cases.md`.

- [ ] **Step 5: Update authoritative documentation**

  In `docs/android-remote-push.md`, replace the client-transport-only boundary with:

  - active authenticated installation lifecycle;
  - exact public RPC endpoint and safe fields;
  - remote Push as dirty hint;
  - successful-sync acknowledgement semantics;
  - EMAS `NOTICE` as sole Android presentation owner for Push-triggered sync;
  - safe opaque notification-open matching;
  - supported direct-message scope; and
  - remaining OEM, credentials, deployment, and real-device limitations.

  In `docs/conversation-presentation-ownership.md`, add:

  - remote Push alongside WebSocket as a hint-only sync trigger;
  - `MessageSyncCoordinator` as the sole Core-commit/projection/notification dedupe owner;
  - the remote-push presentation-suppression rule;
  - SessionEpoch and tenant fencing for acknowledgement/navigation; and
  - the new deterministic regression files.

- [ ] **Step 6: Run the catalog test and confirm GREEN**

  ```bash
  flutter test tests/unit/e2e_harness/test_catalog_test.dart
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add \
    docs/android-remote-push.md \
    docs/conversation-presentation-ownership.md \
    tests/e2e/planned/android_remote_push_future_cases.md \
    tests/e2e/case_catalog.json \
    tests/e2e/suite_manifest.json \
    tests/unit/e2e_harness/test_catalog_test.dart
  git commit -m "docs: define Android EMAS product acceptance"
  ```

---

## Task 9: Add the corresponding cross-service Android installation system test

**Repositories and files:**

- Create isolated checkout if absent:
  `/Users/howard/ANP-Workspace/Feature/awiki-system-test-android-emas-mvp`
- Base: `AgentConnect/awiki-system-test` `release/0714`
- Branch: `codex/android-emas-mvp-system-test`
- Create:
  `tests_v2/user_service/test_push_installation_android.py`
- Do not modify User Service or Message Service production code.

- [ ] **Step 1: Create the isolated system-test checkout**

  If no local clone exists:

  ```bash
  git clone --branch release/0714 \
    https://github.com/AgentConnect/awiki-system-test.git \
    /Users/howard/ANP-Workspace/Feature/awiki-system-test-android-emas-mvp
  cd /Users/howard/ANP-Workspace/Feature/awiki-system-test-android-emas-mvp
  git switch -c codex/android-emas-mvp-system-test
  ```

  If a local clone exists, fetch `origin/release/0714` and create the same isolated branch/worktree without changing another checkout.

- [ ] **Step 2: Write the live Android lifecycle test**

  Mirror the existing iOS lifecycle test but use:

  ```python
  provider_device_id = f"systest-android-{uuid.uuid4().hex}"
  android_app_key = "12345678"
  logical_device_id = f"systest-logical-{uuid.uuid4().hex}"
  ```

  Assert:

  - authenticated `upsert_installation` returns the current owner DID;
  - provider is `aliyun_emas`;
  - platform is `android`;
  - `app_id` and `logical_device_id` round-trip exactly;
  - Alice's active list contains the installation;
  - Bob's active list does not contain Alice's installation;
  - `disable_installation` returns `status == disabled`; and
  - Alice's active list excludes it after disable.

  Use `finally` cleanup so an assertion failure still disables the installation.

- [ ] **Step 3: Run the focused live system test**

  From the system-test checkout, run the repository's documented tests_v2 command for:

  ```text
  tests_v2/user_service/test_push_installation_android.py
  ```

  Report mode, User Service URL, Message Service URL, WebSocket URL, DID domain, passed/failed/skipped counts, and elapsed time. Do not print tokens or full provider DeviceIds.

  If the live environment or authorization is unavailable, retain the test code, mark this layer `UNVERIFIED`, and do not claim the cross-service gate passed.

- [ ] **Step 4: Commit the system test separately**

  ```bash
  git add tests_v2/user_service/test_push_installation_android.py
  git commit -m "test: cover Android push installation lifecycle"
  ```

  Do not push this branch without separate approval.

---

## Task 10: Run repository-wide verification and inspect scope

**Files:**

- Verify all files changed by Tasks 1-8.
- Verify the separate system-test commit from Task 9.

- [ ] **Step 1: Format only touched Dart files**

  ```bash
  dart format \
    lib/src/application/models/push_installation.dart \
    lib/src/application/models/remote_push_sync_receipt.dart \
    lib/src/application/ports/push_installation_port.dart \
    lib/src/application/ports/remote_push_sync_port.dart \
    lib/src/application/remote_push_installation_coordinator.dart \
    lib/src/application/remote_push_message_reference.dart \
    lib/src/application/remote_push_message_sync_coordinator.dart \
    lib/src/application/message_sync_service.dart \
    lib/src/data/push/aliyun_emas_platform.dart \
    lib/src/data/push/aliyun_emas_remote_push_client.dart \
    lib/src/data/push/user_service_push_installation_adapter.dart \
    lib/src/domain/services/remote_push_client.dart \
    lib/src/app/bootstrap.dart \
    lib/src/app/app_services.dart \
    lib/src/app/awiki_me_app.dart \
    lib/src/app/tenant_aware_awiki_me_app.dart \
    lib/src/presentation/app_shell/providers/app_runtime_provider.dart \
    lib/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart \
    lib/src/presentation/app_shell/providers/remote_push_coordinator_provider.dart \
    tests/unit/application/remote_push_installation_coordinator_test.dart \
    tests/unit/application/remote_push_message_reference_test.dart \
    tests/unit/application/remote_push_message_sync_coordinator_test.dart \
    tests/unit/data/push/aliyun_emas_remote_push_client_test.dart \
    tests/unit/data/push/user_service_push_installation_adapter_test.dart \
    tests/unit/message_sync_service_test.dart \
    tests/unit/message_sync_coordinator_test.dart \
    tests/unit/bootstrap_test.dart \
    tests/unit/app_runtime_notification_test.dart \
    tests/unit/e2e_harness/test_catalog_test.dart
  ```

- [ ] **Step 2: Run static analysis**

  ```bash
  dart analyze
  ```

- [ ] **Step 3: Run the complete unit suite**

  ```bash
  dart run tests/unit/runner.dart
  ```

- [ ] **Step 4: Run the no-service E2E catalog/smoke verification**

  ```bash
  dart run tests/e2e/runner.dart --case smoke --dry-run
  ```

  This validates planning and command construction only. It is not physical-device or provider evidence.

- [ ] **Step 5: Build the Android Debug APK without credentials**

  ```bash
  flutter build apk --debug
  ```

  The build must succeed with EMAS disabled when `android/emas.properties` is absent. Do not create or commit a credential file.

- [ ] **Step 6: Inspect Git scope**

  ```bash
  git status --short
  git diff --stat origin/release/0714...HEAD
  git diff --name-only origin/release/0714...HEAD
  ```

  Confirm:

  - no iOS/macOS/Windows/web/generated/Pod files changed;
  - no credential or local configuration file is tracked;
  - the accepted design and this plan remain present;
  - only Android and strictly required shared Dart/docs/tests changed; and
  - the system-test change is isolated in its own repository/branch.

- [ ] **Step 7: Record final evidence without overclaiming**

  Report separately:

  - deterministic App unit/analyze/build results;
  - system-test result or `UNVERIFIED`;
  - physical Nubia P0110 provider/product E2E as `UNVERIFIED` until explicitly authorized and run;
  - no deployment, secret configuration, push, PR, or live provider send performed.

  Do not mark the Android EMAS product gate complete from unit tests, APK build, installation RPC success, provider API success, or outbox `done` alone.

---

## Plan Review Checklist

- [ ] Every new production type or method has an explicit failing test before implementation.
- [ ] Exact User Service endpoint, methods, params, and response fields match `release/0714`.
- [ ] Exact Message Service opaque-reference algorithm matches `release/0714`.
- [ ] Push remains a dirty hint; Core remains the message/conversation truth source.
- [ ] Session and tenant fences cover bind, refresh, disable, sync, acknowledgement, and navigation.
- [ ] Remote-Push suppression preserves message identity ledgers and normal sync behavior.
- [ ] Logout and tenant replacement attempt disable before authenticated runtime disposal.
- [ ] Pending events are not acknowledged on retryable, recovery, auth, stale, ignored, or error paths.
- [ ] E2E planned cases have exact oracles and cannot be mistaken for executed evidence.
- [ ] Cross-service test work is isolated and reported independently.
- [ ] No vague stand-ins, unspecified error behavior, or unowned follow-up remains in the implementation steps.
