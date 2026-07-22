#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$SCRIPT_DIR/package_app.config"
LOCAL_CONFIG_PATH="$SCRIPT_DIR/package_app.local.config"
DIST_ROOT="$ROOT_DIR/dist"
PUBSPEC_PATH="$ROOT_DIR/pubspec.yaml"
FULL_PACKAGE_TARGETS="android-arm64,macos-arm64,macos-x64,windows-x64"
PACKAGE_OUTPUT_DIR=""
PACKAGE_OUTPUT_KIND=""

log() {
  printf '[package-app] %s\n' "$*"
}

fail() {
  printf '[package-app] error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: scripts/package_app.sh [--primary-tenant-domain DOMAIN]

Dispatch the pinned GitHub Actions package workflow, wait for its exact run,
and verify its exact aggregate artifact. A complete four-target run replaces
dist/<version>/ and dist/latest.json; a target subset is kept under
dist/validation/<version>+<build>/<request-id>/. The script never changes
pubspec.yaml or builds locally.

Options:
  --primary-tenant-domain DOMAIN  Override the built-in primary tenant domain.
  -h, --help                      Show this help.
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

require_config_var() {
  local name="$1"
  [[ "${!name+x}" ]] || fail "missing required config value: $name"
  [[ -n "${!name}" ]] || fail "config value must not be empty: $name"
}

validate_no_newline() {
  local name="$1"
  local value="$2"
  case "$value" in
    *$'\n'*|*$'\r'*) fail "$name must not contain newline characters" ;;
  esac
}

trim_trailing_slash() {
  local value="$1"
  while [[ "${value%/}" != "$value" ]]; do
    value="${value%/}"
  done
  printf '%s\n' "$value"
}

derive_release_base_url() {
  local domain="$1"
  case "$domain" in
    http://*|https://*) trim_trailing_slash "$domain" ;;
    */*) fail "PACKAGE_RELEASE_DOMAIN must be a hostname or full http(s) URL" ;;
    *) printf 'https://%s\n' "$domain" ;;
  esac
}

validate_primary_tenant_domain() {
  local domain="$1"
  if [[ "${#domain}" -gt 253 ]] ||
    [[ ! "$domain" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$ ]]; then
    fail "PACKAGE_PRIMARY_TENANT_DOMAIN must be a lowercase hostname without scheme, port, or path"
  fi
}

resolve_repo_path() {
  local value="$1"
  case "$value" in
    /*) printf '%s\n' "$value" ;;
    *) printf '%s/%s\n' "$ROOT_DIR" "$value" ;;
  esac
}

install_aggregate_output() {
  local download_root="$1"
  local dist_root="$2"
  local version="$3"
  local build_number="$4"
  local app_ref="$5"
  local core_ref="$6"
  local anp_ref="$7"
  local normalized_targets="$8"
  local request_id="$9"
  local download_base_url="${10}"
  local download_page_url="${11}"
  local manifest_path="$download_root/package-manifest.json"
  local latest_path="$download_root/latest.json"
  local prepared_dir="$download_root/.prepared-$request_id"

  python3 - \
    "$manifest_path" \
    "$latest_path" \
    "$download_root" \
    "$prepared_dir" \
    "$version" \
    "$build_number" \
    "$app_ref" \
    "$core_ref" \
    "$anp_ref" \
    "$request_id" \
    "$normalized_targets" \
    "$FULL_PACKAGE_TARGETS" \
    "$download_base_url" \
    "$download_page_url" <<'PY'
import datetime, hashlib, json, pathlib, shutil, sys

manifest_path = pathlib.Path(sys.argv[1])
latest_path = pathlib.Path(sys.argv[2])
root = pathlib.Path(sys.argv[3])
prepared = pathlib.Path(sys.argv[4])
expected = {
    "version": sys.argv[5],
    "buildNumber": int(sys.argv[6]),
    "sourceRefs": {"app": sys.argv[7], "imCore": sys.argv[8], "anp": sys.argv[9]},
    "requestId": sys.argv[10],
}
normalized_targets = sys.argv[11]
targets = normalized_targets.split(",")
is_complete_release = normalized_targets == sys.argv[12]
expected_package_set = "release" if is_complete_release else "validation"
download_base_url = sys.argv[13].rstrip("/")
download_page_url = sys.argv[14]

if not manifest_path.is_file():
    raise SystemExit("downloaded aggregate is missing package-manifest.json")
manifest_bytes = manifest_path.read_bytes()
if is_complete_release:
    if not latest_path.is_file():
        raise SystemExit("complete release aggregate is missing latest.json")
    if latest_path.read_bytes() != manifest_bytes:
        raise SystemExit("downloaded latest.json does not match package-manifest.json")
elif latest_path.exists():
    raise SystemExit("validation aggregate must not contain latest.json")

manifest = json.loads(manifest_bytes.decode("utf-8"))
if manifest.get("schemaVersion") != 1:
    raise SystemExit("aggregate manifest must use schemaVersion 1")
if manifest.get("packageSet") != expected_package_set:
    raise SystemExit("aggregate manifest packageSet does not match selected targets")
if manifest.get("complete") is not is_complete_release:
    raise SystemExit("aggregate manifest complete does not match selected targets")
for key, value in expected.items():
    if manifest.get(key) != value:
        raise SystemExit(f"aggregate manifest {key} does not match dispatch input")
published_at = manifest.get("publishedAt")
try:
    parsed_published_at = datetime.datetime.fromisoformat(
        published_at.replace("Z", "+00:00")
    )
except (AttributeError, ValueError) as error:
    raise SystemExit("aggregate manifest publishedAt must be ISO-8601") from error
if not published_at.endswith("Z") or parsed_published_at.utcoffset() != datetime.timedelta(0):
    raise SystemExit("aggregate manifest publishedAt must be UTC")
for key in ("releaseNotesUrl", "githubReleaseUrl"):
    if manifest.get(key) != download_page_url:
        raise SystemExit(f"aggregate manifest {key} does not match dispatch input")
artifacts = manifest.get("artifacts")
if not isinstance(artifacts, dict) or list(artifacts) != targets:
    raise SystemExit("aggregate manifest targets do not match dispatch order")

package_files = []
for target, entry in artifacts.items():
    if not isinstance(entry, dict):
        raise SystemExit(f"invalid artifact entry for {target}")
    filename = entry.get("filename", "")
    if (
        not filename
        or pathlib.PurePath(filename).name != filename
        or filename in {"package-manifest.json", "latest.json"}
    ):
        raise SystemExit(f"invalid filename for {target}")
    package = root / filename
    if not package.is_file():
        raise SystemExit(f"missing downloaded package for {target}: {filename}")
    content = package.read_bytes()
    if len(content) != entry.get("sizeBytes"):
        raise SystemExit(f"size mismatch for {target}")
    if hashlib.sha256(content).hexdigest() != entry.get("sha256"):
        raise SystemExit(f"SHA-256 mismatch for {target}")
    package_files.append(package)

def platform_entry(target):
    artifact = artifacts[target]
    return {
        "downloadUrl": f"{download_base_url}/{expected['version']}/{artifact['filename']}",
        "sha256": artifact["sha256"],
    }

expected_platforms = {}
if "android-arm64" in artifacts:
    expected_platforms["android"] = platform_entry("android-arm64")
default_mac = "macos-arm64" if "macos-arm64" in artifacts else (
    "macos-x64" if "macos-x64" in artifacts else None
)
if default_mac:
    expected_platforms["macos"] = platform_entry(default_mac)
for target in ("macos-arm64", "macos-x64", "windows-x64"):
    if target in artifacts:
        expected_platforms[target] = platform_entry(target)
if manifest.get("platforms") != expected_platforms:
    raise SystemExit("aggregate manifest platforms do not match selected artifacts")

if prepared.exists():
    raise SystemExit(f"local package staging path already exists: {prepared}")
prepared.mkdir()
for package in package_files:
    shutil.copy2(package, prepared / package.name)
shutil.copy2(manifest_path, prepared / manifest_path.name)
if is_complete_release:
    shutil.copy2(latest_path, prepared / latest_path.name)
PY

  if [[ "$normalized_targets" == "$FULL_PACKAGE_TARGETS" ]]; then
    publish_release_output \
      "$prepared_dir" \
      "$dist_root" \
      "$version" \
      "$request_id"
    PACKAGE_OUTPUT_DIR="$dist_root/$version"
    PACKAGE_OUTPUT_KIND="release"
    return 0
  fi

  publish_validation_output \
    "$prepared_dir" \
    "$dist_root" \
    "$version+$build_number" \
    "$request_id"
  PACKAGE_OUTPUT_DIR="$dist_root/validation/$version+$build_number/$request_id"
  PACKAGE_OUTPUT_KIND="validation"
}

publish_validation_output() {
  local prepared_dir="$1"
  local dist_root="$2"
  local version_build="$3"
  local request_id="$4"
  local parent_dir="$dist_root/validation/$version_build"
  local output_dir="$parent_dir/$request_id"
  local stage_dir="$parent_dir/.$request_id.tmp"

  if [[ -e "$output_dir" || -e "$stage_dir" ]]; then
    printf '[package-app] error: validation output already exists for request %s\n' \
      "$request_id" >&2
    return 1
  fi
  mkdir -p "$parent_dir"
  if ! cp -R "$prepared_dir" "$stage_dir"; then
    rm -rf "$stage_dir"
    return 1
  fi
  if ! mv "$stage_dir" "$output_dir"; then
    rm -rf "$stage_dir"
    return 1
  fi
}

publish_release_output() (
  local prepared_dir="$1"
  local dist_root="$2"
  local version="$3"
  local request_id="$4"
  local output_dir="$dist_root/$version"
  local stage_dir="$dist_root/.package-stage-$request_id"
  local backup_dir="$dist_root/.package-backup-$request_id"
  local latest_temp="$dist_root/.latest-$request_id.tmp"
  local latest_backup="$dist_root/.latest-backup-$request_id"
  local had_previous_output="false"
  local had_previous_latest="false"
  local installed_output="false"
  local installed_latest="false"
  local committed="false"

  rollback_release_output() {
    local status="$?"
    local rollback_failed="false"
    trap - EXIT INT TERM HUP
    set +e

    if [[ "$committed" != "true" ]]; then
      if [[ "$installed_latest" == "true" ]]; then
        if [[ "$had_previous_latest" == "true" ]]; then
          if ! mv -f "$latest_backup" "$dist_root/latest.json"; then
            rollback_failed="true"
          fi
        elif ! rm -f "$dist_root/latest.json"; then
          rollback_failed="true"
        fi
      fi
      if [[ "$installed_output" == "true" ]] &&
        ! rm -rf "$output_dir"; then
        rollback_failed="true"
      fi
      if [[ "$had_previous_output" == "true" && -e "$backup_dir" ]] &&
        ! mv "$backup_dir" "$output_dir"; then
        rollback_failed="true"
      fi
    fi

    rm -rf "$stage_dir" "$latest_temp"
    if [[ "$rollback_failed" != "true" && -e "$latest_backup" ]] &&
      ! rm -f "$latest_backup"; then
      rollback_failed="true"
    fi
    if [[ "$rollback_failed" == "true" ]]; then
      printf '[package-app] error: release rollback failed; inspect %s and %s\n' \
        "$backup_dir" "$latest_backup" >&2
      exit 1
    fi
    exit "$status"
  }

  mkdir -p "$dist_root"
  if [[ -e "$stage_dir" || -e "$backup_dir" || -e "$latest_temp" ||
    -e "$latest_backup" ]]; then
    printf '[package-app] error: release staging path already exists for request %s\n' \
      "$request_id" >&2
    return 1
  fi
  trap rollback_release_output EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  cp -R "$prepared_dir" "$stage_dir"
  cp "$stage_dir/latest.json" "$latest_temp"
  rm "$stage_dir/latest.json"

  if [[ -e "$output_dir" ]]; then
    had_previous_output="true"
    mv "$output_dir" "$backup_dir"
  fi
  if [[ -e "$dist_root/latest.json" ]]; then
    had_previous_latest="true"
    cp "$dist_root/latest.json" "$latest_backup"
  fi

  installed_output="true"
  mv "$stage_dir" "$output_dir"
  installed_latest="true"
  mv -f "$latest_temp" "$dist_root/latest.json"
  committed="true"
  trap - EXIT INT TERM HUP

  if [[ "$had_previous_output" == "true" ]]; then
    rm -rf "$backup_dir" ||
      printf '[package-app] warning: could not remove release backup %s\n' \
        "$backup_dir" >&2
  fi
  if [[ "$had_previous_latest" == "true" ]]; then
    rm -f "$latest_backup" ||
      printf '[package-app] warning: could not remove latest backup %s\n' \
        "$latest_backup" >&2
  fi
)

main() {
cd "$ROOT_DIR"

PACKAGE_PRIMARY_TENANT_DOMAIN_OVERRIDE=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --primary-tenant-domain)
      [[ "$#" -ge 2 ]] || fail "--primary-tenant-domain requires a value"
      PACKAGE_PRIMARY_TENANT_DOMAIN_OVERRIDE="$2"
      shift 2
      ;;
    --primary-tenant-domain=*)
      PACKAGE_PRIMARY_TENANT_DOMAIN_OVERRIDE="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -f "$CONFIG_PATH" ]] || fail "missing config file: $CONFIG_PATH"
# shellcheck source=scripts/package_app.config
source "$CONFIG_PATH"
if [[ -f "$LOCAL_CONFIG_PATH" ]]; then
  # shellcheck source=scripts/package_app.local.config
  source "$LOCAL_CONFIG_PATH"
fi
if [[ -n "$PACKAGE_PRIMARY_TENANT_DOMAIN_OVERRIDE" ]]; then
  PACKAGE_PRIMARY_TENANT_DOMAIN="$PACKAGE_PRIMARY_TENANT_DOMAIN_OVERRIDE"
fi

for name in \
  PACKAGE_RELEASE_DOMAIN \
  PACKAGE_PRIMARY_TENANT_DOMAIN \
  PACKAGE_TARGETS \
  PACKAGE_VERSION_BUMP \
  PACKAGE_WORKFLOW_FILE \
  PACKAGE_RUN_DISCOVERY_TIMEOUT_SECONDS; do
  require_config_var "$name"
  validate_no_newline "$name" "${!name}"
done
[[ "$PACKAGE_VERSION_BUMP" == "none" ]] ||
  fail "PACKAGE_VERSION_BUMP must be none; commit the version before packaging"
[[ "$PACKAGE_RUN_DISCOVERY_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] ||
  fail "PACKAGE_RUN_DISCOVERY_TIMEOUT_SECONDS must be a positive integer"
validate_primary_tenant_domain "$PACKAGE_PRIMARY_TENANT_DOMAIN"

require_cmd awk
require_cmd gh
require_cmd git
require_cmd python3

SDK_REPO_DIR="$(resolve_repo_path "${PACKAGE_SDK_REPO_DIR:-../awiki-cli-rs2}")"
ANP_RELEASE_CONFIG="$SDK_REPO_DIR/scripts/release/cli/release-config.json"
[[ -f "$ANP_RELEASE_CONFIG" ]] ||
  fail "Core ANP release config is missing: $ANP_RELEASE_CONFIG"

PACKAGE_TARGET_LIST=()
target_enabled() {
  local expected="$1"
  local target
  for target in ${PACKAGE_TARGET_LIST[@]+"${PACKAGE_TARGET_LIST[@]}"}; do
    [[ "$target" == "$expected" ]] && return 0
  done
  return 1
}

parse_package_targets() {
  local raw="${1//,/ }"
  local target
  for target in $raw; do
    case "$target" in
      android-arm64|macos-arm64|macos-x64|windows-x64)
        target_enabled "$target" || PACKAGE_TARGET_LIST+=("$target")
        ;;
      *) fail "PACKAGE_TARGETS contains unsupported target: $target" ;;
    esac
  done
  [[ "${#PACKAGE_TARGET_LIST[@]}" -gt 0 ]] ||
    fail "PACKAGE_TARGETS must include at least one target"
}
parse_package_targets "$PACKAGE_TARGETS"

NORMALIZED_TARGETS=""
for target in android-arm64 macos-arm64 macos-x64 windows-x64; do
  if target_enabled "$target"; then
    if [[ -n "$NORMALIZED_TARGETS" ]]; then
      NORMALIZED_TARGETS="$NORMALIZED_TARGETS,$target"
    else
      NORMALIZED_TARGETS="$target"
    fi
  fi
done

resolve_source_ref() {
  local label="$1"
  local repo_dir="$2"
  local ref
  ref="$(git -C "$repo_dir" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" ||
    fail "$label is not a readable Git checkout: $repo_dir"
  [[ "$ref" =~ ^[0-9a-f]{40}$ ]] || fail "$label HEAD is not a full commit SHA"
  printf '%s\n' "$ref"
}

require_clean_source_tree() {
  local label="$1"
  local repo_dir="$2"
  local status
  status="$(git -C "$repo_dir" status --porcelain --untracked-files=normal 2>/dev/null)" ||
    fail "$label is not a readable Git checkout: $repo_dir"
  [[ -z "$status" ]] ||
    fail "$label source tree must be clean before packaging; commit or remove local changes"
}

APP_SOURCE_REMOTE=""
APP_SOURCE_BRANCH=""
require_exact_upstream_push() {
  local label="$1"
  local repo_dir="$2"
  local expected_ref="$3"
  local upstream remote remote_branch remote_ref
  upstream="$(git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" ||
    fail "$label branch has no upstream; push it with --set-upstream first"
  remote="${upstream%%/*}"
  remote_branch="${upstream#*/}"
  [[ -n "$remote" && -n "$remote_branch" && "$remote_branch" != "$upstream" ]] ||
    fail "$label upstream is invalid: $upstream"
  remote_ref="$(
    git -C "$repo_dir" ls-remote --heads "$remote" "refs/heads/$remote_branch" |
      awk 'NR == 1 { print $1 }'
  )"
  [[ "$remote_ref" == "$expected_ref" ]] ||
    fail "$label HEAD $expected_ref is not the exact tip of $upstream"
  if [[ "$repo_dir" == "$ROOT_DIR" ]]; then
    APP_SOURCE_REMOTE="$remote"
    APP_SOURCE_BRANCH="$remote_branch"
  fi
}

resolve_workflow_ref() {
  local repository="$1"
  local branch
  branch="$(
    gh repo view "$repository" \
      --json defaultBranchRef \
      --jq '.defaultBranchRef.name'
  )" || fail "cannot resolve the default workflow branch for $repository"
  validate_no_newline "GitHub default workflow branch" "$branch"
  [[ -n "$branch" ]] ||
    fail "GitHub repository $repository does not have a default workflow branch"
  printf '%s\n' "$branch"
}

read_pubspec_version() {
  local raw
  raw="$(awk '/^version:[[:space:]]*/ {print $2; exit}' "$PUBSPEC_PATH")"
  [[ "$raw" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?\+[1-9][0-9]*$ ]] ||
    fail "pubspec.yaml version must use semantic-version+positive-build format"
  printf '%s\n' "$raw"
}

read_anp_ref() {
  python3 - "$ANP_RELEASE_CONFIG" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle).get("anp_commit", "")
if not re.fullmatch(r"[0-9a-f]{40}", value):
    raise SystemExit("release-config.json anp_commit must be a lowercase 40-character SHA")
print(value)
PY
}

APP_SOURCE_REF="$(resolve_source_ref "AWiki Me" "$ROOT_DIR")"
IM_CORE_SOURCE_REF="$(resolve_source_ref "IM Core" "$SDK_REPO_DIR")"
ANP_SOURCE_REF="$(read_anp_ref)"
if [[ -n "${PACKAGE_ANP_SOURCE_REF:-}" && "$ANP_SOURCE_REF" != "$PACKAGE_ANP_SOURCE_REF" ]]; then
  fail "Core release config ANP ref $ANP_SOURCE_REF does not match PACKAGE_ANP_SOURCE_REF $PACKAGE_ANP_SOURCE_REF"
fi
require_clean_source_tree "AWiki Me" "$ROOT_DIR"
require_clean_source_tree "IM Core" "$SDK_REPO_DIR"
require_exact_upstream_push "AWiki Me" "$ROOT_DIR" "$APP_SOURCE_REF"
require_exact_upstream_push "IM Core" "$SDK_REPO_DIR" "$IM_CORE_SOURCE_REF"

CURRENT_VERSION="$(read_pubspec_version)"
VERSION_NAME="${CURRENT_VERSION%%+*}"
BUILD_NUMBER="${CURRENT_VERSION##*+}"
RELEASE_BASE_URL="$(derive_release_base_url "$PACKAGE_RELEASE_DOMAIN")"
DOWNLOAD_BASE_URL="$RELEASE_BASE_URL/downloads/awiki-me"
if [[ -n "${PACKAGE_UPDATE_MANIFEST_PUBLIC_URL:-}" ]]; then
  case "$PACKAGE_UPDATE_MANIFEST_PUBLIC_URL" in
    */latest.json) DOWNLOAD_BASE_URL="${PACKAGE_UPDATE_MANIFEST_PUBLIC_URL%/latest.json}" ;;
    *) fail "PACKAGE_UPDATE_MANIFEST_PUBLIC_URL must end with /latest.json" ;;
  esac
fi
DOWNLOAD_PAGE_URL="${PACKAGE_DOWNLOAD_PAGE_URL:-$RELEASE_BASE_URL/#download}"

REMOTE_URL="$(git -C "$ROOT_DIR" remote get-url "$APP_SOURCE_REMOTE")"
REPOSITORY="$(
  printf '%s\n' "$REMOTE_URL" |
    sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##'
)"
[[ "$REPOSITORY" =~ ^[^/]+/[^/]+$ ]] ||
  fail "cannot derive GitHub repository from remote URL: $REMOTE_URL"

gh auth status --hostname github.com >/dev/null 2>&1 ||
  fail "GitHub CLI is not authenticated for github.com"
WORKFLOW_REF="$(resolve_workflow_ref "$REPOSITORY")"

REQUEST_ID="$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"

log "workflow:        $PACKAGE_WORKFLOW_FILE"
log "repository:      $REPOSITORY"
log "workflow ref:    $WORKFLOW_REF"
log "App source:      $APP_SOURCE_BRANCH@$APP_SOURCE_REF"
log "request ID:      $REQUEST_ID"
log "version:         $VERSION_NAME+$BUILD_NUMBER"
log "targets:         $NORMALIZED_TARGETS"
log "App source ref:  $APP_SOURCE_REF"
log "Core source ref: $IM_CORE_SOURCE_REF"
log "ANP source ref:  $ANP_SOURCE_REF"

gh workflow run "$PACKAGE_WORKFLOW_FILE" \
  --repo "$REPOSITORY" \
  --ref "$WORKFLOW_REF" \
  --raw-field "request_id=$REQUEST_ID" \
  --raw-field "app_ref=$APP_SOURCE_REF" \
  --raw-field "core_ref=$IM_CORE_SOURCE_REF" \
  --raw-field "anp_ref=$ANP_SOURCE_REF" \
  --raw-field "targets=$NORMALIZED_TARGETS" \
  --raw-field "version=$VERSION_NAME" \
  --raw-field "build_number=$BUILD_NUMBER" \
  --raw-field "primary_tenant_domain=$PACKAGE_PRIMARY_TENANT_DOMAIN" \
  --raw-field "download_base_url=$DOWNLOAD_BASE_URL" \
  --raw-field "download_page_url=$DOWNLOAD_PAGE_URL"

find_run_id() {
  gh run list \
    --repo "$REPOSITORY" \
    --workflow "$PACKAGE_WORKFLOW_FILE" \
    --branch "$WORKFLOW_REF" \
    --event workflow_dispatch \
    --limit 50 \
    --json databaseId,displayTitle |
    python3 -c '
import json, sys
request_id = sys.argv[1]
matches = [str(run["databaseId"]) for run in json.load(sys.stdin)
           if request_id in str(run.get("displayTitle", ""))]
if len(matches) == 1:
    print(matches[0])
' "$REQUEST_ID"
}

RUN_ID=""
DISCOVERY_STARTED="$(date +%s)"
while [[ -z "$RUN_ID" ]]; do
  RUN_ID="$(find_run_id)"
  if [[ -n "$RUN_ID" ]]; then
    break
  fi
  NOW="$(date +%s)"
  if [[ $((NOW - DISCOVERY_STARTED)) -ge "$PACKAGE_RUN_DISCOVERY_TIMEOUT_SECONDS" ]]; then
    fail "timed out locating workflow run for request $REQUEST_ID"
  fi
  sleep 3
done

log "watching run:    $RUN_ID"
gh run watch "$RUN_ID" --repo "$REPOSITORY" --compact --exit-status

TEMP_DOWNLOAD="$(mktemp -d)"
trap 'rm -rf "$TEMP_DOWNLOAD"' EXIT
AGGREGATE_ARTIFACT="awiki-me-packages-$REQUEST_ID"
gh run download "$RUN_ID" \
  --repo "$REPOSITORY" \
  --name "$AGGREGATE_ARTIFACT" \
  --dir "$TEMP_DOWNLOAD"

install_aggregate_output \
  "$TEMP_DOWNLOAD" \
  "$DIST_ROOT" \
  "$VERSION_NAME" \
  "$BUILD_NUMBER" \
  "$APP_SOURCE_REF" \
  "$IM_CORE_SOURCE_REF" \
  "$ANP_SOURCE_REF" \
  "$NORMALIZED_TARGETS" \
  "$REQUEST_ID" \
  "$DOWNLOAD_BASE_URL" \
  "$DOWNLOAD_PAGE_URL"

log "done"
log "output:           $PACKAGE_OUTPUT_DIR"
if [[ "$PACKAGE_OUTPUT_KIND" == "release" ]]; then
  log "package manifest: $PACKAGE_OUTPUT_DIR/package-manifest.json"
  log "latest:           $DIST_ROOT/latest.json"
else
  log "validation manifest: $PACKAGE_OUTPUT_DIR/package-manifest.json"
  log "global latest:       unchanged"
fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
