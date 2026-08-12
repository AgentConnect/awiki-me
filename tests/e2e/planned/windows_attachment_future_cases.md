# Planned Windows attachment cases

This file is a non-executable catalog anchor. It does not register tests,
provide fixtures, or claim remote pass evidence.

- `WINDOWS-ATTACHMENT-LONG-PATH-E2E-001` requires a real Windows x64 AWiki Me
  build and a deterministic attachment staging path whose `.awiki-part` form
  exceeds 260 UTF-16 code units. The case must download through native Core,
  verify and atomically publish the exact bytes, open them in the App, then
  prove the committed cache survives restart without making system
  `LongPathsEnabled` a prerequisite. Short paths, memory-only download,
  manual file copying, mock-native execution, or accepting partial bytes are
  not passing evidence.
