#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$SCRIPT_DIR/package_app.config"
LOCAL_CONFIG_PATH="$SCRIPT_DIR/package_app.local.config"
DIST_ROOT="$ROOT_DIR/dist"
PUBSPEC_PATH="$ROOT_DIR/pubspec.yaml"
cd "$ROOT_DIR"

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
download the aggregate artifact, verify it, and write dist/<version>/ plus
dist/latest.json. The script never changes pubspec.yaml or builds locally.

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
require_cmd shasum

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

UPSTREAM_REMOTE=""
UPSTREAM_BRANCH=""
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
    UPSTREAM_REMOTE="$remote"
    UPSTREAM_BRANCH="$remote_branch"
  fi
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

REMOTE_URL="$(git -C "$ROOT_DIR" remote get-url "$UPSTREAM_REMOTE")"
REPOSITORY="$(
  printf '%s\n' "$REMOTE_URL" |
    sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##'
)"
[[ "$REPOSITORY" =~ ^[^/]+/[^/]+$ ]] ||
  fail "cannot derive GitHub repository from remote URL: $REMOTE_URL"

gh auth status --hostname github.com >/dev/null 2>&1 ||
  fail "GitHub CLI is not authenticated for github.com"

REQUEST_ID="$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"

log "workflow:        $PACKAGE_WORKFLOW_FILE"
log "repository:      $REPOSITORY"
log "workflow ref:    $UPSTREAM_BRANCH"
log "request ID:      $REQUEST_ID"
log "version:         $VERSION_NAME+$BUILD_NUMBER"
log "targets:         $NORMALIZED_TARGETS"
log "App source ref:  $APP_SOURCE_REF"
log "Core source ref: $IM_CORE_SOURCE_REF"
log "ANP source ref:  $ANP_SOURCE_REF"

gh workflow run "$PACKAGE_WORKFLOW_FILE" \
  --repo "$REPOSITORY" \
  --ref "$UPSTREAM_BRANCH" \
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
    --branch "$UPSTREAM_BRANCH" \
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

python3 - \
  "$TEMP_DOWNLOAD/package-manifest.json" \
  "$TEMP_DOWNLOAD" \
  "$VERSION_NAME" \
  "$BUILD_NUMBER" \
  "$APP_SOURCE_REF" \
  "$IM_CORE_SOURCE_REF" \
  "$ANP_SOURCE_REF" \
  "$NORMALIZED_TARGETS" <<'PY'
import hashlib, json, pathlib, re, sys

manifest_path = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
expected = {
    "version": sys.argv[3],
    "buildNumber": int(sys.argv[4]),
    "sourceRefs": {"app": sys.argv[5], "imCore": sys.argv[6], "anp": sys.argv[7]},
}
targets = sys.argv[8].split(",")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
if manifest.get("schemaVersion") != 1:
    raise SystemExit("aggregate manifest must use schemaVersion 1")
for key, value in expected.items():
    if manifest.get(key) != value:
        raise SystemExit(f"aggregate manifest {key} does not match dispatch input")
artifacts = manifest.get("artifacts")
if not isinstance(artifacts, dict) or list(artifacts) != targets:
    raise SystemExit("aggregate manifest targets do not match dispatch order")
for target, entry in artifacts.items():
    filename = entry.get("filename", "")
    if not filename or pathlib.PurePath(filename).name != filename:
        raise SystemExit(f"invalid filename for {target}")
    package = root / filename
    if not package.is_file():
        raise SystemExit(f"missing downloaded package for {target}: {filename}")
    content = package.read_bytes()
    if len(content) != entry.get("sizeBytes"):
        raise SystemExit(f"size mismatch for {target}")
    if hashlib.sha256(content).hexdigest() != entry.get("sha256"):
        raise SystemExit(f"SHA-256 mismatch for {target}")
PY

OUTPUT_DIR="$DIST_ROOT/$VERSION_NAME"
mkdir -p "$OUTPUT_DIR"
python3 - "$TEMP_DOWNLOAD/package-manifest.json" <<'PY' |
import json, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
for artifact in manifest["artifacts"].values():
    print(artifact["filename"])
PY
while IFS= read -r filename; do
  cp "$TEMP_DOWNLOAD/$filename" "$OUTPUT_DIR/$filename"
done
cp "$TEMP_DOWNLOAD/package-manifest.json" "$OUTPUT_DIR/package-manifest.json"
cp "$TEMP_DOWNLOAD/latest.json" "$DIST_ROOT/latest.json"

log "done"
log "output:           $OUTPUT_DIR"
log "package manifest: $OUTPUT_DIR/package-manifest.json"
log "latest:           $DIST_ROOT/latest.json"
