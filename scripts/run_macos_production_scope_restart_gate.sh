#!/usr/bin/env bash
set -euo pipefail

# NATIVE-E2E-002: signed production Keychain survives release rebuild/process restart.

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

# shellcheck source=scripts/lib/macos_signing.sh
source "$ROOT_DIR/scripts/lib/macos_signing.sh"

[[ "$(uname -s)" == "Darwin" ]] || {
  echo "production_scope_restart_gate_failed: macOS required" >&2
  exit 2
}

: "${AWIKI_MACOS_SIGNING_IDENTITY:?set AWIKI_MACOS_SIGNING_IDENTITY to a stable codesigning identity}"
: "${AWIKI_MACOS_DEVELOPMENT_TEAM:?set AWIKI_MACOS_DEVELOPMENT_TEAM to the matching Team ID}"

signing_fingerprint="$(
  awiki_resolve_codesigning_identity "$AWIKI_MACOS_SIGNING_IDENTITY"
)" || {
  echo "production_scope_restart_gate_failed: signing identity unavailable" >&2
  exit 2
}
command -v flutter >/dev/null || {
  echo "production_scope_restart_gate_failed: flutter unavailable" >&2
  exit 2
}

scope_id=$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)
result_root=$(mktemp -d "${TMPDIR:-/tmp}/awiki-production-scope-gate.XXXXXX")
app_path=""
cleanup_needed=true

cleanup() {
  if [[ "$cleanup_needed" == true ]]; then
    security delete-generic-password \
      -s ai.awiki.awikime.scope-secrets \
      -a "scope/$scope_id" >/dev/null 2>&1 || true
  fi
  rm -rf "$result_root"
}
trap cleanup EXIT

find_release_app() {
  find build/macos/Build/Products/Release -maxdepth 1 -type d -name '*.app' \
    -print -quit
}

verify_signature() {
  local app=$1
  awiki_verify_macos_app_signature \
    "$app" \
    "$AWIKI_MACOS_DEVELOPMENT_TEAM" \
    "ai.awiki.awikime"
}

run_phase() {
  local phase=$1
  local result_path="$result_root/$phase.json"
  rm -f "$result_path"
  flutter build macos --release --no-pub \
      --target tests/e2e/flutter/native/production_scope_restart_probe.dart \
      --dart-define="AWIKI_SCOPE_RESTART_PHASE=$phase" \
      --dart-define="AWIKI_SCOPE_RESTART_ID=$scope_id" \
      --dart-define="AWIKI_SCOPE_RESTART_RESULT_PATH=$result_path"
  app_path=$(find_release_app)
  [[ -n "$app_path" ]] || {
    echo "production_scope_restart_gate_failed: release app missing" >&2
    exit 2
  }
  codesign --force --deep --options runtime \
    --sign "$signing_fingerprint" "$app_path"
  verify_signature "$app_path"
  local executable
  executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
    "$app_path/Contents/Info.plist")
  "$app_path/Contents/MacOS/$executable"
  python3 - "$result_path" "$phase" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
phase = sys.argv[2]
data = json.loads(path.read_text())
expected = {
    "case_id": "NATIVE-E2E-002",
    "phase": phase,
    "status": "passed",
    "code": "ok",
}
if data != expected:
    raise SystemExit("production scope restart result mismatch")
PY
}

run_phase provision
run_phase reopen
run_phase cleanup
cleanup_needed=false
echo "NATIVE-E2E-002 passed: signed release rebuild/process restart preserved the production scope item"
