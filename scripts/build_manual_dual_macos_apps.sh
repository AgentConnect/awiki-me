#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
Build two independently runnable macOS Debug Apps from lib/main.dart.

Usage:
  scripts/build_manual_dual_macos_apps.sh

Environment:
  FLUTTER_BIN                         Flutter executable (default: flutter)
  AWIKI_IM_CORE_REPO_DIR              awiki-cli-rs2 checkout
                                      (default: ../awiki-cli-rs2)
  AWIKI_PRIMARY_TENANT_DOMAIN         Shared tenant domain (default: awiki.info)
USAGE
  exit 0
fi
[[ $# -eq 0 ]] || {
  echo "error: unknown argument: $1" >&2
  exit 2
}
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "x86_64" ]] || {
  echo "error: manual dual-App builds require Intel macOS" >&2
  exit 2
}

flutter_bin="${FLUTTER_BIN:-flutter}"
command -v "$flutter_bin" >/dev/null 2>&1 || {
  echo "error: Flutter executable not found: $flutter_bin" >&2
  exit 2
}
flutter_bin="$(command -v "$flutter_bin")"

im_core_repo_dir="${AWIKI_IM_CORE_REPO_DIR:-$ROOT_DIR/../awiki-cli-rs2}"
im_core_repo_dir="$(cd "$im_core_repo_dir" 2>/dev/null && pwd)" || {
  echo "error: awiki-cli-rs2 checkout is unavailable" >&2
  exit 2
}
im_core_build_script="$im_core_repo_dir/scripts/flutter/build-sdk-native.sh"
im_core_verify_script="$ROOT_DIR/scripts/verify_im_core_native_artifact.sh"
im_core_library="$im_core_repo_dir/packages/awiki_im_core/macos/Frameworks/AwikiImCore.xcframework/macos-x86_64/libawiki_im_core.a"

prepare_native_dependency() {
  [[ -x "$im_core_build_script" ]] || {
    echo "error: native Core build script is unavailable: $im_core_build_script" >&2
    return 1
  }
  [[ -x "$im_core_verify_script" ]] || {
    echo "error: native Core verifier is unavailable: $im_core_verify_script" >&2
    return 1
  }

  local source_revision
  source_revision="$(git -C "$im_core_repo_dir" rev-parse --verify HEAD)" || return 1
  if AWIKI_IM_CORE_REPO_DIR="$im_core_repo_dir" \
      "$im_core_verify_script" >/dev/null 2>&1 && \
      [[ -f "$im_core_library" ]] && \
      [[ "$(/usr/bin/lipo -archs "$im_core_library")" == "x86_64" ]]; then
    echo "Using verified x86_64 awiki_im_core from source revision $source_revision"
  else
    echo "Rebuilding stale awiki_im_core from source revision $source_revision"
    PATH="$(dirname "$flutter_bin"):$PATH" \
      "$im_core_build_script" --macos-only --macos-arch x86_64
  fi

  AWIKI_IM_CORE_REPO_DIR="$im_core_repo_dir" \
    "$im_core_verify_script" || {
      echo "error: native Core provenance verification failed" >&2
      return 1
    }
  [[ -f "$im_core_library" ]] || {
    echo "error: native Core library is missing: $im_core_library" >&2
    return 1
  }
  [[ "$(/usr/bin/lipo -archs "$im_core_library")" == "x86_64" ]] || {
    echo "error: native Core library must be x86_64-only" >&2
    return 1
  }
}

tenant_domain="${AWIKI_PRIMARY_TENANT_DOMAIN:-awiki.info}"
[[ "$tenant_domain" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]] || {
  echo "error: AWIKI_PRIMARY_TENANT_DOMAIN must be a lowercase hostname" >&2
  exit 2
}
manual_root="$ROOT_DIR/build/manual-multi-device"
admin_cache="$manual_root/admin-cache"
joiner_cache="$manual_root/joiner-cache"
joiner_build_rel="build/manual-multi-device/joiner-flutter-build"
joiner_build="$ROOT_DIR/$joiner_build_rel"
admin_app="$ROOT_DIR/build/macos/Build/Products/Debug/AWikiMe.app"
joiner_app="$manual_root/AWikiMe-Joiner.app"

prepare_native_dependency || exit 1

mkdir -p \
  "$admin_cache/flutter-config" \
  "$joiner_cache/flutter-config" \
  "$manual_root"
printf '%s\n' '{"build-dir":"build","enable-macos-desktop":true}' \
  > "$admin_cache/flutter-config/settings"
printf '{"build-dir":"%s","enable-macos-desktop":true}\n' "$joiner_build_rel" \
  > "$joiner_cache/flutter-config/settings"

cat > "$admin_cache/ManualAdmin.xcconfig" <<EOF
AWIKI_MACOS_DEV_BUNDLE_ID = ai.awiki.awikime.dev
AWIKI_APP_DISPLAY_NAME = AWikiMe (Development)
AWIKI_PRIMARY_TENANT_DOMAIN = $tenant_domain
EOF
cat > "$joiner_cache/ManualJoiner.xcconfig" <<EOF
AWIKI_MACOS_DEV_BUNDLE_ID = ai.awiki.awikime.dev.manual.joiner
AWIKI_APP_DISPLAY_NAME = AWikiMe Joiner
AWIKI_PRIMARY_TENANT_DOMAIN = $tenant_domain
EOF

lock_snapshot="$(mktemp)"
pod_lock_snapshot="$(mktemp)"
cp pubspec.lock "$lock_snapshot"
cp macos/Podfile.lock "$pod_lock_snapshot"
restore_lock() {
  cp "$lock_snapshot" pubspec.lock
  cp "$pod_lock_snapshot" macos/Podfile.lock
  rm -f "$lock_snapshot" "$pod_lock_snapshot"
}
trap restore_lock EXIT

build_app() {
  local flutter_config="$1"
  local xcode_config="$2"
  LANG=en_US.UTF-8 \
  LC_ALL=en_US.UTF-8 \
  XDG_CONFIG_HOME="$flutter_config" \
  XCODE_XCCONFIG_FILE="$xcode_config" \
    "$flutter_bin" build macos \
      --debug \
      --no-pub \
      --target=lib/main.dart \
      --dart-define="AWIKI_PRIMARY_TENANT_DOMAIN=$tenant_domain"
}

verify_native_intermediate() {
  local flutter_build_root="$1"
  local copied_library="$flutter_build_root/macos/Build/Products/Debug/XCFrameworkIntermediates/awiki_im_core/libawiki_im_core.a"
  [[ -f "$copied_library" ]] || {
    echo "error: Flutter build did not copy the native Core library: $copied_library" >&2
    exit 1
  }
  /usr/bin/cmp -s "$im_core_library" "$copied_library" || {
    echo "error: Flutter build used a stale native Core library: $copied_library" >&2
    exit 1
  }
}

prepare_native_intermediate() {
  local flutter_build_root="$1"
  local copied_dir="$flutter_build_root/macos/Build/Products/Debug/XCFrameworkIntermediates/awiki_im_core"
  local copied_library="$copied_dir/libawiki_im_core.a"
  if [[ -f "$copied_library" ]] && \
      /usr/bin/cmp -s "$im_core_library" "$copied_library"; then
    echo "Keeping verified Flutter native Core intermediate: $copied_library"
    return
  fi

  echo "Invalidating stale Flutter native Core intermediate: $copied_dir"
  rm -rf \
    "$copied_dir" \
    "$flutter_build_root/macos/Build/Intermediates.noindex/Pods.build/Debug/awiki_im_core.build"
  # CocoaPods declares the XCFramework as an input. Updating its timestamp and
  # removing the matching Pod target state forces Xcode to recopy the slice.
  /usr/bin/touch "$im_core_library"
}

prepare_native_intermediate "$joiner_build"
build_app \
  "$joiner_cache/flutter-config" \
  "$joiner_cache/ManualJoiner.xcconfig"
verify_native_intermediate "$joiner_build"
joiner_source="$joiner_build/macos/Build/Products/Debug/AWikiMe.app"
[[ -d "$joiner_source" ]] || {
  echo "error: Joiner build did not produce an App" >&2
  exit 1
}
rm -rf "$joiner_app"
/usr/bin/ditto "$joiner_source" "$joiner_app"

prepare_native_intermediate "$ROOT_DIR/build"
build_app \
  "$admin_cache/flutter-config" \
  "$admin_cache/ManualAdmin.xcconfig"
verify_native_intermediate "$ROOT_DIR/build"

verify_app() {
  local app="$1"
  local expected_bundle_id="$2"
  [[ -d "$app" ]] || {
    echo "error: App is missing: $app" >&2
    exit 1
  }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == "$expected_bundle_id" ]] || {
    echo "error: unexpected bundle ID: $app" >&2
    exit 1
  }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :AWikiPrimaryTenantDomain' "$app/Contents/Info.plist")" == "$tenant_domain" ]] || {
    echo "error: tenant domain mismatch: $app" >&2
    exit 1
  }
  [[ "$(/usr/bin/lipo -archs "$app/Contents/MacOS/AWikiMe")" == "x86_64" ]] || {
    echo "error: App must be x86_64-only: $app" >&2
    exit 1
  }
  /usr/bin/codesign --verify --deep --strict "$app"
}

verify_app "$admin_app" 'ai.awiki.awikime.dev'
verify_app "$joiner_app" 'ai.awiki.awikime.dev.manual.joiner'

cat <<EOF
Built two standalone Debug Apps for $tenant_domain:
  Admin:  $admin_app
  Joiner: $joiner_app

Launch both:
  open -n '$admin_app'
  open -n '$joiner_app'
EOF
