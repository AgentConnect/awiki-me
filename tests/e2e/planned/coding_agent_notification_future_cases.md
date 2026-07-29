# Coding Agent notification future E2E cases

## `AGENT-NOTIFY-E2E-001`

- Status: planned; no automated case attestation exists yet.
- Owner: `awiki-me-agents+awiki-cli-runtime`.
- Scope: real Coding Agent or Skill Agent → daemon/CLI → User Service and
  Message Service → AWiki Me foreground quiet behavior and background macOS notification,
  visible recent conversation, and exact-once terminal semantics.
- Blocker: the existing `awiki-system-test` and App E2E runners do not yet have
  one fixture that provisions isolated App, CLI, daemon, and coding-runtime
  identities on an approved tenant and correlates the ordinary final message
  with `awiki.agent.status.v1`.
- Follow-up: add the cross-service fixture and case attestation, exercise
  `completed`, `blocked`, and `action_required` in both message-first and
  status-first order, then register the case in an executable remote suite.

The 2026-07-29 development-session observation used a non-production tenant and
confirmed that a CLI message appeared in AWiki Me recents and chat content.
That observation is manual evidence only and must not be reported as this case
passing.

## `AGENT-NOTIFY-NATIVE-E2E-001`

- Status: planned; no automated case attestation exists yet.
- Owner: `awiki-me-platform`.
- Scope: macOS notification authorization, Development bundle identity,
  background delivery through the production notification facade, and visible
  Notification Center banner content.
- Blocker: the current CI smoke runner cannot deterministically reset/approve
  macOS notification permission or inspect Notification Center without an
  operator-controlled host.
- Follow-up: add a dedicated macOS runner that snapshots permission state,
  grants authorization to the Development bundle, backgrounds the App, records
  exactly one banner, and restores the original permission state.

The 2026-07-29 development-session banner observation remains manual evidence;
the fake-facade unit test and debug smoke hook do not satisfy this native case.
