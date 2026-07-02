#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$SCRIPT_DIR/package_app.config"
cd "$ROOT_DIR"

PACKAGE_APP_DISPLAY_NAME="AWiki Me"
PACKAGE_ANDROID_APP_ID="ai.awiki.awikime"
PACKAGE_MACOS_BUNDLE_ID="ai.awiki.awikiMe"
PACKAGE_FLUTTER_BIN="flutter"
PACKAGE_SDK_REPO_DIR="../awiki-cli-rs2"
PACKAGE_ANDROID_EXPECTED_CERT_SHA256="F2:67:E9:18:57:54:ED:C1:2B:E5:69:69:1B:39:B9:EF:D4:EF:1E:CF:2D:7E:D8:18:81:42:69:B3:70:85:D8:75"
PACKAGE_ANDROID_BUILD_MODE="debug"
PACKAGE_MACOS_BUILD_MODE="profile"
XCODE_CONFIGURATION="Profile"
DIST_ROOT="$ROOT_DIR/dist"

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
  if [[ -n "$PUBSPEC_BACKUP" && -f "$PUBSPEC_BACKUP" ]]; then
    rm -f "$PUBSPEC_BACKUP"
  fi
}

trap 'on_exit $?' EXIT

if [[ "$#" -ne 0 ]]; then
  fail "package settings must be edited in scripts/package_app.config; this script accepts no arguments"
fi

[[ -f "$CONFIG_PATH" ]] || fail "missing config file: $CONFIG_PATH"
# shellcheck source=scripts/package_app.config
source "$CONFIG_PATH"

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

for required_name in \
  PACKAGE_CHANNEL \
  AWIKI_BASE_URL \
  AWIKI_UPDATE_MANIFEST_URL \
  AWIKI_RELEASES_URL \
  PACKAGE_VERSION_BUMP; do
  require_config_var "$required_name"
done

require_non_empty_config_var PACKAGE_CHANNEL
require_non_empty_config_var AWIKI_BASE_URL
require_non_empty_config_var AWIKI_UPDATE_MANIFEST_URL
require_non_empty_config_var AWIKI_RELEASES_URL
require_non_empty_config_var PACKAGE_VERSION_BUMP

for value_name in \
  PACKAGE_CHANNEL \
  AWIKI_BASE_URL \
  AWIKI_UPDATE_MANIFEST_URL \
  AWIKI_RELEASES_URL \
  PACKAGE_VERSION_BUMP; do
  validate_no_newline "$value_name" "${!value_name}"
done

case "$PACKAGE_CHANNEL" in
  *[!A-Za-z0-9._-]*)
    fail "PACKAGE_CHANNEL may only contain letters, numbers, dot, underscore, and hyphen"
    ;;
esac

case "$PACKAGE_VERSION_BUMP" in
  build|patch|minor|major|none)
    ;;
  *)
    fail "PACKAGE_VERSION_BUMP must be one of: build, patch, minor, major, none"
    ;;
esac

CHANNEL_DIST_ROOT="$DIST_ROOT/$PACKAGE_CHANNEL"
LATEST_MANIFEST="$CHANNEL_DIST_ROOT/latest.json"
SDK_REPO_DIR="$(resolve_repo_path "$PACKAGE_SDK_REPO_DIR")"
SDK_NATIVE_BUILD_SCRIPT="$SDK_REPO_DIR/scripts/flutter/build-sdk-native.sh"

DART_DEFINE_ARGS=()
DART_DEFINE_KEYS=()
DART_DEFINE_VALUES=()

add_dart_define() {
  local key="$1"
  local value="$2"
  [[ -n "$value" ]] || return 0
  DART_DEFINE_ARGS+=("--dart-define=$key=$value")
  DART_DEFINE_KEYS+=("$key")
  DART_DEFINE_VALUES+=("$value")
}

add_dart_define "AWIKI_BASE_URL" "$AWIKI_BASE_URL"
add_dart_define "AWIKI_UPDATE_MANIFEST_URL" "$AWIKI_UPDATE_MANIFEST_URL"
add_dart_define "AWIKI_RELEASES_URL" "$AWIKI_RELEASES_URL"

encode_dart_defines() {
  local joined=""
  local i part define
  for i in "${!DART_DEFINE_KEYS[@]}"; do
    define="${DART_DEFINE_KEYS[$i]}=${DART_DEFINE_VALUES[$i]}"
    part="$(printf '%s' "$define" | base64 | tr -d '\n')"
    if [[ -n "$joined" ]]; then
      joined="$joined,$part"
    else
      joined="$part"
    fi
  done
  printf '%s\n' "$joined"
}

DART_DEFINES_ENCODED="$(encode_dart_defines)"

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

check_source_identity() {
  grep -Fq "namespace = \"$PACKAGE_ANDROID_APP_ID\"" \
    android/app/build.gradle ||
    fail "android namespace must stay $PACKAGE_ANDROID_APP_ID"
  grep -Fq "applicationId = \"$PACKAGE_ANDROID_APP_ID\"" \
    android/app/build.gradle ||
    fail "android applicationId must stay $PACKAGE_ANDROID_APP_ID"
  grep -Fq "PRODUCT_BUNDLE_IDENTIFIER = $PACKAGE_MACOS_BUNDLE_ID" \
    macos/Runner/Configs/AppInfo.xcconfig ||
    fail "macOS PRODUCT_BUNDLE_IDENTIFIER must stay $PACKAGE_MACOS_BUNDLE_ID"
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
    fail "macos/Runner.xcworkspace is missing; run scripts/bootstrap_macos.sh first"
  fi
}

build_sdk_native() {
  [[ -x "$SDK_NATIVE_BUILD_SCRIPT" ]] ||
    fail "SDK native build script not found or not executable: $SDK_NATIVE_BUILD_SCRIPT"

  log "building awiki_im_core macOS native SDK artifact"
  "$SDK_NATIVE_BUILD_SCRIPT" --macos-only

  log "building awiki_im_core Android native SDK artifact"
  "$SDK_NATIVE_BUILD_SCRIPT" --android-only --skip-codegen-check
}

create_dmg() {
  local app="$1"
  local arch_label="$2"
  local output="$3"
  local stage_dir="$ROOT_DIR/build/package/stage-macos-$PACKAGE_CHANNEL-$PACKAGE_MACOS_BUILD_MODE-$arch_label"
  local volume_name="$PACKAGE_APP_DISPLAY_NAME $VERSION_NAME $PACKAGE_CHANNEL $arch_label"

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
  "$PACKAGE_FLUTTER_BIN" build apk \
    "--$PACKAGE_ANDROID_BUILD_MODE" \
    "${DART_DEFINE_ARGS[@]}" \
    --target-platform android-arm64 \
    --split-per-abi \
    --build-name "$VERSION_NAME" \
    --build-number "$BUILD_NUMBER"

  local built_apk="build/app/outputs/flutter-apk/app-arm64-v8a-$PACKAGE_ANDROID_BUILD_MODE.apk"
  [[ -f "$built_apk" ]] ||
    fail "expected Android arm64 APK not found: $built_apk"
  verify_android_apk "$built_apk" "$aapt_tool" "$apksigner_tool"
  cp "$built_apk" "$output_apk"
}

build_macos_arch() {
  local arch="$1"
  local arch_label="$2"
  local output_dmg="$3"
  local derived_data="$ROOT_DIR/build/package/derived-macos-$PACKAGE_CHANNEL-$PACKAGE_MACOS_BUILD_MODE-$arch_label"
  local app="$derived_data/Build/Products/$XCODE_CONFIGURATION/$PACKAGE_APP_DISPLAY_NAME.app"

  log "building macOS $arch_label $PACKAGE_MACOS_BUILD_MODE app"
  rm -rf "$derived_data"
  "$PACKAGE_FLUTTER_BIN" build macos \
    "--$PACKAGE_MACOS_BUILD_MODE" \
    "${DART_DEFINE_ARGS[@]}" \
    --config-only \
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
    FLUTTER_BUILD_NAME="$VERSION_NAME" \
    FLUTTER_BUILD_NUMBER="$BUILD_NUMBER" \
    DART_DEFINES="$DART_DEFINES_ENCODED" \
    build

  verify_macos_app "$app" "$arch"
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

download_url_for() {
  local file_name="$1"
  printf 'https://awiki.ai/downloads/awiki-me/%s/%s/%s\n' \
    "$PACKAGE_CHANNEL" "$VERSION_NAME" "$file_name"
}

write_app_update_manifest() {
  local output_dir="$1"
  local android_file="$2"
  local macos_arm64_file="$3"
  local macos_x64_file="$4"
  local manifest="$output_dir/latest.json"
  local android_name macos_arm64_name macos_x64_name

  android_name="$(basename "$android_file")"
  macos_arm64_name="$(basename "$macos_arm64_file")"
  macos_x64_name="$(basename "$macos_x64_file")"

  cat > "$manifest" <<JSON
{
  "version": $(json_string "$VERSION_NAME"),
  "buildNumber": $BUILD_NUMBER,
  "publishedAt": $(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)"),
  "releaseNotesUrl": $(json_string "$AWIKI_RELEASES_URL"),
  "githubReleaseUrl": $(json_string "$AWIKI_RELEASES_URL"),
  "platforms": {
    "android": {
      "downloadUrl": $(json_string "$(download_url_for "$android_name")"),
      "sha256": $(json_string "$(file_sha256 "$output_dir/$android_name")")
    },
    "macos": {
      "downloadUrl": $(json_string "$(download_url_for "$macos_arm64_name")"),
      "sha256": $(json_string "$(file_sha256 "$output_dir/$macos_arm64_name")")
    },
    "macos-arm64": {
      "downloadUrl": $(json_string "$(download_url_for "$macos_arm64_name")"),
      "sha256": $(json_string "$(file_sha256 "$output_dir/$macos_arm64_name")")
    },
    "macos-x64": {
      "downloadUrl": $(json_string "$(download_url_for "$macos_x64_name")"),
      "sha256": $(json_string "$(file_sha256 "$output_dir/$macos_x64_name")")
    }
  }
}
JSON
  cp "$manifest" "$LATEST_MANIFEST"
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
  "channel": $(json_string "$PACKAGE_CHANNEL"),
  "buildModes": {
    "android": $(json_string "$PACKAGE_ANDROID_BUILD_MODE"),
    "macos": $(json_string "$PACKAGE_MACOS_BUILD_MODE")
  },
  "publishedAt": $(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)"),
  "backend": {
    "baseUrl": $(json_string "$AWIKI_BASE_URL")
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
  write_app_update_manifest \
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
require_cmd base64
require_cmd hdiutil
require_cmd lipo
require_cmd xcodebuild
require_cmd /usr/libexec/PlistBuddy

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
log "channel:         $PACKAGE_CHANNEL"
log "android mode:    $PACKAGE_ANDROID_BUILD_MODE"
log "macOS mode:      $PACKAGE_MACOS_BUILD_MODE"
log "backend base:    $AWIKI_BASE_URL"
log "update manifest: $AWIKI_UPDATE_MANIFEST_URL"
log "download page:   $AWIKI_RELEASES_URL"
log "current version: $CURRENT_VERSION"
log "next version:    $NEXT_VERSION"
log "dist root:       $DIST_ROOT"
log "SDK repo:        $SDK_REPO_DIR"
log "targets:"
log "  - android-arm64 $PACKAGE_ANDROID_BUILD_MODE APK"
log "  - macos-arm64 $PACKAGE_MACOS_BUILD_MODE DMG"
log "  - macos-x64 $PACKAGE_MACOS_BUILD_MODE DMG"

if [[ "$NEXT_VERSION" != "$CURRENT_VERSION" ]]; then
  PUBSPEC_BACKUP="$(mktemp)"
  cp "$PUBSPEC_PATH" "$PUBSPEC_BACKUP"
  write_pubspec_version "$NEXT_VERSION"
  PUBSPEC_WAS_UPDATED=1
  log "updated pubspec.yaml version to $NEXT_VERSION"
fi

mkdir -p "$CHANNEL_DIST_ROOT"

AAPT_TOOL=""
APKSIGNER_TOOL=""
AAPT_TOOL="$(find_android_tool aapt)"
APKSIGNER_TOOL="$(find_android_tool apksigner)"

prepare_macos_project

build_sdk_native

OUTPUT_DIR="$CHANNEL_DIST_ROOT/$VERSION_NAME"
mkdir -p "$OUTPUT_DIR"

ANDROID_APK=""
MACOS_ARM64_DMG=""
MACOS_X64_DMG=""

ANDROID_APK="$OUTPUT_DIR/AWiki-Me-Android-arm64-$VERSION_NAME.apk"
build_android_arm64 "$ANDROID_APK" "$AAPT_TOOL" "$APKSIGNER_TOOL"

MACOS_ARM64_DMG="$OUTPUT_DIR/AWiki-Me-macOS-arm64-$VERSION_NAME.dmg"
build_macos_arch "arm64" "arm64" "$MACOS_ARM64_DMG"

MACOS_X64_DMG="$OUTPUT_DIR/AWiki-Me-macOS-x64-$VERSION_NAME.dmg"
build_macos_arch "x86_64" "x64" "$MACOS_X64_DMG"

write_manifest "$OUTPUT_DIR" "$ANDROID_APK" "$MACOS_ARM64_DMG" "$MACOS_X64_DMG"

log "done"
log "output: $OUTPUT_DIR"
log "manifest: $OUTPUT_DIR/latest.json"
log "package manifest: $OUTPUT_DIR/package-manifest.json"
log "latest: $LATEST_MANIFEST"
