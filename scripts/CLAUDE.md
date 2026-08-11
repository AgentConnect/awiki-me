# scripts/

> L2 document | Parent: [../CLAUDE.md](../CLAUDE.md)

1. **Role**: Local development, verification, and packaging entrypoints.
2. **Boundary**: Scripts orchestrate existing Flutter/platform tools; product behavior stays in `lib/`.
3. **Constraint**: Keep development builds incremental and platform-specific; never commit generated state or secrets.

## Members

- `build_manual_dual_macos_apps.sh`: Builds isolated standalone Admin and Joiner macOS Debug Apps from `lib/main.dart`.
- `prepare_macos_build.sh`: Prepares Flutter and CocoaPods dependencies.
- `run_macos_production_scope_restart_gate.sh`: Runs the signed production-scope restart gate.
- `pre_release_storage_cleanup.dart`: Executes the reviewed pre-release storage cleanup workflow.
- `android_emas_release_config.py`: Writes and validates the ignored, owner-only Android Release EMAS configuration.
- `package_app.sh`, `package_unix_worker.sh`, `package_windows.ps1`, `package_app.config`: Package and publish platform artifacts.
- `run_android_emulator.sh`: Starts the configured Android emulator workflow.
- `lib/`, `windows/`: Shared signing and Windows verification helpers.

Update this file when script membership or responsibilities change.
