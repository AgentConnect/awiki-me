# Client update behavior

The current tenant's Server Info owns the App's recommended and minimum supported
versions. The App checks that policy and opens its download page; it does not
download or install packages on the user's behalf.

## Ownership and startup

- `UpdateService.loadCachedUpdate` reads local policy without network I/O.
  `AppUpdateService` owns origin/revision validation, bounded HTTP requests and
  persistence; it does not own navigation or the messaging runtime.
- `AppUpdateController` applies the cache before refreshing. The shell waits for
  this local read before initializing business runtime. A known minimum blocks
  normal entry immediately; a cache miss does not hold startup for the network.
- A restriction leaves retry, the download page and tenant switching available.
  Opening the page does not remove the restriction. Only the current tenant's
  verified policy/current installed version can change its compatibility state.
- A tenant switch replaces the tenant's service/provider scope. Disposed services
  abort pending requests, and stale provider completions cannot update the new UI.
  An optional official-source lookup cannot lift a known current-tenant minimum
  or invalidate its pending refresh.
  Tenant request generations are independent of recommendation selection. If a
  tenant minimum arrives during an official lookup, it takes over the visible
  policy and download target; late official results cannot replace that state.

## Failure and cache semantics

Checks for the same service share a pending request. A manual check always reaches
the network, even if it overlaps an automatic check satisfied by fresh cache.
The whole HTTP response has a 15-second timeout and a 1 MiB size bound; redirects
are rejected. A failed request keeps the last verified policy, including a
minimum-version restriction, and displays a check failure.

The cache namespace includes tenant ID, policy origin, product and channel. A
single versioned record contains the manifest or confirmed policy absence,
revision and timestamp, so an interrupted auxiliary timestamp write cannot mix
two policy states. Existing manifest-only caches are still readable. A verified
live policy remains effective in memory if persistence fails; after restart only
successfully persisted state is available.

An explicit disabled policy (or a custom tenant's 404) clears previous
recommendations and requirements. Origin and revision checks apply before an
enabled or disabled versioned policy can replace the cache. Absence is persisted
along with the last revision so offline restart does not resurrect an old
recommendation. A network error is not policy absence.
`client_versions: null` is malformed, not an explicit removal: it must preserve
the previous verified policy, or report a failed check when no cache exists.

Settings distinguish unchecked, checking, unavailable, failed/cached, update
available and up to date. The last state requires a successfully interpreted
version policy; absence never produces an "already latest" message.

## Local verification

No release or production policy change is required:

```bash
flutter test --no-pub tests/unit/data/services/app_update_service_test.dart tests/unit/app_update_provider_test.dart tests/unit/app_update_lifecycle_test.dart tests/unit/domain/app_update_manifest_test.dart
flutter test --no-pub integration_test/app_smoke_test.dart -d macos --plain-name 'cached update gate survives offline startup and recovers through retry'
```

The service tests use controlled HTTP responses with simulated versions, delayed
responses, policy removal, disk failures and offline restart. The native smoke
`APP-UPDATE-SMOKE-E2E-001` mounts the actual App with fake service ports and checks
visible restriction, manual download action and recovery through retry. It does
not attest a real OS package installation, signing or data retention after one.

See [testing.md](testing.md) for platform runner and full-suite requirements.

Review verification on 2026-09-09: the four update test files listed above plus
`tests/unit/handle_recovery_flow_test.dart` passed 120 tests locally, including
both response orders, startup overlap, newer tenant requests, authoritative
download selection, null policies with/without cache, and deleted Recovery UI
selection. The reproducing update tests failed before the fix. Targeted Dart
analysis passed. Native platform smoke and real-backend product E2E were not run
in this local-only review; no package was published or installed.
