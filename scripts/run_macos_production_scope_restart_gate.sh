#!/usr/bin/env bash
set -euo pipefail

# NATIVE-E2E-002: one prepared signed production App survives process restart.

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

# shellcheck source=scripts/lib/macos_signing.sh
source "$ROOT_DIR/scripts/lib/macos_signing.sh"

mode=""
artifact_root=""
artifact_manifest=""
report_dir=""
run_id=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepare-only) mode="prepare" ;;
    --execute) mode="execute" ;;
    --artifact-root=*) artifact_root=${1#*=} ;;
    --artifact-manifest=*) artifact_manifest=${1#*=} ;;
    --report-dir=*) report_dir=${1#*=} ;;
    --run-id=*) run_id=${1#*=} ;;
    *)
      echo "production_scope_restart_gate_failed: invalid argument" >&2
      exit 2
      ;;
  esac
  shift
done

[[ "$(uname -s)" == "Darwin" ]] || {
  echo "production_scope_restart_gate_failed: macOS required" >&2
  exit 2
}
[[ "$mode" == "prepare" || "$mode" == "execute" ]] || {
  echo "production_scope_restart_gate_failed: select prepare or execute" >&2
  exit 2
}
: "${AWIKI_MACOS_DEVELOPMENT_TEAM:?set AWIKI_MACOS_DEVELOPMENT_TEAM to the matching Team ID}"

bundle_digest() {
  python3 - "$1" <<'PY'
import hashlib
import os
import pathlib
import stat
import sys

root = pathlib.Path(sys.argv[1]).resolve()
digest = hashlib.sha256()
for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
    relative = path.relative_to(root).as_posix().encode()
    digest.update(relative)
    digest.update(b"\0")
    digest.update(str(stat.S_IMODE(path.lstat().st_mode)).encode())
    digest.update(b"\0")
    if path.is_symlink():
        digest.update(b"link\0")
        digest.update(os.readlink(path).encode())
    elif path.is_file():
        digest.update(b"file\0")
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    elif path.is_dir():
        digest.update(b"dir\0")
    digest.update(b"\0")
print(digest.hexdigest())
PY
}

prepare_artifact() {
  [[ -n "$artifact_root" ]] || {
    echo "production_scope_restart_gate_failed: artifact root required" >&2
    exit 2
  }
  : "${AWIKI_MACOS_SIGNING_IDENTITY:?set AWIKI_MACOS_SIGNING_IDENTITY to a stable codesigning identity}"
  command -v flutter >/dev/null || {
    echo "production_scope_restart_gate_failed: flutter unavailable" >&2
    exit 2
  }
  command -v pod >/dev/null || {
    echo "production_scope_restart_gate_failed: CocoaPods unavailable" >&2
    exit 2
  }
  local signing_fingerprint
  signing_fingerprint="$(awiki_resolve_codesigning_identity "$AWIKI_MACOS_SIGNING_IDENTITY")" || {
    echo "production_scope_restart_gate_failed: signing identity unavailable" >&2
    exit 2
  }

  local im_core_repo_dir
  im_core_repo_dir="${AWIKI_IM_CORE_REPO_DIR:-$ROOT_DIR/../awiki-cli-rs2}"
  im_core_repo_dir="$(cd "$im_core_repo_dir" 2>/dev/null && pwd)" || {
    echo "production_scope_restart_gate_failed: native dependency repository unavailable" >&2
    exit 2
  }
  local im_core_build_script="$im_core_repo_dir/scripts/flutter/build-sdk-native.sh"
  local im_core_xcframework="$im_core_repo_dir/packages/awiki_im_core/macos/Frameworks/AwikiImCore.xcframework"
  [[ -x "$im_core_build_script" ]] || {
    echo "production_scope_restart_gate_failed: native build script unavailable" >&2
    exit 2
  }
  local app_source_ref core_source_ref app_dirty=false core_dirty=false
  app_source_ref=$(git rev-parse --verify HEAD)
  core_source_ref=$(git -C "$im_core_repo_dir" rev-parse --verify HEAD)
  [[ -z "$(git status --porcelain=v1 --untracked-files=normal)" ]] || app_dirty=true
  [[ -z "$(git -C "$im_core_repo_dir" status --porcelain=v1 --untracked-files=normal)" ]] || core_dirty=true

  "$im_core_build_script" --macos-only || {
    echo "production_scope_restart_gate_failed: native dependency build failed" >&2
    exit 2
  }
  AWIKI_IM_CORE_REPO_DIR="$im_core_repo_dir" \
    "$ROOT_DIR/scripts/verify_im_core_native_artifact.sh" || {
    echo "production_scope_restart_gate_failed: native awiki_im_core provenance verification failed" >&2
    exit 2
  }

  local info_plist="$im_core_xcframework/Info.plist"
  [[ -f "$info_plist" ]] || {
    echo "production_scope_restart_gate_failed: native XCFramework missing" >&2
    exit 2
  }
  local library_path library
  library_path=$(/usr/libexec/PlistBuddy -c 'Print :AvailableLibraries:0:LibraryPath' "$info_plist")
  library=$(find "$im_core_xcframework" -mindepth 2 -maxdepth 2 -type f -name "$library_path" -print -quit)
  [[ -f "$library" ]] || {
    echo "production_scope_restart_gate_failed: native library missing" >&2
    exit 2
  }
  lipo "$library" -verify_arch arm64 x86_64 || {
    echo "production_scope_restart_gate_failed: native architecture matrix invalid" >&2
    exit 2
  }

  rm -rf build/macos/Build/Products/Release/XCFrameworkIntermediates/awiki_im_core
  if ! flutter build macos --config-only --release --no-pub \
    --target tests/e2e/flutter/native/production_scope_restart_probe.dart; then
    echo "production_scope_restart_gate_failed: release platform configuration generation failed" >&2
    exit 2
  fi
  if ! (cd macos && pod install); then
    echo "production_scope_restart_gate_failed: CocoaPods installation failed" >&2
    exit 2
  fi
  local podfile_lock_checksum
  podfile_lock_checksum=$(shasum -a 256 macos/Podfile.lock | awk '{print $1}')
  if ! flutter build macos --release --no-pub \
    --target tests/e2e/flutter/native/production_scope_restart_probe.dart; then
    echo "production_scope_restart_gate_failed: release App build failed" >&2
    exit 2
  fi
  local app_path
  app_path=$(find build/macos/Build/Products/Release -maxdepth 1 -type d -name '*.app' -print -quit)
  [[ -n "$app_path" ]] || {
    echo "production_scope_restart_gate_failed: release app missing" >&2
    exit 2
  }
  codesign --force --deep --options runtime --sign "$signing_fingerprint" "$app_path"
  awiki_verify_macos_app_signature "$app_path" "$AWIKI_MACOS_DEVELOPMENT_TEAM" "ai.awiki.awikime"
  [[ "$(shasum -a 256 macos/Podfile.lock | awk '{print $1}')" == "$podfile_lock_checksum" ]] || {
    echo "production_scope_restart_gate_failed: Podfile.lock changed" >&2
    exit 2
  }

  mkdir -p "$artifact_root"
  chmod 700 "$artifact_root"
  rm -rf "$artifact_root/AWikiMe.app"
  /usr/bin/ditto "$app_path" "$artifact_root/AWikiMe.app"
  local digest
  digest=$(bundle_digest "$artifact_root/AWikiMe.app")
  python3 - "$artifact_root/manifest.json" "$digest" "$app_source_ref" "$core_source_ref" \
    "$app_dirty" "$core_dirty" "$signing_fingerprint" "$AWIKI_MACOS_DEVELOPMENT_TEAM" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = {
    "schemaVersion": 1,
    "caseId": "NATIVE-E2E-002",
    "bundleRelativePath": "AWikiMe.app",
    "executableRelativePath": "Contents/MacOS/AWikiMe",
    "bundleId": "ai.awiki.awikime",
    "artifactSha256": sys.argv[2],
    "sourceRefs": {"awikiMe": sys.argv[3], "awikiCli": sys.argv[4]},
    "worktrees": {"awikiMeDirty": sys.argv[5] == "true", "awikiCliDirty": sys.argv[6] == "true"},
    "signingFingerprint": sys.argv[7],
    "developmentTeam": sys.argv[8],
    "architectures": ["arm64", "x86_64"],
    "nativeDependencyBuildCount": 1,
    "appBuildCount": 1,
    "podfileLockStable": True,
}
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
  echo "NATIVE-E2E-002 prepared: $artifact_root/manifest.json"
}

execute_artifact() {
  [[ -n "$artifact_manifest" && -n "$report_dir" && -n "$run_id" ]] || {
    echo "production_scope_restart_gate_failed: execute inputs required" >&2
    exit 2
  }
  local app_path expected_digest artifact_values
  artifact_values=$(python3 - "$artifact_manifest" "$AWIKI_MACOS_DEVELOPMENT_TEAM" <<'PY'
import json
import pathlib
import sys

manifest = pathlib.Path(sys.argv[1]).resolve()
payload = json.loads(manifest.read_text())
if payload.get("schemaVersion") != 1 or payload.get("caseId") != "NATIVE-E2E-002":
    raise SystemExit("native artifact manifest invalid")
if payload.get("developmentTeam") != sys.argv[2]:
    raise SystemExit("native artifact team mismatch")
if payload.get("nativeDependencyBuildCount") != 1 or payload.get("appBuildCount") != 1:
    raise SystemExit("native artifact build count invalid")
if payload.get("architectures") != ["arm64", "x86_64"] or payload.get("podfileLockStable") is not True:
    raise SystemExit("native artifact preparation evidence invalid")
relative = pathlib.Path(payload.get("bundleRelativePath", ""))
if relative.is_absolute() or ".." in relative.parts:
    raise SystemExit("native artifact path invalid")
app = (manifest.parent / relative).resolve()
app.relative_to(manifest.parent)
print(app)
print(payload.get("artifactSha256", ""))
PY
  )
  app_path=$(printf '%s\n' "$artifact_values" | sed -n '1p')
  expected_digest=$(printf '%s\n' "$artifact_values" | sed -n '2p')
  [[ -d "$app_path" && "$(bundle_digest "$app_path")" == "$expected_digest" ]] || {
    echo "production_scope_restart_gate_failed: prepared bundle digest mismatch" >&2
    exit 2
  }
  awiki_verify_macos_app_signature "$app_path" "$AWIKI_MACOS_DEVELOPMENT_TEAM" "ai.awiki.awikime"
  local executable
  executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Contents/Info.plist")
  local scope_id result_root cleanup_needed=true
  scope_id=$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
  )
  result_root=$(mktemp -d "${TMPDIR:-/tmp}/awiki-production-scope-gate.XXXXXX")
  cleanup() {
    if [[ "$cleanup_needed" == true ]]; then
      security delete-generic-password -s ai.awiki.awikime.scope-secrets \
        -a "scope/$scope_id" >/dev/null 2>&1 || true
    fi
    rm -rf "$result_root"
  }
  trap cleanup EXIT

  run_phase() {
    local phase=$1
    local result_path="$result_root/$phase.json"
    "$app_path/Contents/MacOS/$executable" \
      "--awiki-scope-probe-phase=$phase" \
      "--awiki-scope-probe-id=$scope_id" \
      "--awiki-scope-probe-result=$result_path"
    python3 - "$result_path" "$phase" <<'PY'
import json
import pathlib
import sys
actual = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected = {"case_id": "NATIVE-E2E-002", "phase": sys.argv[2], "status": "passed", "code": "ok"}
if actual != expected:
    raise SystemExit("production scope restart result mismatch")
PY
  }

  run_phase provision
  run_phase reopen
  run_phase cleanup
  cleanup_needed=false
  mkdir -p "$report_dir"
  chmod 700 "$report_dir"
  python3 - "$report_dir" "$run_id" <<'PY'
import datetime
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
run_id = sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
assertions = [
    "native_dependency_built_once", "architecture_matrix_validated", "podfile_lock_stable",
    "production_scope_provisioned", "independent_reopen_preserved_revision",
    "create_exclusive_already_exists", "cleanup_deleted_and_missing",
]
case = {
    "caseId": "NATIVE-E2E-002", "status": "passed", "startedAt": now, "finishedAt": now,
    "phases": assertions,
    "assertions": [{"assertionId": f"NATIVE-E2E-002:{value}", "status": "passed", "observedAt": now} for value in assertions],
}
(root / "case_attestation.json").write_text(json.dumps({
    "schemaVersion": 2, "scenario": "production-keychain", "runId": run_id, "cases": [case],
}, indent=2) + "\n")
(root / "resource_ledger.json").write_text(json.dumps({
    "schemaVersion": 1, "containsSecrets": False, "cleanupStatus": "cleaned",
    "resources": {"productionScopeItems": 0},
}, indent=2) + "\n")
(root / "timings.json").write_text(json.dumps({
    "schemaVersion": 2, "status": "passed", "platform": "macos", "mode": "real",
    "dryRun": False, "prepareOnly": False, "runId": run_id, "case": "production-keychain",
    "caseIds": ["NATIVE-E2E-002"], "passedCaseIds": ["NATIVE-E2E-002"],
    "caseResults": [case], "counts": {"declared": 1, "passed": 1},
    "attestation": {"schemaVersion": 2, "status": "verified"},
    "buildMetrics": {"executionBuildCommands": 0},
}, indent=2) + "\n")
PY
  echo "NATIVE-E2E-002 passed: prepared signed App preserved the production scope item"
}

if [[ "$mode" == "prepare" ]]; then
  prepare_artifact
else
  execute_artifact
fi
