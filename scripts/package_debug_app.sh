#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_DISPLAY_NAME="AWiki Me"
ANDROID_APP_ID="ai.awiki.awikime"
MACOS_BUNDLE_ID="ai.awiki.awikiMe"
EXPECTED_ANDROID_DEBUG_CERT_SHA256="F2:67:E9:18:57:54:ED:C1:2B:E5:69:69:1B:39:B9:EF:D4:EF:1E:CF:2D:7E:D8:18:81:42:69:B3:70:85:D8:75"

SDK_REPO_DIR="$(cd "$ROOT_DIR/../awiki-cli-rs2" && pwd)"
SDK_NATIVE_BUILD_SCRIPT="$SDK_REPO_DIR/scripts/flutter/build-sdk-native.sh"
DIST_ROOT="${DIST_ROOT:-$ROOT_DIR/dist/app}"
PUBSPEC_PATH="$ROOT_DIR/pubspec.yaml"
LATEST_MANIFEST="$DIST_ROOT/latest.json"

BUMP_MODE="build"
EXPLICIT_VERSION=""
DRY_RUN=0
PUBSPEC_BACKUP=""
PUBSPEC_WAS_UPDATED=0

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

usage() {
  cat <<'USAGE'
Usage:
  scripts/package_debug_app.sh [options]

Builds the fixed AWiki Me debug installer set:
  - Android arm64 debug APK
  - macOS arm64 debug DMG
  - macOS x64 debug DMG

Options:
  --bump build|patch|minor|major
      Version bump mode. Default is "build": keep x.y.z and increment +build.
  --version x.y.z
      Set display version explicitly and increment +build.
  --no-version-bump
      Keep the current pubspec.yaml version exactly. Useful for rebuilding
      the same version locally; it still must be newer than dist/app/latest.json.
  --dry-run
      Print the planned version and run source-level checks without modifying
      files or building installers.
  -h, --help
      Show this help.

Environment:
  DIST_ROOT
      Output root. Defaults to ./dist/app.
USAGE
}

log() {
  printf '[package-debug-app] %s\n' "$*"
}

fail() {
  printf '[package-debug-app] error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump)
      [[ $# -ge 2 ]] || fail "--bump requires a value"
      BUMP_MODE="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || fail "--version requires a value"
      EXPLICIT_VERSION="$2"
      shift 2
      ;;
    --no-version-bump)
      BUMP_MODE="none"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

case "$BUMP_MODE" in
  build|patch|minor|major|none) ;;
  *) fail "--bump must be one of: build, patch, minor, major" ;;
esac

if [[ -n "$EXPLICIT_VERSION" && "$BUMP_MODE" != "build" ]]; then
  fail "--version cannot be combined with --bump or --no-version-bump"
fi

if [[ -n "$EXPLICIT_VERSION" && ! "$EXPLICIT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "--version must use x.y.z format"
fi

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

  if [[ "$BUMP_MODE" != "none" || -n "$EXPLICIT_VERSION" ]]; then
    next_build=$((build + 1))
  fi

  if [[ -n "$EXPLICIT_VERSION" ]]; then
    printf '%s+%s\n' "$EXPLICIT_VERSION" "$next_build"
    return
  fi

  case "$BUMP_MODE" in
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
  grep -Eq 'namespace[[:space:]]*=[[:space:]]*"ai\.awiki\.awikime"' \
    android/app/build.gradle ||
    fail "android namespace must stay $ANDROID_APP_ID"
  grep -Eq 'applicationId[[:space:]]*=[[:space:]]*"ai\.awiki\.awikime"' \
    android/app/build.gradle ||
    fail "android applicationId must stay $ANDROID_APP_ID"
  grep -Eq '^PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=[[:space:]]*ai\.awiki\.awikiMe[[:space:]]*$' \
    macos/Runner/Configs/AppInfo.xcconfig ||
    fail "macOS PRODUCT_BUNDLE_IDENTIFIER must stay $MACOS_BUNDLE_ID"
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
  [[ "$package_name" == "$ANDROID_APP_ID" ]] ||
    fail "Android APK package is $package_name, expected $ANDROID_APP_ID"
  version_name="$(printf '%s\n' "$badging" |
    sed -n "s/.*versionName='\([^']*\)'.*/\1/p" | head -1)"
  [[ "$version_name" == "$VERSION_NAME" ]] ||
    fail "Android APK versionName is $version_name, expected $VERSION_NAME"
  version_code="$(printf '%s\n' "$badging" |
    sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" | head -1)"
  expected_version_code=$((BUILD_NUMBER + 2000))
  [[ "$version_code" == "$expected_version_code" ]] ||
    fail "Android arm64 split APK versionCode is $version_code, expected $expected_version_code"

  local actual_cert
  actual_cert="$("$apksigner_tool" verify --print-certs "$apk" |
    sed -n 's/.*certificate SHA-256 digest:[[:space:]]*//p' | head -1)"
  [[ -n "$actual_cert" ]] || fail "cannot read Android APK signing certificate"

  local actual_norm expected_norm
  actual_norm="$(printf '%s' "$actual_cert" | normalize_sha256)"
  expected_norm="$(printf '%s' "$EXPECTED_ANDROID_DEBUG_CERT_SHA256" | normalize_sha256)"
  [[ "$actual_norm" == "$expected_norm" ]] ||
    fail "Android debug signing certificate changed: $actual_cert"
}

verify_macos_app() {
  local app="$1"
  local expected_arch="$2"
  [[ -d "$app" ]] || fail "macOS app bundle not found: $app"

  local bundle_id
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$app/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$bundle_id" == "$MACOS_BUNDLE_ID" ]] ||
    fail "macOS app bundle id is $bundle_id, expected $MACOS_BUNDLE_ID"

  local executable="$app/Contents/MacOS/$APP_DISPLAY_NAME"
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
  local stage_dir="$ROOT_DIR/build/package/stage-macos-$arch_label"
  local volume_name="AWiki Me $VERSION_NAME $arch_label"

  rm -rf "$stage_dir" "$output"
  mkdir -p "$stage_dir"
  cp -R "$app" "$stage_dir/$APP_DISPLAY_NAME.app"
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

  log "building Android arm64 debug APK"
  flutter build apk \
    --debug \
    --target-platform android-arm64 \
    --split-per-abi \
    --build-name "$VERSION_NAME" \
    --build-number "$BUILD_NUMBER"

  local built_apk="build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk"
  [[ -f "$built_apk" ]] ||
    fail "expected Android arm64 APK not found: $built_apk"
  verify_android_apk "$built_apk" "$aapt_tool" "$apksigner_tool"
  cp "$built_apk" "$output_apk"
}

build_macos_arch() {
  local arch="$1"
  local arch_label="$2"
  local output_dmg="$3"
  local derived_data="$ROOT_DIR/build/package/derived-macos-$arch_label"
  local app="$derived_data/Build/Products/Debug/$APP_DISPLAY_NAME.app"

  log "building macOS $arch_label debug app"
  rm -rf "$derived_data"
  flutter build macos \
    --debug \
    --config-only \
    --build-name "$VERSION_NAME" \
    --build-number "$BUILD_NUMBER"
  xcodebuild \
    -workspace macos/Runner.xcworkspace \
    -scheme Runner \
    -configuration Debug \
    -derivedDataPath "$derived_data" \
    -destination 'platform=macOS' \
    ARCHS="$arch" \
    ONLY_ACTIVE_ARCH=NO \
    FLUTTER_BUILD_NAME="$VERSION_NAME" \
    FLUTTER_BUILD_NUMBER="$BUILD_NUMBER" \
    build

  verify_macos_app "$app" "$arch"
  create_dmg "$app" "$arch_label" "$output_dmg"
}

write_manifest() {
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
  "version": "$VERSION_NAME",
  "buildNumber": $BUILD_NUMBER,
  "publishedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "platforms": {
    "android-arm64": {
      "file": "$android_name",
      "sha256": "$(file_sha256 "$android_file")",
      "sizeBytes": $(file_size "$android_file")
    },
    "macos-arm64": {
      "file": "$macos_arm64_name",
      "sha256": "$(file_sha256 "$macos_arm64_file")",
      "sizeBytes": $(file_size "$macos_arm64_file")
    },
    "macos-x64": {
      "file": "$macos_x64_name",
      "sha256": "$(file_sha256 "$macos_x64_file")",
      "sizeBytes": $(file_size "$macos_x64_file")
    }
  }
}
JSON
  cp "$manifest" "$LATEST_MANIFEST"
}

require_cmd awk
require_cmd grep
require_cmd sed
require_cmd flutter
require_cmd shasum
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

log "current version: $CURRENT_VERSION"
log "next version:    $NEXT_VERSION"
log "dist root:       $DIST_ROOT"
log "SDK repo:        $SDK_REPO_DIR"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry run build plan:"
  log "  1. build awiki_im_core native SDK artifact for macOS"
  log "  2. build awiki_im_core native SDK artifact for Android"
  log "  3. build Android arm64 debug APK"
  log "  4. build macOS arm64 debug DMG"
  log "  5. build macOS x64 debug DMG"
  log "dry run complete; no files changed"
  exit 0
fi

if [[ "$NEXT_VERSION" != "$CURRENT_VERSION" ]]; then
  PUBSPEC_BACKUP="$(mktemp)"
  cp "$PUBSPEC_PATH" "$PUBSPEC_BACKUP"
  write_pubspec_version "$NEXT_VERSION"
  PUBSPEC_WAS_UPDATED=1
  log "updated pubspec.yaml version to $NEXT_VERSION"
fi

AAPT_TOOL="$(find_android_tool aapt)"
APKSIGNER_TOOL="$(find_android_tool apksigner)"
prepare_macos_project
build_sdk_native

OUTPUT_DIR="$DIST_ROOT/$NEXT_VERSION"
mkdir -p "$OUTPUT_DIR"

ANDROID_APK="$OUTPUT_DIR/awiki-me-android-arm64-debug-$NEXT_VERSION.apk"
MACOS_ARM64_DMG="$OUTPUT_DIR/awiki-me-macos-arm64-debug-$NEXT_VERSION.dmg"
MACOS_X64_DMG="$OUTPUT_DIR/awiki-me-macos-x64-debug-$NEXT_VERSION.dmg"

build_android_arm64 "$ANDROID_APK" "$AAPT_TOOL" "$APKSIGNER_TOOL"
build_macos_arch "arm64" "arm64" "$MACOS_ARM64_DMG"
build_macos_arch "x86_64" "x64" "$MACOS_X64_DMG"
write_manifest "$OUTPUT_DIR" "$ANDROID_APK" "$MACOS_ARM64_DMG" "$MACOS_X64_DMG"

log "done"
log "output: $OUTPUT_DIR"
log "manifest: $OUTPUT_DIR/latest.json"
