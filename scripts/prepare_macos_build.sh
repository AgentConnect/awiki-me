#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

flutter_bin="${FLUTTER_BIN:-flutter}"
if ! command -v "$flutter_bin" >/dev/null 2>&1; then
  cat >&2 <<'MSG'
error: flutter is not on PATH.
Set FLUTTER_BIN to your Flutter executable, for example:
  FLUTTER_BIN=/path/to/flutter/bin/flutter scripts/prepare_macos_build.sh
MSG
  exit 1
fi

# Some machines have full Xcode installed but xcode-select points at the
# CommandLineTools directory. Use the full Xcode for this process without
# changing global developer-dir state.
if ! xcrun --find xcodebuild >/dev/null 2>&1; then
  default_xcode="/Applications/Xcode.app/Contents/Developer"
  if [[ -x "$default_xcode/usr/bin/xcodebuild" ]]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-$default_xcode}"
  fi
fi

if ! xcrun --find xcodebuild >/dev/null 2>&1; then
  cat >&2 <<'MSG'
error: xcodebuild was not found.
Install/open full Xcode, then either select it globally:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
or run this script with:
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/prepare_macos_build.sh
MSG
  exit 1
fi

if ! command -v pod >/dev/null 2>&1; then
  cat >&2 <<'MSG'
error: CocoaPods is not installed or not on PATH.
Install it before building the macOS runner, for example:
  brew install cocoapods
or:
  sudo gem install cocoapods
MSG
  exit 1
fi

# CocoaPods normalizes paths as Unicode and fails under ASCII/C locales.
# Set these unconditionally for compatibility with the macOS system Bash.
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8

export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://mirrors.tuna.tsinghua.edu.cn/dart-pub}"
"$flutter_bin" pub get
(
  cd macos
  pod install
)

expected="macos/Pods/Target Support Files/Pods-Runner/Pods-Runner-frameworks-Debug-input-files.xcfilelist"
if [[ ! -f "$expected" ]]; then
  echo "error: CocoaPods did not generate $expected" >&2
  exit 1
fi

cat <<'MSG'
macOS dependencies are ready.
Open macos/Runner.xcworkspace in Xcode, not macos/Runner.xcodeproj.
For CLI builds, run: flutter build macos
MSG
