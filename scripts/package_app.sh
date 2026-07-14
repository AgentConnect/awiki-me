#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$SCRIPT_DIR/package_app.config"
LOCAL_CONFIG_PATH="$SCRIPT_DIR/package_app.local.config"
SIGNING_LIB_PATH="$SCRIPT_DIR/lib/macos_signing.sh"
cd "$ROOT_DIR"

PACKAGE_APP_DISPLAY_NAME="AWikiMe"
PACKAGE_ANDROID_APP_ID="ai.awiki.awikime"
PACKAGE_MACOS_BUNDLE_ID="ai.awiki.awikime"
PACKAGE_PRODUCTION_SCOPE_SECRET_SERVICE="ai.awiki.awikime.scope-secrets"
PACKAGE_FLUTTER_BIN="flutter"
PACKAGE_SDK_REPO_DIR="../awiki-cli-rs2"
PACKAGE_ANDROID_EXPECTED_CERT_SHA256="F2:67:E9:18:57:54:ED:C1:2B:E5:69:69:1B:39:B9:EF:D4:EF:1E:CF:2D:7E:D8:18:81:42:69:B3:70:85:D8:75"
PACKAGE_ANDROID_BUILD_MODE="release"
PACKAGE_MACOS_BUILD_MODE="release"
XCODE_CONFIGURATION="Release"
DIST_ROOT="$ROOT_DIR/dist"
ANDROID_PLUGIN_REGISTRANT="$ROOT_DIR/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
ANDROID_PLUGIN_REGISTRANT_BACKUP=""
ANDROID_PLUGIN_REGISTRANT_EXISTED=0
FLUTTER_PUB_GET_DONE=0

PUBSPEC_PATH="$ROOT_DIR/pubspec.yaml"
PUBSPEC_BACKUP=""
PUBSPEC_WAS_UPDATED=0

log() {
  printf '[package-app] %s\n' "$*"
}

fail() {
  printf '[package-app] error: %s\n' "$*" >&2
  exit 1
}

on_exit() {
  local status="$1"
  if [[ "$status" -ne 0 && "$PUBSPEC_WAS_UPDATED" -eq 1 && -n "$PUBSPEC_BACKUP" && -f "$PUBSPEC_BACKUP" ]]; then
    cp "$PUBSPEC_BACKUP" "$PUBSPEC_PATH"
    log "restored pubspec.yaml version after failed build"
  fi
  if [[ -n "$ANDROID_PLUGIN_REGISTRANT_BACKUP" && -f "$ANDROID_PLUGIN_REGISTRANT_BACKUP" ]]; then
    if [[ "$ANDROID_PLUGIN_REGISTRANT_EXISTED" -eq 1 ]]; then
      mkdir -p "$(dirname "$ANDROID_PLUGIN_REGISTRANT")"
      cp "$ANDROID_PLUGIN_REGISTRANT_BACKUP" "$ANDROID_PLUGIN_REGISTRANT"
    else
      rm -f "$ANDROID_PLUGIN_REGISTRANT"
    fi
    rm -f "$ANDROID_PLUGIN_REGISTRANT_BACKUP"
  fi
  if [[ -n "$PUBSPEC_BACKUP" && -f "$PUBSPEC_BACKUP" ]]; then
    rm -f "$PUBSPEC_BACKUP"
  fi
}

trap 'on_exit $?' EXIT

usage() {
  cat <<'USAGE'
Usage: scripts/package_app.sh [--primary-tenant-domain DOMAIN]

Options:
  --primary-tenant-domain DOMAIN  Override the built-in AWiki tenant domain
                                  for this build only.
  -h, --help                      Show this help.
USAGE
}

PACKAGE_PRIMARY_TENANT_DOMAIN_OVERRIDE=""
PACKAGE_PRIMARY_TENANT_DOMAIN_OVERRIDE_SET=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --primary-tenant-domain)
      [[ "$#" -ge 2 ]] || fail "--primary-tenant-domain requires a value"
      PACKAGE_PRIMARY_TENANT_DOMAIN_OVERRIDE="$2"
      PACKAGE_PRIMARY_TENANT_DOMAIN_OVERRIDE_SET=1
      shift 2
      ;;
    --primary-tenant-domain=*)
      PACKAGE_PRIMARY_TENANT_DOMAIN_OVERRIDE="${1#*=}"
      PACKAGE_PRIMARY_TENANT_DOMAIN_OVERRIDE_SET=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -f "$CONFIG_PATH" ]] || fail "missing config file: $CONFIG_PATH"
# shellcheck source=scripts/package_app.config
source "$CONFIG_PATH"
if [[ -f "$LOCAL_CONFIG_PATH" ]]; then
  # shellcheck source=scripts/package_app.local.config
  source "$LOCAL_CONFIG_PATH"
fi
if [[ "$PACKAGE_PRIMARY_TENANT_DOMAIN_OVERRIDE_SET" -eq 1 ]]; then
  PACKAGE_PRIMARY_TENANT_DOMAIN="$PACKAGE_PRIMARY_TENANT_DOMAIN_OVERRIDE"
fi
[[ -f "$SIGNING_LIB_PATH" ]] || fail "missing signing library: $SIGNING_LIB_PATH"
# shellcheck source=scripts/lib/macos_signing.sh
source "$SIGNING_LIB_PATH"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

require_config_var() {
  local name="$1"
  if [[ ! "${!name+x}" ]]; then
    fail "missing required config value: $name"
  fi
}

require_non_empty_config_var() {
  local name="$1"
  require_config_var "$name"
  if [[ -z "${!name}" ]]; then
    fail "config value must not be empty: $name"
  fi
}

trim_trailing_slash() {
  local value="$1"
  while [[ "${value%/}" != "$value" ]]; do
    value="${value%/}"
  done
  printf '%s\n' "$value"
}

join_url() {
  local base path
  base="$(trim_trailing_slash "$1")"
  path="$2"
  while [[ "${path#/}" != "$path" ]]; do
    path="${path#/}"
  done
  printf '%s/%s\n' "$base" "$path"
}

derive_release_base_url() {
  local domain="$1"
  [[ -n "$domain" ]] || fail "PACKAGE_RELEASE_DOMAIN must not be empty"
  case "$domain" in
    http://*|https://*)
      trim_trailing_slash "$domain"
      ;;
    */*)
      fail "PACKAGE_RELEASE_DOMAIN must be a hostname or full http(s) URL"
      ;;
    *)
      printf 'https://%s\n' "$domain"
      ;;
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
  [[ -n "$value" ]] || fail "path config value must not be empty"
  case "$value" in
    /*)
      printf '%s\n' "$value"
      ;;
    *)
      printf '%s/%s\n' "$ROOT_DIR" "$value"
      ;;
  esac
}

validate_no_newline() {
  local name="$1"
  local value="$2"
  case "$value" in
    *$'\n'*|*$'\r'*)
      fail "$name must not contain newline characters"
      ;;
  esac
}

json_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  printf '"%s"' "$value"
}

PACKAGE_TARGET_LIST=()

target_enabled() {
  local expected="$1"
  local target
  for target in ${PACKAGE_TARGET_LIST[@]+"${PACKAGE_TARGET_LIST[@]}"}; do
    if [[ "$target" == "$expected" ]]; then
      return 0
    fi
  done
  return 1
}

needs_android() {
  target_enabled "android-arm64"
}

needs_macos() {
  target_enabled "macos-arm64" || target_enabled "macos-x64"
}

parse_package_targets() {
  local raw="$1"
  local token
  PACKAGE_TARGET_LIST=()

  raw="${raw//,/ }"
  for token in $raw; do
    case "$token" in
      android-arm64|macos-arm64|macos-x64)
        if ! target_enabled "$token"; then
          PACKAGE_TARGET_LIST+=("$token")
        fi
        ;;
      *)
        fail "PACKAGE_TARGETS contains unsupported target: $token"
        ;;
    esac
  done

  if [[ "${#PACKAGE_TARGET_LIST[@]}" -eq 0 ]]; then
    fail "PACKAGE_TARGETS must include at least one target"
  fi
}

target_description() {
  case "$1" in
    android-arm64)
      printf 'android-arm64 %s APK\n' "$PACKAGE_ANDROID_BUILD_MODE"
      ;;
    macos-arm64)
      printf 'macos-arm64 %s DMG\n' "$PACKAGE_MACOS_BUILD_MODE"
      ;;
    macos-x64)
      printf 'macos-x64 %s DMG\n' "$PACKAGE_MACOS_BUILD_MODE"
      ;;
    *)
      fail "unknown package target: $1"
      ;;
  esac
}

require_cmd python3

if [[ ! "${PACKAGE_TARGETS+x}" ]]; then
  PACKAGE_TARGETS="android-arm64,macos-arm64,macos-x64"
fi

for required_name in \
  PACKAGE_RELEASE_DOMAIN \
  PACKAGE_PRIMARY_TENANT_DOMAIN \
  PACKAGE_TARGETS \
  PACKAGE_ANDROID_STARTUP_SMOKE_TEST \
  PACKAGE_VERSION_BUMP \
  AWIKI_MACOS_SIGNING_IDENTITY \
  AWIKI_MACOS_DEVELOPMENT_TEAM; do
  require_config_var "$required_name"
done

require_non_empty_config_var PACKAGE_RELEASE_DOMAIN
require_non_empty_config_var PACKAGE_PRIMARY_TENANT_DOMAIN
require_non_empty_config_var PACKAGE_TARGETS
require_non_empty_config_var PACKAGE_ANDROID_STARTUP_SMOKE_TEST
require_non_empty_config_var PACKAGE_VERSION_BUMP

for value_name in \
  PACKAGE_RELEASE_DOMAIN \
  PACKAGE_PRIMARY_TENANT_DOMAIN \
  PACKAGE_UPDATE_MANIFEST_PUBLIC_URL \
  PACKAGE_DOWNLOAD_PAGE_URL \
  PACKAGE_TARGETS \
  PACKAGE_ANDROID_STARTUP_SMOKE_TEST \
  PACKAGE_VERSION_BUMP \
  AWIKI_MACOS_SIGNING_IDENTITY \
  AWIKI_MACOS_DEVELOPMENT_TEAM; do
  if [[ "${!value_name+x}" ]]; then
    validate_no_newline "$value_name" "${!value_name}"
  fi
done

validate_primary_tenant_domain "$PACKAGE_PRIMARY_TENANT_DOMAIN"

parse_package_targets "$PACKAGE_TARGETS"

case "$PACKAGE_VERSION_BUMP" in
  build|patch|minor|major|none)
    ;;
  *)
    fail "PACKAGE_VERSION_BUMP must be one of: build, patch, minor, major, none"
    ;;
esac

case "$PACKAGE_ANDROID_STARTUP_SMOKE_TEST" in
  auto|always|never)
    ;;
  *)
    fail "PACKAGE_ANDROID_STARTUP_SMOKE_TEST must be one of: auto, always, never"
    ;;
esac

PACKAGE_RELEASE_BASE_URL="$(derive_release_base_url "$PACKAGE_RELEASE_DOMAIN")"
PACKAGE_RELEASE_BASE_URL="$(trim_trailing_slash "$PACKAGE_RELEASE_BASE_URL")"
case "$PACKAGE_RELEASE_BASE_URL" in
  http://*|https://*) ;;
  *) fail "PACKAGE_RELEASE_DOMAIN must derive an http:// or https:// URL" ;;
esac

if [[ -z "${PACKAGE_UPDATE_MANIFEST_PUBLIC_URL:-}" ]]; then
  PACKAGE_UPDATE_MANIFEST_PUBLIC_URL="$(join_url "$PACKAGE_RELEASE_BASE_URL" "downloads/awiki-me/latest.json")"
fi
if [[ -z "${PACKAGE_DOWNLOAD_PAGE_URL:-}" ]]; then
  PACKAGE_DOWNLOAD_PAGE_URL="$(join_url "$PACKAGE_RELEASE_BASE_URL" "#download")"
fi
PACKAGE_UPDATE_MANIFEST_PUBLIC_URL="$(trim_trailing_slash "$PACKAGE_UPDATE_MANIFEST_PUBLIC_URL")"
PACKAGE_DOWNLOAD_PAGE_URL="$(trim_trailing_slash "$PACKAGE_DOWNLOAD_PAGE_URL")"

LATEST_MANIFEST="$DIST_ROOT/latest.json"
SDK_REPO_DIR="$(resolve_repo_path "$PACKAGE_SDK_REPO_DIR")"
SDK_NATIVE_BUILD_SCRIPT="$SDK_REPO_DIR/scripts/flutter/build-sdk-native.sh"

read_pubspec_version() {
  local raw
  raw="$(awk '/^version:[[:space:]]*/ {print $2; exit}' "$PUBSPEC_PATH")"
  [[ -n "$raw" ]] || fail "version not found in pubspec.yaml"
  [[ "$raw" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]] ||
    fail "pubspec.yaml version must use x.y.z+build format; got: $raw"
  printf '%s\n' "$raw"
}

compute_next_version() {
  local current="$1"
  [[ "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]] ||
    fail "invalid current version: $current"
  local major="${BASH_REMATCH[1]}"
  local minor="${BASH_REMATCH[2]}"
  local patch="${BASH_REMATCH[3]}"
  local build="${BASH_REMATCH[4]}"
  local next_build="$build"

  if [[ "$PACKAGE_VERSION_BUMP" != "none" ]]; then
    next_build=$((build + 1))
  fi

  case "$PACKAGE_VERSION_BUMP" in
    none|build)
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
  esac

  printf '%s.%s.%s+%s\n' "$major" "$minor" "$patch" "$next_build"
}

version_name() {
  printf '%s\n' "${1%%+*}"
}

build_number() {
  printf '%s\n' "${1##*+}"
}

download_base_url() {
  local manifest_url="$PACKAGE_UPDATE_MANIFEST_PUBLIC_URL"
  case "$manifest_url" in
    */latest.json)
      printf '%s\n' "${manifest_url%/latest.json}"
      ;;
    *)
      fail "PACKAGE_UPDATE_MANIFEST_PUBLIC_URL must end with /latest.json"
      ;;
  esac
}

read_latest_build_number() {
  [[ -f "$LATEST_MANIFEST" ]] || return 0
  sed -n 's/.*"buildNumber"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
    "$LATEST_MANIFEST" | head -1
}

write_pubspec_version() {
  local next_version_value="$1"
  local tmp
  tmp="$(mktemp)"
  awk -v next_version_value="$next_version_value" '
    BEGIN { done = 0 }
    /^version:[[:space:]]*/ && done == 0 {
      print "version: " next_version_value
      done = 1
      next
    }
    { print }
    END {
      if (done == 0) {
        exit 42
      }
    }
  ' "$PUBSPEC_PATH" > "$tmp" || {
    rm -f "$tmp"
    fail "failed to update pubspec.yaml version"
  }
  mv "$tmp" "$PUBSPEC_PATH"
}

write_properties_key() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$file" ]] && grep -q "^${key}=" "$file"; then
    awk -v key="$key" -v value="$value" '
      index($0, key "=") == 1 {
        print key "=" value
        next
      }
      { print }
    ' "$file" > "$tmp"
  else
    if [[ -f "$file" ]]; then
      cat "$file" > "$tmp"
    fi
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  fi
  mv "$tmp" "$file"
}

sync_android_local_version() {
  local local_properties="android/local.properties"
  [[ -f "$local_properties" ]] || fail "Android local.properties is missing; run flutter pub get once before packaging"
  write_properties_key "$local_properties" "flutter.versionName" "$VERSION_NAME"
  write_properties_key "$local_properties" "flutter.versionCode" "$BUILD_NUMBER"
}

check_source_identity() {
  grep -Fq "ScopeSecretChannel.production => '$PACKAGE_PRODUCTION_SCOPE_SECRET_SERVICE'" \
    lib/src/data/storage/platform_scope_secret_repository.dart ||
    fail "Dart production scope-secret service must stay $PACKAGE_PRODUCTION_SCOPE_SECRET_SERVICE"
  if needs_android; then
    grep -Fq "namespace = \"$PACKAGE_ANDROID_APP_ID\"" \
      android/app/build.gradle ||
      fail "android namespace must stay $PACKAGE_ANDROID_APP_ID"
    grep -Fq "applicationId = \"$PACKAGE_ANDROID_APP_ID\"" \
      android/app/build.gradle ||
      fail "android applicationId must stay $PACKAGE_ANDROID_APP_ID"
  fi
  if needs_macos; then
    grep -Fq "PRODUCT_BUNDLE_IDENTIFIER = $PACKAGE_MACOS_BUNDLE_ID" \
      macos/Runner/Configs/AppInfo.xcconfig ||
      fail "macOS PRODUCT_BUNDLE_IDENTIFIER must stay $PACKAGE_MACOS_BUNDLE_ID"
    grep -Fq "case \"$PACKAGE_PRODUCTION_SCOPE_SECRET_SERVICE\":" \
      macos/Runner/MainFlutterWindow.swift ||
      fail "macOS production scope-secret service must stay $PACKAGE_PRODUCTION_SCOPE_SECRET_SERVICE"
  fi
}

android_sdk_dir() {
  local candidates=()
  if [[ -n "${ANDROID_HOME:-}" ]]; then
    candidates+=("$ANDROID_HOME")
  fi
  if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
    candidates+=("$ANDROID_SDK_ROOT")
  fi
  local local_sdk
  local_sdk="$(sed -n 's/^sdk.dir=//p' android/local.properties 2>/dev/null | head -1 || true)"
  if [[ -n "$local_sdk" ]]; then
    candidates+=("$local_sdk")
  fi
  candidates+=("$HOME/Library/Android/sdk")

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate/build-tools" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
}

find_android_tool() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return
  fi
  local sdk
  sdk="$(android_sdk_dir || true)"
  [[ -n "$sdk" ]] || fail "Android SDK not found; cannot locate $name"
  local tool
  tool="$(
    find "$sdk/build-tools" -path "*/$name" -type f 2>/dev/null |
      awk -F/ '
        {
          path = $0
          version = $(NF - 1)
          split(version, parts, ".")
          printf "%08d%08d%08d %s\n", parts[1], parts[2], parts[3], path
        }
      ' |
      sort |
      tail -1 |
      cut -d' ' -f2-
  )"
  [[ -n "$tool" ]] || fail "$name not found under Android SDK build-tools"
  printf '%s\n' "$tool"
}

normalize_sha256() {
  tr '[:lower:]' '[:upper:]' | tr -d '[:space:]:'
}

file_size() {
  if stat -f%z "$1" >/dev/null 2>&1; then
    stat -f%z "$1"
  else
    stat -c%s "$1"
  fi
}

file_sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

prepare_android_release_sources() {
  [[ "$PACKAGE_ANDROID_BUILD_MODE" == "release" ]] ||
    fail "Android user-facing packages must use release mode"

  if [[ -z "$ANDROID_PLUGIN_REGISTRANT_BACKUP" ]]; then
    ANDROID_PLUGIN_REGISTRANT_BACKUP="$(mktemp)"
    if [[ -f "$ANDROID_PLUGIN_REGISTRANT" ]]; then
      ANDROID_PLUGIN_REGISTRANT_EXISTED=1
      cp "$ANDROID_PLUGIN_REGISTRANT" "$ANDROID_PLUGIN_REGISTRANT_BACKUP"
    else
      ANDROID_PLUGIN_REGISTRANT_EXISTED=0
      : > "$ANDROID_PLUGIN_REGISTRANT_BACKUP"
    fi
  fi

  ensure_flutter_pub_get
  write_android_release_plugin_registrant
}

write_android_release_plugin_registrant() {
  python3 - "$ROOT_DIR" "$ANDROID_PLUGIN_REGISTRANT" <<'PY'
import json
import pathlib
import re
import sys

root_dir = pathlib.Path(sys.argv[1])
registrant_path = pathlib.Path(sys.argv[2])
dependencies_path = root_dir / ".flutter-plugins-dependencies"

if not dependencies_path.exists():
    raise SystemExit(".flutter-plugins-dependencies is missing after flutter pub get")

dependencies = json.loads(dependencies_path.read_text(encoding="utf-8"))
plugins = dependencies.get("plugins", {}).get("android", [])


def android_block(pubspec_text):
    lines = pubspec_text.splitlines()
    for index, line in enumerate(lines):
        if re.match(r"^\s{6}android:\s*(?:#.*)?$", line):
            block = []
            for next_line in lines[index + 1 :]:
                if not next_line.startswith("        "):
                    break
                block.append(next_line[8:])
            return "\n".join(block)
    return ""


def pubspec_value(block, key):
    match = re.search(rf"^\s*{re.escape(key)}:\s*(.+?)\s*$", block, re.MULTILINE)
    if not match:
        return None
    value = match.group(1).split("#", 1)[0].strip().strip("\"'")
    return value or None


registrations = []
dev_plugin_names = []
for plugin in plugins:
    name = str(plugin.get("name") or "").strip()
    if not name:
        continue
    if plugin.get("dev_dependency"):
        dev_plugin_names.append(name)
        continue
    pubspec_path = pathlib.Path(str(plugin.get("path") or "")) / "pubspec.yaml"
    if not pubspec_path.exists():
        raise SystemExit(f"pubspec.yaml missing for Android plugin {name}: {pubspec_path}")
    block = android_block(pubspec_path.read_text(encoding="utf-8"))
    plugin_package = pubspec_value(block, "package")
    plugin_class = pubspec_value(block, "pluginClass")
    if plugin_package and plugin_class:
        registrations.append((name, plugin_package, plugin_class))

if not registrations:
    raise SystemExit("no Android method-channel plugin registrations were generated")

body_lines = []
for name, plugin_package, plugin_class in registrations:
    full_class = f"{plugin_package}.{plugin_class}"
    body_lines.extend(
        [
            "    try {",
            f"      flutterEngine.getPlugins().add(new {full_class}());",
            "    } catch (Exception e) {",
            f'      Log.e(TAG, "Error registering plugin {name}, {full_class}", e);',
            "    }",
        ]
    )

source = f'''package io.flutter.plugins;

import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import io.flutter.Log;

import io.flutter.embedding.engine.FlutterEngine;

/**
 * Generated file. Do not edit.
 * This file is generated by scripts/package_app.sh for release packaging.
 */
@Keep
public final class GeneratedPluginRegistrant {{
  private static final String TAG = "GeneratedPluginRegistrant";
  public static void registerWith(@NonNull FlutterEngine flutterEngine) {{
{chr(10).join(body_lines)}
  }}
}}
'''

for dev_name in dev_plugin_names:
    if dev_name in source:
        raise SystemExit(f"release GeneratedPluginRegistrant still references dev plugin {dev_name}")

registrant_path.parent.mkdir(parents=True, exist_ok=True)
registrant_path.write_text(source, encoding="utf-8")

print(
    "generated release Android plugin registrant with "
    f"{len(registrations)} production plugins; excluded "
    f"{len(dev_plugin_names)} dev plugins"
)
PY
}

verify_android_release_apk_contents() {
  local apk="$1"
  [[ "$PACKAGE_ANDROID_BUILD_MODE" == "release" ]] ||
    fail "Android user-facing packages must use release mode"

  python3 - "$apk" "$ROOT_DIR/.flutter-plugins-dependencies" <<'PY'
import json
import pathlib
import re
import sys
import zipfile

apk_path = pathlib.Path(sys.argv[1])
dependencies_path = pathlib.Path(sys.argv[2])

dev_plugin_names = []
dev_plugin_markers = []
if dependencies_path.exists():
    dependencies = json.loads(dependencies_path.read_text(encoding="utf-8"))
    for plugin in dependencies.get("plugins", {}).get("android", []):
        if plugin.get("dev_dependency"):
            name = str(plugin.get("name") or "").strip()
            if name:
                dev_plugin_names.append(name)
                dev_plugin_markers.append(name.encode("utf-8"))
                pubspec_path = pathlib.Path(str(plugin.get("path") or "")) / "pubspec.yaml"
                if pubspec_path.exists():
                    raw_pubspec = pubspec_path.read_text(encoding="utf-8", errors="ignore")
                    for key in ("pluginClass", "package"):
                        match = re.search(rf"^\s*{key}:\s*(.+?)\s*$", raw_pubspec, re.MULTILINE)
                        if match:
                            marker = match.group(1).split("#", 1)[0].strip().strip("\"'")
                            if marker:
                                dev_plugin_markers.append(marker.encode("utf-8"))

scan_bytes = bytearray()
with zipfile.ZipFile(apk_path) as archive:
    for info in archive.infolist():
        name = info.filename
        if name.endswith(".dex") or name.startswith("lib/") or name.startswith("META-INF/services/"):
            scan_bytes.extend(name.encode("utf-8", errors="ignore"))
            scan_bytes.extend(b"\0")
            scan_bytes.extend(archive.read(info))

if b"Lio/flutter/plugins/GeneratedPluginRegistrant;" not in scan_bytes:
    sys.stderr.write(
        "Android release APK is missing io.flutter.plugins.GeneratedPluginRegistrant; "
        "Flutter plugins will not register at startup.\n"
    )
    sys.exit(1)

leaked = sorted({
    name
    for name in dev_plugin_names
    if name.encode("utf-8") in scan_bytes
})
for marker in dev_plugin_markers:
    if marker in scan_bytes:
        leaked.append(marker.decode("utf-8", errors="replace"))
leaked = sorted(set(leaked))
if leaked:
    sys.stderr.write(
        "Android release APK contains dev-only plugins: "
        + ", ".join(leaked)
        + "\n"
    )
    sys.exit(1)
PY
}

verify_android_apk() {
  local apk="$1"
  local aapt_tool="$2"
  local apksigner_tool="$3"
  [[ -f "$apk" ]] || fail "Android APK not found: $apk"

  local badging package_name version_name version_code expected_version_code
  badging="$("$aapt_tool" dump badging "$apk")"
  package_name="$(printf '%s\n' "$badging" |
    sed -n "s/package: name='\([^']*\)'.*/\1/p" | head -1)"
  [[ "$package_name" == "$PACKAGE_ANDROID_APP_ID" ]] ||
    fail "Android APK package is $package_name, expected $PACKAGE_ANDROID_APP_ID"
  version_name="$(printf '%s\n' "$badging" |
    sed -n "s/.*versionName='\([^']*\)'.*/\1/p" | head -1)"
  [[ "$version_name" == "$VERSION_NAME" ]] ||
    fail "Android APK versionName is $version_name, expected $VERSION_NAME"
  version_code="$(printf '%s\n' "$badging" |
    sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" | head -1)"
  expected_version_code=$((BUILD_NUMBER + 2000))
  [[ "$version_code" == "$expected_version_code" ]] ||
    fail "Android arm64 split APK versionCode is $version_code, expected $expected_version_code"
  if printf '%s\n' "$badging" | grep -q '^application-debuggable'; then
    fail "Android package is debuggable; user-facing packages must be built in release mode"
  fi
  verify_android_release_apk_contents "$apk"

  local verify_output
  verify_output="$("$apksigner_tool" verify --print-certs "$apk" 2>&1)" ||
    fail "Android APK signature verification failed: $verify_output"

  if [[ -n "$PACKAGE_ANDROID_EXPECTED_CERT_SHA256" ]]; then
    local actual_cert
    actual_cert="$(printf '%s\n' "$verify_output" |
      sed -n 's/.*certificate SHA-256 digest:[[:space:]]*//p' | head -1)"
    [[ -n "$actual_cert" ]] || fail "cannot read Android APK signing certificate"

    local actual_norm expected_norm
    actual_norm="$(printf '%s' "$actual_cert" | normalize_sha256)"
    expected_norm="$(printf '%s' "$PACKAGE_ANDROID_EXPECTED_CERT_SHA256" | normalize_sha256)"
    [[ "$actual_norm" == "$expected_norm" ]] ||
      fail "Android signing certificate changed: $actual_cert"
  fi
}

android_smoke_test_device() {
  case "$PACKAGE_ANDROID_STARTUP_SMOKE_TEST" in
    never)
      return 0
      ;;
  esac
  if ! command -v adb >/dev/null 2>&1; then
    [[ "$PACKAGE_ANDROID_STARTUP_SMOKE_TEST" == "auto" ]] && return 0
    fail "adb is required for Android startup smoke test"
  fi

  local devices
  devices="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')"
  local emulator_devices
  emulator_devices="$(printf '%s\n' "$devices" | sed '/^$/d' | grep '^emulator-' || true)"
  local count
  count="$(printf '%s\n' "$emulator_devices" | sed '/^$/d' | wc -l | tr -d '[:space:]')"

  if [[ "$PACKAGE_ANDROID_STARTUP_SMOKE_TEST" == "auto" ]]; then
    if [[ "$count" -eq 1 ]]; then
      printf '%s\n' "$emulator_devices" | sed -n '1p'
    fi
    return 0
  fi

  [[ "$count" -eq 1 ]] ||
    fail "Android startup smoke test requires exactly one emulator device; found $count"
  printf '%s\n' "$emulator_devices" | sed -n '1p'
}

verify_android_startup_smoke() {
  local apk="$1"
  local device
  device="$(android_smoke_test_device)"
  if [[ -z "$device" ]]; then
    log "skipping Android startup smoke test"
    return 0
  fi

  log "running Android startup smoke test on $device"
  adb -s "$device" install -r "$apk" >/dev/null
  adb -s "$device" shell pm clear "$PACKAGE_ANDROID_APP_ID" >/dev/null
  adb -s "$device" logcat -c
  adb -s "$device" shell monkey \
    -p "$PACKAGE_ANDROID_APP_ID" \
    -c android.intent.category.LAUNCHER \
    1 >/dev/null
  sleep 6

  local pid crash_log
  pid="$(adb -s "$device" shell pidof "$PACKAGE_ANDROID_APP_ID" 2>/dev/null | tr -d '\r' || true)"
  crash_log="$(adb -s "$device" logcat -d -t 1200 | grep -Ei \
    'FATAL EXCEPTION|Fatal signal|SIGSEGV|UnsatisfiedLink|ClassNotFoundException|dlopen failed|native crash|tombstone|Force finishing activity' || true)"
  if [[ -z "$pid" || -n "$crash_log" ]]; then
    printf '%s\n' "$crash_log" >&2
    fail "Android startup smoke test failed"
  fi
  log "Android startup smoke test passed"
}

verify_macos_app() {
  local app="$1"
  local expected_arch="$2"
  [[ -d "$app" ]] || fail "macOS app bundle not found: $app"

  local bundle_id
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$app/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$bundle_id" == "$PACKAGE_MACOS_BUNDLE_ID" ]] ||
    fail "macOS app bundle id is $bundle_id, expected $PACKAGE_MACOS_BUNDLE_ID"

  local executable="$app/Contents/MacOS/$PACKAGE_APP_DISPLAY_NAME"
  [[ -f "$executable" ]] || fail "macOS executable not found: $executable"
  local actual_archs
  actual_archs="$(lipo -archs "$executable")"
  [[ "$actual_archs" == "$expected_arch" ]] ||
    fail "macOS executable archs are $actual_archs, expected exactly $expected_arch"
}

prepare_macos_project() {
  if [[ ! -d macos/Runner.xcworkspace ]]; then
    fail "macos/Runner.xcworkspace is missing; run scripts/prepare_macos_build.sh first"
  fi
}

ensure_flutter_pub_get() {
  if [[ "$FLUTTER_PUB_GET_DONE" -eq 0 ]]; then
    "$PACKAGE_FLUTTER_BIN" pub get
    FLUTTER_PUB_GET_DONE=1
  fi
}

build_sdk_native() {
  [[ -x "$SDK_NATIVE_BUILD_SCRIPT" ]] ||
    fail "SDK native build script not found or not executable: $SDK_NATIVE_BUILD_SCRIPT"

  if needs_macos; then
    log "building awiki_im_core macOS native SDK artifact"
    "$SDK_NATIVE_BUILD_SCRIPT" --macos-only
  fi

  if needs_android; then
    log "building awiki_im_core Android native SDK artifact"
    "$SDK_NATIVE_BUILD_SCRIPT" --android-only --skip-codegen-check
  fi
}

create_dmg() {
  local app="$1"
  local arch_label="$2"
  local output="$3"
  local stage_dir="$ROOT_DIR/build/package/stage-macos-$PACKAGE_MACOS_BUILD_MODE-$arch_label"
  local volume_name="$PACKAGE_APP_DISPLAY_NAME $VERSION_NAME $arch_label"

  rm -rf "$stage_dir" "$output"
  mkdir -p "$stage_dir"
  cp -R "$app" "$stage_dir/$PACKAGE_APP_DISPLAY_NAME.app"
  ln -s /Applications "$stage_dir/Applications"
  hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$stage_dir" \
    -ov \
    -format UDZO \
    "$output" >/dev/null
}

build_android_arm64() {
  local output_apk="$1"
  local aapt_tool="$2"
  local apksigner_tool="$3"

  log "building Android arm64 $PACKAGE_ANDROID_BUILD_MODE APK"
  prepare_android_release_sources
  sync_android_local_version
  rm -f "build/app/outputs/flutter-apk/app-arm64-v8a-$PACKAGE_ANDROID_BUILD_MODE.apk"
  "$PACKAGE_FLUTTER_BIN" build apk \
    "--$PACKAGE_ANDROID_BUILD_MODE" \
    --no-pub \
    --target-platform android-arm64 \
    --split-per-abi \
    --dart-define="AWIKI_PRIMARY_TENANT_DOMAIN=$PACKAGE_PRIMARY_TENANT_DOMAIN" \
    --build-name "$VERSION_NAME" \
    --build-number "$BUILD_NUMBER"

  local built_apk="build/app/outputs/flutter-apk/app-arm64-v8a-$PACKAGE_ANDROID_BUILD_MODE.apk"
  [[ -f "$built_apk" ]] ||
    fail "expected Android arm64 APK not found: $built_apk"
  verify_android_apk "$built_apk" "$aapt_tool" "$apksigner_tool"
  verify_android_startup_smoke "$built_apk"
  cp "$built_apk" "$output_apk"
}

build_macos_arch() {
  local arch="$1"
  local arch_label="$2"
  local output_dmg="$3"
  local derived_data="$ROOT_DIR/build/package/derived-macos-$PACKAGE_MACOS_BUILD_MODE-$arch_label"
  local app="$derived_data/Build/Products/$XCODE_CONFIGURATION/$PACKAGE_APP_DISPLAY_NAME.app"

  log "building macOS $arch_label $PACKAGE_MACOS_BUILD_MODE app"
  rm -rf "$derived_data"
  ensure_flutter_pub_get
  "$PACKAGE_FLUTTER_BIN" build macos \
    "--$PACKAGE_MACOS_BUILD_MODE" \
    --no-pub \
    --config-only \
    --dart-define="AWIKI_PRIMARY_TENANT_DOMAIN=$PACKAGE_PRIMARY_TENANT_DOMAIN" \
    --build-name "$VERSION_NAME" \
    --build-number "$BUILD_NUMBER"
  xcodebuild \
    -workspace macos/Runner.xcworkspace \
    -scheme Runner \
    -configuration "$XCODE_CONFIGURATION" \
    -derivedDataPath "$derived_data" \
    -destination 'platform=macOS' \
    ARCHS="$arch" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$AWIKI_MACOS_SIGNING_FINGERPRINT" \
    DEVELOPMENT_TEAM="$AWIKI_MACOS_DEVELOPMENT_TEAM" \
    FLUTTER_BUILD_NAME="$VERSION_NAME" \
    FLUTTER_BUILD_NUMBER="$BUILD_NUMBER" \
    build

  verify_macos_app "$app" "$arch"
  awiki_verify_macos_app_signature \
    "$app" \
    "$AWIKI_MACOS_DEVELOPMENT_TEAM" \
    "$PACKAGE_MACOS_BUNDLE_ID" || fail "macOS trial-release signature verification failed"
  create_dmg "$app" "$arch_label" "$output_dmg"
}

write_platform_entry() {
  local key="$1"
  local file="$2"
  local prefix_comma="$3"
  local name
  name="$(basename "$file")"
  if [[ "$prefix_comma" == "1" ]]; then
    printf ',\n'
  fi
  cat <<JSON
    $(json_string "$key"): {
      "file": $(json_string "$name"),
      "sha256": $(json_string "$(file_sha256 "$file")"),
      "sizeBytes": $(file_size "$file")
    }
JSON
}

write_latest_platform_entry() {
  local key="$1"
  local file="$2"
  local prefix_comma="$3"
  local name
  name="$(basename "$file")"
  if [[ "$prefix_comma" == "1" ]]; then
    printf ',\n'
  fi
  cat <<JSON
    $(json_string "$key"): {
      "downloadUrl": $(json_string "$(download_url_for "$name")"),
      "sha256": $(json_string "$(file_sha256 "$file")")
    }
JSON
}

download_url_for() {
  local file_name="$1"
  printf '%s/%s/%s\n' "$(download_base_url)" "$VERSION_NAME" "$file_name"
}

write_latest_manifest() {
  local output_dir="$1"
  local android_file="$2"
  local macos_arm64_file="$3"
  local macos_x64_file="$4"
  local manifest="$LATEST_MANIFEST"
  local wrote=0
  local macos_default_file=""
  if [[ -n "$macos_arm64_file" ]]; then
    macos_default_file="$macos_arm64_file"
  elif [[ -n "$macos_x64_file" ]]; then
    macos_default_file="$macos_x64_file"
  fi

  {
    cat <<JSON
{
  "version": $(json_string "$VERSION_NAME"),
  "buildNumber": $BUILD_NUMBER,
  "publishedAt": $(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)"),
  "releaseNotesUrl": $(json_string "$PACKAGE_DOWNLOAD_PAGE_URL"),
  "githubReleaseUrl": $(json_string "$PACKAGE_DOWNLOAD_PAGE_URL"),
  "platforms": {
JSON
    if [[ -n "$android_file" ]]; then
      write_latest_platform_entry "android" "$android_file" "$wrote"
      wrote=1
    fi
    if [[ -n "$macos_default_file" ]]; then
      write_latest_platform_entry "macos" "$macos_default_file" "$wrote"
      wrote=1
    fi
    if [[ -n "$macos_arm64_file" ]]; then
      write_latest_platform_entry "macos-arm64" "$macos_arm64_file" "$wrote"
      wrote=1
    fi
    if [[ -n "$macos_x64_file" ]]; then
      write_latest_platform_entry "macos-x64" "$macos_x64_file" "$wrote"
      wrote=1
    fi
    cat <<'JSON'

  }
}
JSON
  } > "$manifest"
}

write_manifest() {
  local output_dir="$1"
  local android_file="$2"
  local macos_arm64_file="$3"
  local macos_x64_file="$4"
  local manifest="$output_dir/package-manifest.json"

  {
    cat <<JSON
{
  "version": $(json_string "$VERSION_NAME"),
  "buildNumber": $BUILD_NUMBER,
  "buildModes": {
    "android": $(json_string "$PACKAGE_ANDROID_BUILD_MODE"),
    "macos": $(json_string "$PACKAGE_MACOS_BUILD_MODE")
  },
  "publishedAt": $(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)"),
  "release": {
    "downloadBaseUrl": $(json_string "$PACKAGE_RELEASE_BASE_URL")
  },
  "platforms": {
JSON
    local wrote=0
    if [[ -n "$android_file" ]]; then
      write_platform_entry "android-arm64" "$android_file" "$wrote"
      wrote=1
    fi
    if [[ -n "$macos_arm64_file" ]]; then
      write_platform_entry "macos-arm64" "$macos_arm64_file" "$wrote"
      wrote=1
    fi
    if [[ -n "$macos_x64_file" ]]; then
      write_platform_entry "macos-x64" "$macos_x64_file" "$wrote"
      wrote=1
    fi
    cat <<'JSON'

  }
}
JSON
  } > "$manifest"
  write_latest_manifest \
    "$output_dir" \
    "$android_file" \
    "$macos_arm64_file" \
    "$macos_x64_file"
}

require_cmd awk
require_cmd grep
require_cmd sed
require_cmd "$PACKAGE_FLUTTER_BIN"
require_cmd shasum
if needs_macos; then
  require_cmd codesign
  require_cmd hdiutil
  require_cmd lipo
  require_cmd security
  require_cmd xcodebuild
  require_cmd /usr/libexec/PlistBuddy
  require_non_empty_config_var AWIKI_MACOS_SIGNING_IDENTITY
  require_non_empty_config_var AWIKI_MACOS_DEVELOPMENT_TEAM
  [[ "$AWIKI_MACOS_DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]] ||
    fail "AWIKI_MACOS_DEVELOPMENT_TEAM must be a 10-character Team ID"
  AWIKI_MACOS_SIGNING_FINGERPRINT="$(
    awiki_resolve_codesigning_identity "$AWIKI_MACOS_SIGNING_IDENTITY"
  )" || fail "macOS trial-release signing identity is unavailable"
fi

CURRENT_VERSION="$(read_pubspec_version)"
NEXT_VERSION="$(compute_next_version "$CURRENT_VERSION")"
VERSION_NAME="$(version_name "$NEXT_VERSION")"
BUILD_NUMBER="$(build_number "$NEXT_VERSION")"
LAST_BUILD="$(read_latest_build_number || true)"

if [[ -n "$LAST_BUILD" && "$BUILD_NUMBER" -le "$LAST_BUILD" ]]; then
  fail "new buildNumber $BUILD_NUMBER must be greater than latest manifest buildNumber $LAST_BUILD"
fi

check_source_identity

log "config:          $CONFIG_PATH"
if [[ -f "$LOCAL_CONFIG_PATH" ]]; then
  log "local config:    $LOCAL_CONFIG_PATH"
fi
log "android mode:    $PACKAGE_ANDROID_BUILD_MODE"
log "macOS mode:      $PACKAGE_MACOS_BUILD_MODE"
log "release domain:  $PACKAGE_RELEASE_DOMAIN"
log "tenant domain:   $PACKAGE_PRIMARY_TENANT_DOMAIN"
log "download base:   $PACKAGE_RELEASE_BASE_URL"
log "manifest URL:    $PACKAGE_UPDATE_MANIFEST_PUBLIC_URL"
log "download page:   $PACKAGE_DOWNLOAD_PAGE_URL"
log "current version: $CURRENT_VERSION"
log "next version:    $NEXT_VERSION"
log "dist root:       $DIST_ROOT"
log "SDK repo:        $SDK_REPO_DIR"
if needs_macos; then
  log "macOS signer:    $AWIKI_MACOS_SIGNING_IDENTITY"
  log "macOS Team ID:   $AWIKI_MACOS_DEVELOPMENT_TEAM"
fi
log "targets:"
for target in ${PACKAGE_TARGET_LIST[@]+"${PACKAGE_TARGET_LIST[@]}"}; do
  log "  - $(target_description "$target")"
done

if [[ "$NEXT_VERSION" != "$CURRENT_VERSION" ]]; then
  PUBSPEC_BACKUP="$(mktemp)"
  cp "$PUBSPEC_PATH" "$PUBSPEC_BACKUP"
  write_pubspec_version "$NEXT_VERSION"
  PUBSPEC_WAS_UPDATED=1
  log "updated pubspec.yaml version to $NEXT_VERSION"
fi

mkdir -p "$DIST_ROOT"

AAPT_TOOL=""
APKSIGNER_TOOL=""
if needs_android; then
  AAPT_TOOL="$(find_android_tool aapt)"
  APKSIGNER_TOOL="$(find_android_tool apksigner)"
fi

if needs_macos; then
  prepare_macos_project
fi

build_sdk_native

OUTPUT_DIR="$DIST_ROOT/$VERSION_NAME"
mkdir -p "$OUTPUT_DIR"

ANDROID_APK=""
MACOS_ARM64_DMG=""
MACOS_X64_DMG=""

if needs_android; then
  ANDROID_APK="$OUTPUT_DIR/AWiki-Me-Android-arm64-$VERSION_NAME.apk"
  build_android_arm64 "$ANDROID_APK" "$AAPT_TOOL" "$APKSIGNER_TOOL"
fi

if target_enabled "macos-arm64"; then
  MACOS_ARM64_DMG="$OUTPUT_DIR/AWiki-Me-macOS-arm64-$VERSION_NAME.dmg"
  build_macos_arch "arm64" "arm64" "$MACOS_ARM64_DMG"
fi

if target_enabled "macos-x64"; then
  MACOS_X64_DMG="$OUTPUT_DIR/AWiki-Me-macOS-x64-$VERSION_NAME.dmg"
  build_macos_arch "x86_64" "x64" "$MACOS_X64_DMG"
fi

write_manifest "$OUTPUT_DIR" "$ANDROID_APK" "$MACOS_ARM64_DMG" "$MACOS_X64_DMG"

log "done"
log "output: $OUTPUT_DIR"
log "package manifest: $OUTPUT_DIR/package-manifest.json"
log "latest: $LATEST_MANIFEST"
