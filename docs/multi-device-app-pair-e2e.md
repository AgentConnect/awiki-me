# One-host App↔App E2E mode

The App-pair harness is the reusable macOS E2E boundary for scenarios that need
two independently runnable AWiki Me processes on one computer. It exposes two
separate suites:

- `multi-device-app-pair`: security acceptance for `DEVICE-JOIN-E2E-004`,
  including one real macOS LocalAuthentication decision;
- `multi-device-app-pair-functional`: unattended functional acceptance for
  cross-device Agent inventory and Direct-message convergence.

## Isolation model

The two roles are product processes, not two widget trees in one test process:

| Boundary | Admin App | Joining App |
| --- | --- | --- |
| Bundle ID | `ai.awiki.awikime.dev.e2e.pair.admin` | `ai.awiki.awikime.dev.e2e.pair.joiner` |
| Flutter build directory | stable role cache under `.e2e/build-cache/` | separate stable role cache under `.e2e/build-cache/` |
| App bundle | `AWikiMe-admin.app` | `AWikiMe-joiner.app` |
| App/native Core state | fresh admin Storage Scope | fresh joiner Storage Scope |
| Flutter driver | attaches to the admin VM service | attaches to the joiner VM service |

The runner builds the roles sequentially, launches both bundles directly, then
attaches two `flutter drive --use-existing-app` processes concurrently. The
stable, distinct bundle IDs keep the operating-system application identities
separate. Stable per-role build roots may reuse only compiler intermediates;
per-run state roots and E2E scope-secret repositories prevent either role from
reusing another run's product data or credential material.

## Coordination boundary

The runner creates an authenticated loopback-only coordinator for the duration
of the pair. Product state still advances only through the visible App UI,
native Core, realtime notification path, and remote services.

The coordinator may:

- exchange bounded lifecycle checkpoints between the two test roles;
- compare the two six-digit SAS values in memory and return only
  `ready/matched`;
- in the functional suite, exchange only public DIDs, Handles, canonical
  conversation IDs, and message IDs needed for cross-process exact oracles.

It may not:

- call a product API, hydrate the Join inbox, request App sync, or mutate Core;
- persist OTP, SAS, challenge, proof, token, or authorization values;
- place SAS values in logs, reports, or case attestation.

The run-config token is mode-local, stored with file mode `0600`, and deleted
when the pair stops. Both App state roots are also removed after the processes
are terminated. Remote test identities and Join side effects remain governed
by the suite residual ledger.

Driver output is not streamed or persisted. On failure, each driver retains at
most 80 already-sanitized lines in memory; the runner redacts registered
runtime secrets, DIDs, phone values, and every standalone six-digit value
before surfacing that bounded diagnostic.

## Reusable builder

`tool/build_isolated_e2e_app.dart` is the generic build boundary. It accepts an
`integration_test/*_test.dart` target, isolated state/work/artifact roots, a
bundle ID, and repeated Dart defines. It always makes a Debug macOS build with
`--no-pub`; each work root owns its Flutter XDG settings and build directory.
The App-pair runner keeps one stable work root per role under
`.e2e/build-cache/multi-device-app-pair/`, so later runs reuse Flutter,
CocoaPods, Swift, and Xcode intermediates. Only the fixed E2E gate and role are
compile-time inputs. Run config, attestation paths, scenario IDs, and run IDs
are supplied to the launched processes, so a new run does not invalidate the
role build. Runtime state, E2E credential storage, and copied App artifacts
remain per-run, and the Admin and Joiner retain distinct bundle IDs. All three
roots must be non-overlapping descendants of the repository so the Flutter
relative build-dir contract and cleanup boundary remain auditable.
On the current Intel development host it rejects any executable that is not
x86_64-only. The output is one JSON artifact manifest containing the copied App
and executable paths.

The App-pair runner is the supported caller today. Future E2E modes may reuse
the builder, but must define their own orchestration, isolation oracle, secret
policy, cleanup, catalog case, and suite entry. This does not make every
existing E2E a dual-App test.

## Run

Use the same reviewed remote account variables as the App↔CLI Join suite. The
security suite does not need `cliPeer.binary` or `cliPeer.sourceRef`:

```bash
AWIKI_MULTI_DEVICE_REMOTE_JOIN_E2E_ENABLED=1 \
AWIKI_MULTI_DEVICE_E2E_PHONE=<dedicated-test-phone> \
AWIKI_MULTI_DEVICE_E2E_OTP_COMMAND_JSON='<reviewed-json-argv-resolver>' \
AWIKI_MULTI_DEVICE_E2E_HANDLE_PREFIX=apppair \
dart run tests/e2e/runner.dart \
  --case multi-device-app-pair \
  --config <local-awiki-info-macos-config.yaml>
```

For the explicitly authorized synthetic test number, also set
`AWIKI_MULTI_DEVICE_E2E_ALLOW_STAGED_OTP_ON_SMS_ERROR=1`. This keeps the same
strict response-shape and exact reviewed-resolver checks documented in
[testing.md](testing.md); it does not convert arbitrary SMS failures into
success. HTTP 429 uses the service's bounded `Retry-After` contract and does
not enter staged-OTP resolution.

The operator must complete the real macOS user-presence prompt in the admin
App. `--prepare-only` validates prerequisites but intentionally does not build
the pair, because the compiled targets require the ephemeral coordinator of an
executing run. Flutter is resolved from `PATH` by default; a host whose Flutter
SDK is not on `PATH` can set `AWIKI_E2E_FLUTTER_BIN` to the absolute executable.

The unattended functional suite uses the same command shape with
`--case multi-device-app-pair-functional`. Its local YAML additionally requires
an x86_64 Debug `cliPeer.binary`, the exact 40-character source revision
embedded in that binary, and an x86_64 Debug `daemon.binary` plus a Daemon
Handle. It injects an always-confirming `UserPresencePort` only through the
compiled integration-test provider override. Production code and the security
suite remain fail-closed and continue to use `LocalAuthUserPresencePort`.
Because the runner executes on macOS while `awiki.info` is managed on Ali, its
Account State fixture/fail-once action accepts only the reviewed
`ssh ali -- sudo -n /usr/bin/env ...` argv. That argv runs the immutable
`/opt/awiki/services/user-service/v1/current` script, sets
`PYTHONDONTWRITEBYTECODE=1` and the deployed `PYTHONPATH`, and loads only
`/etc/awiki/user-service.env`. A local `/home/ecs-user/...` command, mutable
source checkout, alternate host, shell, or implicit remote environment fails
before either App starts.
For the one-shot Account State domain-isolation phase, the joining test App
temporarily detaches the presentation request bus and pauses its foreground
catch-up timer while the server failpoint is armed. Realtime message delivery
remains available. The test still calls the real coordinator and remote service
directly for the failing reconcile and the successful retry, then restores the
normal lifecycle and request bus. This prevents a realtime hint or the periodic
foreground reconcile from consuming the one-shot fixture before the asserted
request without changing production scheduling or weakening the remote
protocol assertions.
The Stage-3 retention-gap action follows the same reviewed boundary. It runs
only through the fixed `ssh ali -- sudo -n /usr/bin/env ...` command, executes
the immutable `/opt/awiki/services/message-service/current` helper with
`--apply`, pins the reviewed Ali `/usr/bin/python3.11` stdlib runtime, and reads
only the root-owned, service-group-readable, non-group-writable
`/etc/awiki/message-service.toml`.
The server config must explicitly enable
`testing.sync_v2_recovery_operator_enabled`. The helper accepts one exact
protocol device and resolves exactly one account; the managed User operator
then authorizes that account through the active Handle test-phone binding and
confirms the same active device. Message Service revalidates the mapping,
requires the replica to be bootstrapped, and updates exactly one active stream.
The App runner supplies neither an account ID nor a dynamic account allowlist.
Its closed receipt is fault-injection evidence only, never a message/recovery
oracle.
The functional suite keeps the production-default Direct E2EE gate disabled.
Its ordinary Direct texts therefore use P3 Base on every participant; the test
fails if multi-device synchronization silently creates a P5 session or upgrades
the message security level.

The functional suite proves:

1. the joining App starts its normal Agents-page inventory observer before the
   admin App installs one real Daemon and creates Codex and Claude Code runtime
   Agents;
2. both Apps converge the same exact Daemon/runtime DID, Handle, runtime kind,
   and parent topology, and the joining App renders both runtime names without
   a test-side inventory refresh after creation;
3. an admin-App default-plain Direct message is committed to an independent CLI
   peer and appears on the joining App as the same canonical `isMine` sender
   projection;
4. the joining App sends a second Direct message through the same conversation
   using its own joined-device signing key; the admin App projects that exact
   default-plain message as canonical `isMine` sender projection;
5. an ordinary CLI reply appears under the same conversation on both Apps and
   is visibly rendered by the joining App;
6. the joining App opens an already-converged runtime Agent through visible UI,
   sends one default-plain prompt through the real composer, and the admin App
   renders the same canonical outgoing message.

The runner executes the independent Direct-message checks immediately after
Join, then starts the Agents-page observer before Daemon/Agent creation. This
keeps an Agent provisioning failure from hiding joined-device messaging
evidence while preserving the observer-before-create topology oracle.

For every product RPC, Core obtains the device signing private key and its
verification-method ID as one `KeyMaterialProvider` result. The test fails if a
joined App signs with its local device private key but labels the Origin Proof
with the first `authentication` entry from the shared DID Document.

Realtime and Push remain lossy hints. While an authenticated App is in the
foreground, App runtime requests a coalesced Core reliable-sync catch-up every
30 seconds and stops that cadence in the background. This lets a durable
sender/recipient owner event converge even if its live WebSocket hint is
missed; the timer never projects a message itself and does not replace Core
checkpoints. A sender-side `sync.changed` notification contains only a sync
hint: the App preserves it long enough to schedule Core `sync.delta`, while
`sync.thread_after` remains the message projection source of truth.
The stable conversation ID used by the App is only a presentation/storage
route. Core keeps ordinary Direct history on the immutable
`direct + peer DID` wire identity before merging it with a sender device's
local projection; the acceptance path must not turn that presentation ID into
a `thread` wire identity or weaken conflict detection.

It does **not** prove operating-system user presence, and it starts only one
Daemon. The second App observes the account-level Agent Inventory; it must not
start duplicate runtime processes for the same Daemon-owned Agents.

User Service Inventory remains the Agent-topology source of truth. A committed
Daemon control event, including one replayed after a subscription is attached,
is only an invalidation signal on another device: it triggers an authoritative
Inventory reconciliation but cannot synthesize a new Agent locally. This
closes the snapshot/subscription race without making realtime payloads a second
topology source of truth. Before a runtime Agent from that authoritative
Inventory is published to the UI, the App asks Core Directory to project its
canonical Direct route. A failed identity projection never invents a Persona;
the next authoritative Inventory reconciliation retries it. This lets reliable
sender-side history hydrate an Agent conversation even when that device has
never opened the chat. Because the invalidation hint can also be lost, the
visible Agents page performs a quiet authoritative Inventory reconciliation
every 30 seconds while the App is foregrounded and stops it when the page is
disposed. On the App that accepted a runtime-create intent, the pending intent
also drives a bounded, quiet Inventory reconciliation until the exact runtime
appears or the intent deadline expires.

## Verification evidence

The `awiki.info` run `20260726150342-hkr9m42wlk` passed
`DEVICE-JOIN-E2E-004` on 2026-07-26. Its attestation proves both isolated App
processes, Joiner pending without SAS, listener-delivered Admin review,
in-memory SAS match, one real macOS user-presence completion, and exact
two-device Registry convergence. Local state and the coordinator config were
removed; the remote identity/Join ledger remains `residual` because no public
remote delete API exists.

The unattended functional runs `20260726223434-hkrm1iagkz`,
`20260726224138-hkrm8j0eej`, and `20260726225818-hkrmp2b5ac` then passed
consecutively on `awiki.info`; the last run used the final source state after
the foreground Inventory reconciliation timer lifecycle was made explicit.
Each verified `DEVICE-AGENT-SYNC-E2E-001`,
`DEVICE-MESSAGE-SYNC-E2E-001`, and `DEVICE-MESSAGE-SYNC-E2E-002` with
schema-v2 case attestation.

The later `awiki.info` run `20260727065349-hkrzswkgbz` passed the same three
cases after the joined-device Origin Proof regression was added. Its outbound
attestation additionally proves that the joining App committed a Direct
message with its own device signing material and that the admin App projected
the exact message as canonical own-sync. These runs prove the functional
oracles above but, by design, do not replace the real-user-presence security
attestation.

The `awiki.info` run `20260727162425-hksfj42mww` passed all four functional
cases after sender-side history hydration was made exact-message aware and
ordinary Direct history kept `direct + peer DID` as its immutable wire
identity. Its schema-v2 attestation includes
`DEVICE-AGENT-MESSAGE-SYNC-E2E-001` in addition to the two Direct-message cases
and `DEVICE-AGENT-SYNC-E2E-001`; both isolated Debug Apps completed in
8 minutes 43 seconds. This is the first recorded App↔App acceptance proving a
prompt sent through the joining App's visible runtime-Agent composer converges
to the admin App.
