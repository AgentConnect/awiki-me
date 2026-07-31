#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SIGNING_LIB="$SCRIPT_DIR/lib/macos_signing.sh"
DMGBUILD_VERSION="1.6.7"
MACOS_DMG_BACKGROUND="$ROOT_DIR/installer/macos/dmg-background.png"
MACOS_DMG_SETTINGS="$ROOT_DIR/installer/macos/dmg_settings.py"
ANDROID_APP_ID="ai.awiki.awikime"
ANDROID_EXPECTED_CERT_SHA256="F2:67:E9:18:57:54:ED:C1:2B:E5:69:69:1B:39:B9:EF:D4:EF:1E:CF:2D:7E:D8:18:81:42:69:B3:70:85:D8:75"
cd "$ROOT_DIR"

fail() {
  printf '[package-worker] error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

normalize_sha256() {
  tr '[:lower:]' '[:upper:]' | tr -d '[:space:]:'
}

option_value() {
  local name="$1"
  local value="$2"
  [[ -n "$value" ]] || fail "$name must not be empty"
  printf '%s\n' "$value"
}

TARGET=""
VERSION=""
BUILD_NUMBER=""
APP_REF=""
CORE_REF=""
ANP_REF=""
PRIMARY_TENANT_DOMAIN=""
ANDROID_STARTUP_SMOKE_TEST="auto"
OUTPUT_DIR=""
CORE_DIR="$(cd "$ROOT_DIR/../awiki-cli-rs2" 2>/dev/null && pwd || true)"
ANP_DIR="$(cd "$ROOT_DIR/../anp/anp" 2>/dev/null && pwd || true)"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$(option_value "$1" "${2:-}")"; shift 2 ;;
    --version) VERSION="$(option_value "$1" "${2:-}")"; shift 2 ;;
    --build-number) BUILD_NUMBER="$(option_value "$1" "${2:-}")"; shift 2 ;;
    --app-ref) APP_REF="$(option_value "$1" "${2:-}")"; shift 2 ;;
    --core-ref) CORE_REF="$(option_value "$1" "${2:-}")"; shift 2 ;;
    --anp-ref) ANP_REF="$(option_value "$1" "${2:-}")"; shift 2 ;;
    --primary-tenant-domain) PRIMARY_TENANT_DOMAIN="$(option_value "$1" "${2:-}")"; shift 2 ;;
    --android-startup-smoke-test) ANDROID_STARTUP_SMOKE_TEST="$(option_value "$1" "${2:-}")"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$(option_value "$1" "${2:-}")"; shift 2 ;;
    --core-dir) CORE_DIR="$(option_value "$1" "${2:-}")"; shift 2 ;;
    --anp-dir) ANP_DIR="$(option_value "$1" "${2:-}")"; shift 2 ;;
    -h|--help)
      printf '%s\n' 'Usage: package_unix_worker.sh --target android-arm64|macos-arm64|macos-x64 --version VERSION --build-number NUMBER --app-ref SHA --core-ref SHA --anp-ref SHA --primary-tenant-domain DOMAIN [--android-startup-smoke-test auto|always|never] --output-dir DIR'
      exit 0
      ;;
    *) fail "unknown argument: $1" ;;
  esac
done

case "$TARGET" in
  android-arm64|macos-arm64|macos-x64) ;;
  *) fail "unsupported Unix worker target: $TARGET" ;;
esac
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] ||
  fail "invalid version: $VERSION"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || fail "invalid build number"
for ref in "$APP_REF" "$CORE_REF" "$ANP_REF"; do
  [[ "$ref" =~ ^[0-9a-f]{40}$ ]] || fail "source refs must be lowercase full SHAs"
done
[[ -n "$PRIMARY_TENANT_DOMAIN" && -n "$OUTPUT_DIR" ]] ||
  fail "primary tenant domain and output directory are required"
case "$ANDROID_STARTUP_SMOKE_TEST" in
  auto|always|never) ;;
  *) fail "Android startup smoke policy must be auto, always, or never" ;;
esac
[[ -d "$CORE_DIR" && -d "$ANP_DIR" ]] || fail "Core or ANP checkout is missing"

require_cmd dart
require_cmd flutter
require_cmd git
require_cmd python3

[[ "$(git rev-parse 'HEAD^{commit}')" == "$APP_REF" ]] || fail "APP checkout ref mismatch"
[[ "$(git -C "$CORE_DIR" rev-parse 'HEAD^{commit}')" == "$CORE_REF" ]] || fail "Core checkout ref mismatch"
[[ "$(git -C "$ANP_DIR" rev-parse 'HEAD^{commit}')" == "$ANP_REF" ]] || fail "ANP checkout ref mismatch"

FLUTTER_VERSION="$(flutter --version | sed -n 's/^Flutter \([^[:space:]]*\).*/\1/p' | tail -1)"
[[ "$FLUTTER_VERSION" == "3.44.0" ]] || fail "Flutter must be 3.44.0, got $FLUTTER_VERSION"
RUST_VERSION="$(cd "$CORE_DIR" && rustc --version | awk '{print $2}')"
[[ "$RUST_VERSION" == "1.88.0" ]] || fail "Rust must be 1.88.0, got $RUST_VERSION"

mkdir -p "$OUTPUT_DIR"

write_android_release_plugin_registrant() {
  local registrant="$ROOT_DIR/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
  python3 - "$ROOT_DIR" "$registrant" <<'PY'
import json, pathlib, re, sys

root = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
dependencies = json.loads((root / ".flutter-plugins-dependencies").read_text(encoding="utf-8"))

def android_block(text):
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if re.match(r"^\s{6}android:\s*(?:#.*)?$", line):
            block = []
            for next_line in lines[index + 1:]:
                if not next_line.startswith("        "):
                    break
                block.append(next_line[8:])
            return "\n".join(block)
    return ""

def value(block, key):
    match = re.search(rf"^\s*{re.escape(key)}:\s*(.+?)\s*$", block, re.MULTILINE)
    return None if not match else match.group(1).split("#", 1)[0].strip().strip("\"'")

registrations = []
for plugin in dependencies.get("plugins", {}).get("android", []):
    if plugin.get("dev_dependency"):
        continue
    name = str(plugin.get("name") or "").strip()
    pubspec = pathlib.Path(str(plugin.get("path") or "")) / "pubspec.yaml"
    if not name or not pubspec.is_file():
        continue
    block = android_block(pubspec.read_text(encoding="utf-8"))
    package = value(block, "package")
    plugin_class = value(block, "pluginClass")
    if package and plugin_class:
        registrations.append((name, package, plugin_class))
if not registrations:
    raise SystemExit("no production Android plugins found")

body = []
for name, package, plugin_class in registrations:
    full_class = f"{package}.{plugin_class}"
    body.extend([
        "    try {",
        f"      flutterEngine.getPlugins().add(new {full_class}());",
        "    } catch (Exception e) {",
        f'      Log.e(TAG, "Error registering plugin {name}, {full_class}", e);',
        "    }",
    ])
source = f'''package io.flutter.plugins;

import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import io.flutter.Log;
import io.flutter.embedding.engine.FlutterEngine;

/** Generated for release packaging. */
@Keep
public final class GeneratedPluginRegistrant {{
  private static final String TAG = "GeneratedPluginRegistrant";
  public static void registerWith(@NonNull FlutterEngine flutterEngine) {{
{chr(10).join(body)}
  }}
}}
'''
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(source, encoding="utf-8")
PY
}

metadata() {
  local filename="$1"
  dart run tool/package_manifest.dart metadata \
    --target "$TARGET" \
    --filename "$filename" \
    --signing-state signed \
    --version "$VERSION" \
    --build-number "$BUILD_NUMBER" \
    --app-ref "$APP_REF" \
    --core-ref "$CORE_REF" \
    --anp-ref "$ANP_REF" \
    --output "$OUTPUT_DIR/artifact-metadata.json"
}

android_smoke_test_device() {
  if [[ "$ANDROID_STARTUP_SMOKE_TEST" == "never" ]]; then
    return 0
  fi
  if ! command -v adb >/dev/null 2>&1; then
    [[ "$ANDROID_STARTUP_SMOKE_TEST" == "auto" ]] && return 0
    fail "adb is required for Android startup smoke verification"
  fi

  local emulator_devices count
  emulator_devices="$(adb devices | awk 'NR > 1 && $2 == "device" && $1 ~ /^emulator-/ { print $1 }')"
  count="$(printf '%s\n' "$emulator_devices" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  if [[ "$ANDROID_STARTUP_SMOKE_TEST" == "auto" ]]; then
    if [[ "$count" -eq 1 ]]; then
      printf '%s\n' "$emulator_devices" | sed -n '1p'
    fi
    return 0
  fi

  [[ "$count" -eq 1 ]] ||
    fail "Android startup smoke verification requires exactly one emulator; found $count"
  printf '%s\n' "$emulator_devices" | sed -n '1p'
}

verify_android_startup_smoke() {
  local apk="$1" device pid crash_log
  device="$(android_smoke_test_device)"
  if [[ -z "$device" ]]; then
    printf '%s\n' '[package-worker] skipping Android startup smoke verification'
    return 0
  fi

  adb -s "$device" install -r "$apk" >/dev/null
  adb -s "$device" shell pm clear "$ANDROID_APP_ID" >/dev/null
  adb -s "$device" logcat -c
  adb -s "$device" shell monkey \
    -p "$ANDROID_APP_ID" \
    -c android.intent.category.LAUNCHER \
    1 >/dev/null
  sleep 6

  pid="$(adb -s "$device" shell pidof "$ANDROID_APP_ID" 2>/dev/null | tr -d '\r' || true)"
  crash_log="$(adb -s "$device" logcat -d -t 1200 | grep -Ei \
    'FATAL EXCEPTION|Fatal signal|SIGSEGV|UnsatisfiedLink|ClassNotFoundException|dlopen failed|native crash|tombstone|Force finishing activity' || true)"
  if [[ -z "$pid" || -n "$crash_log" ]]; then
    printf '%s\n' "$crash_log" >&2
    fail "Android startup smoke verification failed"
  fi
}

build_android() {
  [[ -f android/key.properties ]] || fail "android/key.properties is required for release signing"
  (cd "$CORE_DIR" &&
    scripts/flutter/build-sdk-native.sh \
      --android-only \
      --android-abi arm64-v8a \
      --skip-codegen-check)
  flutter pub get
  write_android_release_plugin_registrant
  flutter build apk \
    --release \
    --no-pub \
    --target-platform android-arm64 \
    --split-per-abi \
    --dart-define="AWIKI_PRIMARY_TENANT_DOMAIN=$PRIMARY_TENANT_DOMAIN" \
    --dart-define="AWIKI_APP_SOURCE_REF=$APP_REF" \
    --dart-define="AWIKI_IM_CORE_SOURCE_REF=$CORE_REF" \
    --build-name "$VERSION" \
    --build-number "$BUILD_NUMBER"

  local built="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
  local filename="AWiki-Me-Android-arm64-$VERSION.apk"
  [[ -f "$built" ]] || fail "Android arm64 APK was not produced"
  local sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  [[ -n "$sdk_root" ]] || fail "ANDROID_SDK_ROOT or ANDROID_HOME is required"
  local aapt apksigner
  aapt="$(find "$sdk_root/build-tools" -type f -name aapt | sort -V | tail -1)"
  apksigner="$(find "$sdk_root/build-tools" -type f -name apksigner | sort -V | tail -1)"
  [[ -x "$aapt" && -x "$apksigner" ]] || fail "Android build-tools are incomplete"
  local badging version_code expected_version_code verify_output actual_cert
  local actual_cert_normalized expected_cert_normalized
  badging="$("$aapt" dump badging "$built")"
  printf '%s\n' "$badging" | grep -Fq "package: name='$ANDROID_APP_ID'" ||
    fail "Android applicationId mismatch"
  printf '%s\n' "$badging" | grep -Fq "versionName='$VERSION'" ||
    fail "Android versionName mismatch"
  version_code="$(printf '%s\n' "$badging" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" | head -1)"
  expected_version_code=$((BUILD_NUMBER + 2000))
  [[ "$version_code" == "$expected_version_code" ]] ||
    fail "Android arm64 split versionCode is $version_code, expected $expected_version_code"
  if printf '%s\n' "$badging" | grep -q '^application-debuggable'; then
    fail "Android package is debuggable"
  fi

  verify_output="$("$apksigner" verify --verbose --print-certs "$built" 2>&1)" ||
    fail "Android APK signature verification failed: $verify_output"
  actual_cert="$(printf '%s\n' "$verify_output" | sed -n 's/.*certificate SHA-256 digest:[[:space:]]*//p' | head -1)"
  [[ -n "$actual_cert" ]] || fail "Android signing certificate SHA-256 is missing"
  actual_cert_normalized="$(printf '%s' "$actual_cert" | normalize_sha256)"
  expected_cert_normalized="$(printf '%s' "$ANDROID_EXPECTED_CERT_SHA256" | normalize_sha256)"
  [[ "$actual_cert_normalized" == "$expected_cert_normalized" ]] ||
    fail "Android signing certificate changed: $actual_cert"

  python3 - "$built" "$ROOT_DIR/.flutter-plugins-dependencies" <<'PY'
import json, pathlib, re, sys, zipfile

apk_path = pathlib.Path(sys.argv[1])
dependencies_path = pathlib.Path(sys.argv[2])
dev_names = []
dev_markers = []
if dependencies_path.exists():
    dependencies = json.loads(dependencies_path.read_text(encoding="utf-8"))
    for plugin in dependencies.get("plugins", {}).get("android", []):
        if not plugin.get("dev_dependency"):
            continue
        name = str(plugin.get("name") or "").strip()
        if name:
            dev_names.append(name)
            dev_markers.append(name.encode())
        pubspec = pathlib.Path(str(plugin.get("path") or "")) / "pubspec.yaml"
        if pubspec.exists():
            source = pubspec.read_text(encoding="utf-8", errors="ignore")
            for key in ("pluginClass", "package"):
                match = re.search(rf"^\s*{key}:\s*(.+?)\s*$", source, re.MULTILINE)
                if match:
                    marker = match.group(1).split("#", 1)[0].strip().strip("\"'")
                    if marker:
                        dev_markers.append(marker.encode())

scan = bytearray()
with zipfile.ZipFile(apk_path) as archive:
    native = [name for name in archive.namelist() if name.startswith("lib/") and name.endswith(".so")]
    for info in archive.infolist():
        name = info.filename
        if name.endswith(".dex") or name.startswith("lib/") or name.startswith("META-INF/services/"):
            scan.extend(name.encode(errors="ignore"))
            scan.extend(b"\0")
            scan.extend(archive.read(info))
if not native or any(not name.startswith("lib/arm64-v8a/") for name in native):
    raise SystemExit("APK does not contain only arm64-v8a native libraries")
if not any(name.endswith("libawiki_im_core.so") for name in native):
    raise SystemExit("APK is missing libawiki_im_core.so")
if b"Lio/flutter/plugins/GeneratedPluginRegistrant;" not in scan:
    raise SystemExit("APK is missing the production Flutter plugin registrant")
leaked = {name for name in dev_names if name.encode() in scan}
leaked.update(marker.decode(errors="replace") for marker in dev_markers if marker in scan)
if leaked:
    raise SystemExit("APK contains dev-only plugins: " + ", ".join(sorted(leaked)))
PY
  verify_android_startup_smoke "$built"
  cp "$built" "$OUTPUT_DIR/$filename"
  metadata "$filename"
}

verify_macos_dmg() {
  local dmg="$1"
  local expected_arch="$2"

  (
    set -euo pipefail
    local mount_point="$ROOT_DIR/build/package/verify-$TARGET"
    local mounted="false"

    cleanup_macos_dmg_mount() {
      if [[ "$mounted" == "true" ]]; then
        if ! hdiutil detach "$mount_point" >/dev/null 2>&1 &&
          ! hdiutil detach -force "$mount_point" >/dev/null 2>&1; then
          return 1
        fi
        mounted="false"
      fi
      rm -rf "$mount_point"
    }

    cleanup_macos_dmg_mount_on_exit() {
      local status=$?
      trap - EXIT
      if ! cleanup_macos_dmg_mount; then
        printf 'failed to detach macOS DMG verification mount: %s\n' \
          "$mount_point" >&2
        status=1
      fi
      exit "$status"
    }
    trap cleanup_macos_dmg_mount_on_exit EXIT
    trap 'exit 130' HUP INT TERM

    rm -rf "$mount_point"
    mkdir -p "$mount_point"
    hdiutil verify "$dmg" >/dev/null
    hdiutil attach \
      -readonly \
      -nobrowse \
      -noautoopen \
      -mountpoint "$mount_point" \
      "$dmg" >/dev/null
    mounted="true"

    [[ -d "$mount_point/AWikiMe.app" ]] ||
      fail "macOS DMG is missing AWikiMe.app"
    [[ -L "$mount_point/Applications" ]] ||
      fail "macOS DMG is missing the Applications link"
    [[ "$(readlink "$mount_point/Applications")" == "/Applications" ]] ||
      fail "macOS DMG Applications link has the wrong target"
    [[ -s "$mount_point/.DS_Store" ]] ||
      fail "macOS DMG is missing Finder layout metadata"
    [[ -f "$mount_point/.background.png" ]] ||
      fail "macOS DMG is missing the Finder background"
    cmp -s \
      "$MACOS_DMG_BACKGROUND" \
      "$mount_point/.background.png" ||
      fail "macOS DMG Finder background does not match the source asset"
    [[ "$(lipo -archs "$mount_point/AWikiMe.app/Contents/MacOS/AWikiMe")" == "$expected_arch" ]] ||
      fail "mounted macOS app architecture mismatch"
    codesign --verify --deep --strict --verbose=2 "$mount_point/AWikiMe.app"
    awiki_verify_macos_app_signature \
      "$mount_point/AWikiMe.app" \
      "$AWIKI_MACOS_DEVELOPMENT_TEAM" \
      ai.awiki.awikime || fail "mounted macOS app signature contract failed"
  )
}

build_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "macOS packages require a macOS worker"
  [[ -f "$SIGNING_LIB" ]] || fail "macOS signing helper is missing"
  [[ -f "$MACOS_DMG_BACKGROUND" ]] || fail "macOS DMG background is missing"
  [[ -f "$MACOS_DMG_SETTINGS" ]] || fail "macOS DMG settings are missing"
  local dmgbuild_python="${DMGBUILD_PYTHON:-python3}"
  command -v "$dmgbuild_python" >/dev/null 2>&1 ||
    fail "required command not found: $dmgbuild_python"
  [[ "$("$dmgbuild_python" -c \
    'from importlib.metadata import version; print(version("dmgbuild"))')" == \
    "$DMGBUILD_VERSION" ]] || fail "dmgbuild must be $DMGBUILD_VERSION"
  # shellcheck source=scripts/lib/macos_signing.sh
  source "$SIGNING_LIB"
  : "${AWIKI_MACOS_SIGNING_IDENTITY:?AWIKI_MACOS_SIGNING_IDENTITY is required}"
  : "${AWIKI_MACOS_DEVELOPMENT_TEAM:?AWIKI_MACOS_DEVELOPMENT_TEAM is required}"
  local fingerprint
  fingerprint="$(awiki_resolve_codesigning_identity "$AWIKI_MACOS_SIGNING_IDENTITY")" ||
    fail "configured macOS signing identity is unavailable"

  local arch arch_label filename derived app
  if [[ "$TARGET" == "macos-arm64" ]]; then
    arch="arm64"
    arch_label="arm64"
  else
    arch="x86_64"
    arch_label="x64"
  fi
  (cd "$CORE_DIR" &&
    scripts/flutter/build-sdk-native.sh \
      --macos-only \
      --macos-arch "$arch" \
      --skip-codegen-check)
  flutter pub get
  [[ -d macos/Runner.xcworkspace ]] || fail "macOS Runner workspace is missing"
  filename="AWiki-Me-macOS-$arch_label-$VERSION.dmg"
  derived="$ROOT_DIR/build/package/derived-$TARGET"
  app="$derived/Build/Products/Release/AWikiMe.app"
  rm -rf "$derived"
  flutter build macos \
    --release \
    --no-pub \
    --config-only \
    --dart-define="AWIKI_PRIMARY_TENANT_DOMAIN=$PRIMARY_TENANT_DOMAIN" \
    --dart-define="AWIKI_APP_SOURCE_REF=$APP_REF" \
    --dart-define="AWIKI_IM_CORE_SOURCE_REF=$CORE_REF" \
    --build-name "$VERSION" \
    --build-number "$BUILD_NUMBER"
  xcodebuild \
    -workspace macos/Runner.xcworkspace \
    -scheme Runner \
    -configuration Release \
    -derivedDataPath "$derived" \
    -destination 'platform=macOS' \
    ARCHS="$arch" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$fingerprint" \
    DEVELOPMENT_TEAM="$AWIKI_MACOS_DEVELOPMENT_TEAM" \
    AWIKI_APP_SOURCE_REF="$APP_REF" \
    AWIKI_IM_CORE_SOURCE_REF="$CORE_REF" \
    AWIKI_PRIMARY_TENANT_DOMAIN="$PRIMARY_TENANT_DOMAIN" \
    FLUTTER_BUILD_NAME="$VERSION" \
    FLUTTER_BUILD_NUMBER="$BUILD_NUMBER" \
    build

  [[ -d "$app" ]] || fail "macOS app was not produced"
  [[ "$(lipo -archs "$app/Contents/MacOS/AWikiMe")" == "$arch" ]] ||
    fail "macOS executable architecture mismatch"
  codesign --verify --deep --strict --verbose=2 "$app"
  awiki_verify_macos_app_signature \
    "$app" "$AWIKI_MACOS_DEVELOPMENT_TEAM" ai.awiki.awikime ||
    fail "macOS signature contract failed"

  local dmg_work="$ROOT_DIR/build/package/dmg-$TARGET"
  local staged_dmg="$dmg_work/$filename"
  rm -rf "$dmg_work" "$OUTPUT_DIR/$filename"
  mkdir -p "$dmg_work"
  "$dmgbuild_python" -m dmgbuild \
    --settings "$MACOS_DMG_SETTINGS" \
    --no-hidpi \
    --detach-retries 5 \
    -D "application=$app" \
    -D "background=$MACOS_DMG_BACKGROUND" \
    "AWikiMe $VERSION $arch_label" \
    "$staged_dmg"
  hdiutil imageinfo "$staged_dmg" | grep -Fq 'Format: UDZO' ||
    fail "macOS DMG is not UDZO"
  verify_macos_dmg "$staged_dmg" "$arch"
  mv "$staged_dmg" "$OUTPUT_DIR/$filename"
  rm -rf "$dmg_work"
  metadata "$filename"
}

if [[ "$TARGET" == "android-arm64" ]]; then
  build_android
else
  build_macos
fi
