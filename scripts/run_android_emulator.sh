#!/usr/bin/env bash

set -euo pipefail

sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
emulator_bin="$sdk_root/emulator/emulator"

usage() {
  cat <<'EOF'
Usage:
  scripts/run_android_emulator.sh --list
  scripts/run_android_emulator.sh <avd-name> [emulator options...]

Starts an Android Emulator with direct host keycode forwarding so physical
keyboard input reaches the guest instead of relying on host charmap translation.
EOF
}

if [[ ! -x "$emulator_bin" ]]; then
  printf 'Android Emulator not found at %s\n' "$emulator_bin" >&2
  exit 1
fi

if [[ "${1:-}" == "--list" ]]; then
  exec "$emulator_bin" -list-avds
fi

if [[ $# -lt 1 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  [[ $# -ge 1 ]] && exit 0
  exit 2
fi

avd_name="$1"
shift

exec "$emulator_bin" -avd "$avd_name" -use-keycode-forwarding "$@"
