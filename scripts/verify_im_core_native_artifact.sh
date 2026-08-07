#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IM_CORE_REPO_DIR="${AWIKI_IM_CORE_REPO_DIR:-$ROOT_DIR/../awiki-cli-rs2}"
IM_CORE_REPO_DIR="$(cd "$IM_CORE_REPO_DIR" 2>/dev/null && pwd)" || {
  echo "error: awiki-cli-rs2 checkout is unavailable" >&2
  exit 1
}
VERIFY_SCRIPT="$IM_CORE_REPO_DIR/scripts/flutter/verify-native-artifact.sh"
[[ -f "$VERIFY_SCRIPT" ]] || {
  echo "error: native artifact verifier is missing: $VERIFY_SCRIPT" >&2
  exit 1
}

exec bash "$VERIFY_SCRIPT" --macos
