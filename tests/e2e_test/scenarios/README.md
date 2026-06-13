# E2E Scenarios

Place reusable end-to-end scenario code here, for example App + CLI peer message
flows. Harness entry points should call these scenarios instead of duplicating
business flow steps.


## Agent IM delegated message

`agent_im_delegated_message/app_bootstrap_scenario.dart` is the reusable
App-side bootstrap hook for the delegated-message E2E flow. It calls the
production `DefaultAgentControlService` with fake ports, sends an
`awiki.daemon.bootstrap.v1` payload to the Daemon direct thread, verifies that
system/control payloads are hidden from chat rendering, and returns only a
redacted report projection. The raw private package is kept in the in-memory
send payload only and must not be logged or persisted by tests.
