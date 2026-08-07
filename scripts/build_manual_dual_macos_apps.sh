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
cp pubspec.lock "$lock_snapshot"
restore_lock() {
  cp "$lock_snapshot" pubspec.lock
  rm -f "$lock_snapshot"
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

build_app \
  "$joiner_cache/flutter-config" \
  "$joiner_cache/ManualJoiner.xcconfig"
joiner_source="$joiner_build/macos/Build/Products/Debug/AWikiMe.app"
[[ -d "$joiner_source" ]] || {
  echo "error: Joiner build did not produce an App" >&2
  exit 1
}
rm -rf "$joiner_app"
/usr/bin/ditto "$joiner_source" "$joiner_app"

build_app \
  "$admin_cache/flutter-config" \
  "$admin_cache/ManualAdmin.xcconfig"

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
