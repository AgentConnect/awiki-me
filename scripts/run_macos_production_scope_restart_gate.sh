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
command -v pod >/dev/null || {
  echo "production_scope_restart_gate_failed: CocoaPods unavailable" >&2
  exit 2
}

im_core_repo_dir="${AWIKI_IM_CORE_REPO_DIR:-$ROOT_DIR/../awiki-cli-rs2}"
im_core_repo_dir="$(cd "$im_core_repo_dir" 2>/dev/null && pwd)" || {
  echo "production_scope_restart_gate_failed: native dependency repository unavailable" >&2
  exit 2
}
im_core_build_script="$im_core_repo_dir/scripts/flutter/build-sdk-native.sh"
im_core_xcframework="$im_core_repo_dir/packages/awiki_im_core/macos/Frameworks/AwikiImCore.xcframework"

prepare_native_dependency() {
  [[ -x "$im_core_build_script" ]] || {
    echo "missing native build script: $im_core_build_script" >&2
    return 1
  }
  local source_revision
  source_revision="$(git -C "$im_core_repo_dir" rev-parse --verify HEAD)" || return 1
  echo "Preparing awiki_im_core from source revision $source_revision"

  if ! "$im_core_build_script" --macos-only; then
    echo "native awiki_im_core build failed" >&2
    return 1
  fi
  if ! AWIKI_IM_CORE_REPO_DIR="$im_core_repo_dir" \
    "$ROOT_DIR/scripts/verify_im_core_native_artifact.sh"; then
    echo "native awiki_im_core provenance verification failed" >&2
    return 1
  fi

  local info_plist="$im_core_xcframework/Info.plist"
  [[ -f "$info_plist" ]] || {
    echo "native XCFramework is missing Info.plist" >&2
    return 1
  }
  local platform library_path library
  platform="$(/usr/libexec/PlistBuddy -c 'Print :AvailableLibraries:0:SupportedPlatform' "$info_plist")" || return 1
  library_path="$(/usr/libexec/PlistBuddy -c 'Print :AvailableLibraries:0:LibraryPath' "$info_plist")" || return 1
  [[ "$platform" == "macos" ]] || {
    echo "native XCFramework first library is not macOS" >&2
    return 1
  }
  if /usr/libexec/PlistBuddy -c 'Print :AvailableLibraries:1' "$info_plist" >/dev/null 2>&1; then
    echo "native macOS XCFramework must contain exactly one platform library" >&2
    return 1
  fi
  library="$(find "$im_core_xcframework" -mindepth 2 -maxdepth 2 -type f -name "$library_path" -print -quit)"
  [[ -f "$library" ]] || {
    echo "native XCFramework library is missing" >&2
    return 1
  }
  lipo "$library" -verify_arch arm64 x86_64 || {
    echo "native XCFramework must contain arm64 and x86_64" >&2
    return 1
  }

  rm -rf build/macos/Build/Products/Release/XCFrameworkIntermediates/awiki_im_core
  if ! flutter build macos --config-only --release --no-pub \
    --target tests/e2e/flutter/native/production_scope_restart_probe.dart; then
    echo "release platform configuration generation failed" >&2
    return 1
  fi
  if ! (cd macos && pod install); then
    echo "CocoaPods installation failed" >&2
    return 1
  fi
}

prepare_native_dependency || {
  echo "production_scope_restart_gate_failed: native dependency preparation failed" >&2
  exit 2
}

podfile_lock_checksum="$(shasum -a 256 macos/Podfile.lock | awk '{print $1}')"

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
final_podfile_lock_checksum="$(shasum -a 256 macos/Podfile.lock | awk '{print $1}')"
[[ "$final_podfile_lock_checksum" == "$podfile_lock_checksum" ]] || {
  echo "production_scope_restart_gate_failed: Podfile.lock changed during release phases" >&2
  exit 2
}
cleanup_needed=false
echo "NATIVE-E2E-002 passed: signed release rebuild/process restart preserved the production scope item"
