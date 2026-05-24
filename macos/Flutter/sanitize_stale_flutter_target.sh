# Prevent Xcode from reusing Flutter test-runner state as the app entrypoint.
#
# `flutter test -d macos` writes a temporary flutter_test_listener target into
# Flutter-Generated.xcconfig. That temp file is deleted when the test process
# exits, but Xcode may still read the stale target on the next GUI build.
# Source this script from Xcode build phases before invoking macos_assemble.sh.

DEFAULT_FLUTTER_TARGET="${DEFAULT_FLUTTER_TARGET:-lib/main.dart}"
PROJECT_PATH="${FLUTTER_APPLICATION_PATH:-${SOURCE_ROOT:-}/..}"
FLUTTER_TARGET_VALUE="${FLUTTER_TARGET:-}"

flutter_target_exists() {
  case "$1" in
    "")
      return 1
      ;;
    /*)
      [ -f "$1" ]
      ;;
    *)
      [ -f "$PROJECT_PATH/$1" ]
      ;;
  esac
}

should_reset_flutter_target=false
case "$FLUTTER_TARGET_VALUE" in
  *flutter_test_listener* | /*)
    if ! flutter_target_exists "$FLUTTER_TARGET_VALUE"; then
      should_reset_flutter_target=true
    fi
    ;;
esac

if [ "$should_reset_flutter_target" = true ]; then
  echo "Resetting stale FLUTTER_TARGET ($FLUTTER_TARGET_VALUE) to $DEFAULT_FLUTTER_TARGET"
  export FLUTTER_TARGET="$DEFAULT_FLUTTER_TARGET"

  FLUTTER_GENERATED_CONFIG="$PROJECT_DIR/Flutter/ephemeral/Flutter-Generated.xcconfig"
  if [ -f "$FLUTTER_GENERATED_CONFIG" ]; then
    sed -i '' "s|^FLUTTER_TARGET=.*|FLUTTER_TARGET=$DEFAULT_FLUTTER_TARGET|" "$FLUTTER_GENERATED_CONFIG"
  fi

  FLUTTER_EXPORT_ENV="$PROJECT_DIR/Flutter/ephemeral/flutter_export_environment.sh"
  if [ -f "$FLUTTER_EXPORT_ENV" ]; then
    sed -i '' "s|^export \"FLUTTER_TARGET=.*\"|export \"FLUTTER_TARGET=$DEFAULT_FLUTTER_TARGET\"|" "$FLUTTER_EXPORT_ENV"
  fi
fi
