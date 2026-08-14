#!/usr/bin/env bash

awiki_macos_signing_error() {
  printf '[macos-signing] error: %s\n' "$*" >&2
}

awiki_resolve_codesigning_identity() {
  local identity="$1"
  local identities line fingerprint

  [[ "$(uname -s)" == "Darwin" ]] || {
    awiki_macos_signing_error "macOS is required"
    return 1
  }
  command -v security >/dev/null 2>&1 || {
    awiki_macos_signing_error "security is required"
    return 1
  }
  [[ -n "$identity" && "$identity" != "-" ]] || {
    awiki_macos_signing_error "a non-ad-hoc signing identity is required"
    return 1
  }

  identities="$(security find-identity -v -p codesigning 2>/dev/null)"
  case "$identity" in
    [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]*)
      line="$(grep -i -m 1 " $identity " <<< "$identities" || true)"
      ;;
    *)
      line="$(grep -F -m 1 "\"$identity\"" <<< "$identities" || true)"
      ;;
  esac
  [[ -n "$line" ]] || {
    awiki_macos_signing_error "signing identity is not available in the Keychain: $identity"
    return 1
  }

  fingerprint="$(awk '{print $2}' <<< "$line")"
  [[ "$fingerprint" =~ ^[0-9A-Fa-f]{40}$ ]] || {
    awiki_macos_signing_error "could not resolve the signing identity fingerprint"
    return 1
  }
  printf '%s\n' "$fingerprint"
}

awiki_resolve_developer_id_application_identity() {
  local identity="$1"
  local fingerprint identities line

  fingerprint="$(awiki_resolve_codesigning_identity "$identity")" || return 1
  identities="$(security find-identity -v -p codesigning 2>/dev/null)"
  line="$(grep -i -m 1 " $fingerprint " <<< "$identities" || true)"
  [[ "$line" == *'"Developer ID Application:'* ]] || {
    awiki_macos_signing_error \
      "release identity must be a Developer ID Application certificate: $identity"
    return 1
  }
  printf '%s\n' "$fingerprint"
}

awiki_codesign_with_timestamp_retry() {
  local attempt=1
  local max_attempts=5
  local output

  while true; do
    if output="$(codesign "$@" 2>&1)"; then
      [[ -n "$output" ]] && printf '%s\n' "$output"
      return 0
    fi
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    if [[ "$attempt" -ge "$max_attempts" ]] ||
      ! grep -Eqi \
        'timestamp.*(not available|unavailable|timed out|timeout|connection)' \
        <<< "$output"; then
      return 1
    fi
    printf '[macos-signing] timestamp service unavailable; retrying codesign (%s/%s)\n' \
      "$attempt" "$max_attempts" >&2
    sleep $((attempt * 2))
    attempt=$((attempt + 1))
  done
}

awiki_codesign_distribution_item() {
  local item="$1"
  local fingerprint="$2"
  local entitlements_dir="$3"
  local item_index="$4"
  local entitlements="$entitlements_dir/$item_index.plist"
  local sign_args=(
    --force
    --sign "$fingerprint"
    --options runtime
    --timestamp
    --preserve-metadata=identifier
  )

  if codesign -d --entitlements :- "$item" > "$entitlements" 2>/dev/null &&
    [[ -s "$entitlements" ]]; then
    plutil -lint "$entitlements" >/dev/null || {
      awiki_macos_signing_error "existing entitlements are invalid: $item"
      return 1
    }
    sign_args+=(--entitlements "$entitlements")
  else
    rm -f "$entitlements"
  fi

  awiki_codesign_with_timestamp_retry "${sign_args[@]}" "$item" || {
    awiki_macos_signing_error "could not sign nested distribution code: $item"
    return 1
  }
}

awiki_sign_macos_distribution_app() (
  local app="$1"
  local fingerprint="$2"
  local work_dir macho_list bundle_list item item_index=0

  [[ -d "$app/Contents" ]] || {
    awiki_macos_signing_error "app bundle not found: $app"
    return 1
  }
  [[ "$fingerprint" =~ ^[0-9A-Fa-f]{40}$ ]] || {
    awiki_macos_signing_error "invalid signing identity fingerprint"
    return 1
  }

  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/awiki-macos-signing.XXXXXX")" || {
    awiki_macos_signing_error "could not create the signing workspace"
    return 1
  }
  trap 'rm -rf "$work_dir"' EXIT
  macho_list="$work_dir/macho.list"
  bundle_list="$work_dir/bundle.list"

  # Sign every executable Mach-O first. This includes helper binaries such as
  # Sparkle's Autoupdate that are nested inside a framework but are not bundles.
  find "$app/Contents" -type f -perm -111 -print0 > "$macho_list"
  while IFS= read -r -d '' item; do
    if file -b "$item" | grep -Fq 'Mach-O'; then
      item_index=$((item_index + 1))
      awiki_codesign_distribution_item \
        "$item" "$fingerprint" "$work_dir" "$item_index" || return 1
    fi
  done < "$macho_list"

  # BSD find's -depth order guarantees that XPC services and helper Apps are
  # signed before the frameworks that contain them. The outer App is last.
  find "$app/Contents" -depth -type d \
    \( -name '*.app' -o -name '*.appex' -o -name '*.bundle' -o \
      -name '*.framework' -o -name '*.plugin' -o -name '*.xpc' \) \
    -print0 > "$bundle_list"
  while IFS= read -r -d '' item; do
    item_index=$((item_index + 1))
    awiki_codesign_distribution_item \
      "$item" "$fingerprint" "$work_dir" "$item_index" || return 1
  done < "$bundle_list"

  item_index=$((item_index + 1))
  awiki_codesign_distribution_item \
    "$app" "$fingerprint" "$work_dir" "$item_index"
)

awiki_verify_macos_distribution_item() {
  local item="$1"
  local expected_team="$2"
  local details entitlements

  codesign --verify --strict "$item" || {
    awiki_macos_signing_error "strict code-signature verification failed: $item"
    return 1
  }
  details="$(codesign -dvvv "$item" 2>&1)" || {
    awiki_macos_signing_error "could not inspect code signature: $item"
    return 1
  }
  grep -Fq 'Authority=Developer ID Application:' <<< "$details" || {
    awiki_macos_signing_error "code is not signed with Developer ID Application: $item"
    return 1
  }
  grep -Fqx "TeamIdentifier=$expected_team" <<< "$details" || {
    awiki_macos_signing_error "code signature Team ID does not match $expected_team: $item"
    return 1
  }
  grep -Eq '^CodeDirectory .+flags=0x[0-9A-Fa-f]+\([^)]*runtime' <<< "$details" || {
    awiki_macos_signing_error "code signature does not enable Hardened Runtime: $item"
    return 1
  }
  grep -Eq '^Timestamp=.+' <<< "$details" || {
    awiki_macos_signing_error "code signature does not contain a secure timestamp: $item"
    return 1
  }
  entitlements="$(codesign -d --entitlements :- "$item" 2>/dev/null || true)"
  if grep -Fq 'com.apple.security.get-task-allow' <<< "$entitlements"; then
    awiki_macos_signing_error "distribution code contains get-task-allow: $item"
    return 1
  fi
}

awiki_verify_macos_nested_distribution_code() (
  local app="$1"
  local expected_team="$2"
  local work_dir macho_list bundle_list item

  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/awiki-macos-verification.XXXXXX")" || {
    awiki_macos_signing_error "could not create the verification workspace"
    return 1
  }
  trap 'rm -rf "$work_dir"' EXIT
  macho_list="$work_dir/macho.list"
  bundle_list="$work_dir/bundle.list"

  find "$app/Contents" -type f -perm -111 -print0 > "$macho_list"
  while IFS= read -r -d '' item; do
    if file -b "$item" | grep -Fq 'Mach-O'; then
      awiki_verify_macos_distribution_item \
        "$item" "$expected_team" || return 1
    fi
  done < "$macho_list"

  find "$app/Contents" -depth -type d \
    \( -name '*.app' -o -name '*.appex' -o -name '*.bundle' -o \
      -name '*.framework' -o -name '*.plugin' -o -name '*.xpc' \) \
    -print0 > "$bundle_list"
  while IFS= read -r -d '' item; do
    awiki_verify_macos_distribution_item \
      "$item" "$expected_team" || return 1
  done < "$bundle_list"
)

awiki_verify_macos_app_signature() {
  local app="$1"
  local expected_team="$2"
  local expected_bundle_id="$3"
  local bundle_id details requirement

  [[ -d "$app" ]] || {
    awiki_macos_signing_error "app bundle not found: $app"
    return 1
  }
  [[ "$expected_team" =~ ^[A-Z0-9]{10}$ ]] || {
    awiki_macos_signing_error "invalid expected Team ID: $expected_team"
    return 1
  }
  [[ -n "$expected_bundle_id" ]] || {
    awiki_macos_signing_error "expected bundle ID must not be empty"
    return 1
  }

  codesign --verify --deep --strict "$app" || {
    awiki_macos_signing_error "strict code-signature verification failed: $app"
    return 1
  }
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$app/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$bundle_id" == "$expected_bundle_id" ]] || {
    awiki_macos_signing_error \
      "bundle ID is $bundle_id, expected $expected_bundle_id"
    return 1
  }

  details="$(codesign -dvvv "$app" 2>&1)"
  grep -Fqx "Identifier=$expected_bundle_id" <<< "$details" || {
    awiki_macos_signing_error "signature identifier does not match $expected_bundle_id"
    return 1
  }
  grep -Fqx "TeamIdentifier=$expected_team" <<< "$details" || {
    awiki_macos_signing_error "signature Team ID does not match $expected_team"
    return 1
  }
  if grep -Fq 'Signature=adhoc' <<< "$details"; then
    awiki_macos_signing_error "ad-hoc signatures are not allowed for trial releases"
    return 1
  fi

  requirement="$(codesign -d -r- "$app" 2>&1)"
  if grep -Fq 'cdhash H' <<< "$requirement"; then
    awiki_macos_signing_error "designated requirement is tied to a mutable CDHash"
    return 1
  fi
  grep -Fq "identifier \"$expected_bundle_id\"" <<< "$requirement" || {
    awiki_macos_signing_error "designated requirement does not contain the bundle identifier"
    return 1
  }
}

awiki_verify_macos_distribution_app() {
  local app="$1"
  local expected_team="$2"
  local expected_bundle_id="$3"
  local details entitlements

  awiki_verify_macos_app_signature \
    "$app" "$expected_team" "$expected_bundle_id" || return 1
  awiki_verify_macos_nested_distribution_code \
    "$app" "$expected_team" || return 1
  details="$(codesign -dvvv "$app" 2>&1)"
  grep -Fq 'Authority=Developer ID Application:' <<< "$details" || {
    awiki_macos_signing_error "app is not signed with Developer ID Application"
    return 1
  }
  grep -Eq '^CodeDirectory .+flags=0x[0-9A-Fa-f]+\([^)]*runtime' <<< "$details" || {
    awiki_macos_signing_error "app signature does not enable Hardened Runtime"
    return 1
  }
  grep -Eq '^Timestamp=.+' <<< "$details" || {
    awiki_macos_signing_error "app signature does not contain a secure timestamp"
    return 1
  }
  entitlements="$(codesign -d --entitlements - "$app" 2>&1)" || {
    awiki_macos_signing_error "could not read app entitlements"
    return 1
  }
  if grep -Fq 'com.apple.security.get-task-allow' <<< "$entitlements"; then
    awiki_macos_signing_error "release app contains the get-task-allow entitlement"
    return 1
  fi
}

awiki_verify_macos_distribution_dmg() {
  local dmg="$1"
  local expected_team="$2"
  local details

  [[ -f "$dmg" ]] || {
    awiki_macos_signing_error "DMG not found: $dmg"
    return 1
  }
  codesign --verify --strict "$dmg" || {
    awiki_macos_signing_error "strict DMG signature verification failed: $dmg"
    return 1
  }
  details="$(codesign -dvvv "$dmg" 2>&1)"
  grep -Fq 'Authority=Developer ID Application:' <<< "$details" || {
    awiki_macos_signing_error "DMG is not signed with Developer ID Application"
    return 1
  }
  grep -Fqx "TeamIdentifier=$expected_team" <<< "$details" || {
    awiki_macos_signing_error "DMG signature Team ID does not match $expected_team"
    return 1
  }
  grep -Eq '^Timestamp=.+' <<< "$details" || {
    awiki_macos_signing_error "DMG signature does not contain a secure timestamp"
    return 1
  }
  xcrun stapler validate "$dmg" || {
    awiki_macos_signing_error "DMG does not contain a valid notarization ticket"
    return 1
  }
}

awiki_validate_notary_configuration() {
  local profile="${AWIKI_MACOS_NOTARY_PROFILE:-}"
  local key_path="${AWIKI_MACOS_NOTARY_KEY_PATH:-}"
  local key_id="${AWIKI_MACOS_NOTARY_KEY_ID:-}"
  local issuer_id="${AWIKI_MACOS_NOTARY_ISSUER_ID:-}"
  local timeout="${AWIKI_MACOS_NOTARY_TIMEOUT:-1h}"

  [[ "$timeout" =~ ^[1-9][0-9]*[smh]?$ ]] || {
    awiki_macos_signing_error "invalid AWIKI_MACOS_NOTARY_TIMEOUT: $timeout"
    return 1
  }
  if [[ -n "$profile" ]]; then
    [[ "$profile" =~ ^[A-Za-z0-9._-]+$ ]] || {
      awiki_macos_signing_error "invalid AWIKI_MACOS_NOTARY_PROFILE"
      return 1
    }
    [[ -z "$key_path" && -z "$key_id" && -z "$issuer_id" ]] || {
      awiki_macos_signing_error \
        "keychain-profile and API-key notarization settings cannot be combined"
      return 1
    }
    return 0
  fi

  [[ -f "$key_path" ]] || {
    awiki_macos_signing_error "notarization API key file is missing"
    return 1
  }
  [[ "$key_id" =~ ^[A-Z0-9]{10,}$ ]] || {
    awiki_macos_signing_error "invalid notarization API Key ID"
    return 1
  }
  [[ "$issuer_id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || {
    awiki_macos_signing_error "invalid notarization Issuer ID"
    return 1
  }
  if [[ ! "$(stat -f '%OLp' "$key_path")" =~ ^[0-7]*00$ ]]; then
    awiki_macos_signing_error "notarization API key must not be group/other writable or readable"
    return 1
  fi
}

awiki_notarytool() {
  local command="$1"
  shift
  local auth=()

  awiki_validate_notary_configuration || return 1
  if [[ -n "${AWIKI_MACOS_NOTARY_PROFILE:-}" ]]; then
    auth=(--keychain-profile "$AWIKI_MACOS_NOTARY_PROFILE")
  else
    auth=(
      --key "$AWIKI_MACOS_NOTARY_KEY_PATH"
      --key-id "$AWIKI_MACOS_NOTARY_KEY_ID"
      --issuer "$AWIKI_MACOS_NOTARY_ISSUER_ID"
    )
  fi
  xcrun notarytool "$command" "$@" "${auth[@]}"
}

awiki_notary_json_field() {
  local path="$1"
  local field="$2"

  python3 - "$path" "$field" <<'PY' 2>/dev/null || true
import json, pathlib, sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
print(data.get(sys.argv[2], ""))
PY
}

awiki_notarize_and_staple_dmg() {
  local dmg="$1"
  local diagnostics_dir="$2"
  local submission="$diagnostics_dir/submission.json"
  local result="$diagnostics_dir/result.json"
  local info="$diagnostics_dir/info.json"
  local log="$diagnostics_dir/log.json"
  local submission_id status

  mkdir -p "$diagnostics_dir"
  rm -f "$submission" "$result" "$info" "$log"
  if ! awiki_notarytool submit \
    "$dmg" \
    --no-wait \
    --no-progress \
    --output-format json > "$submission"; then
    [[ -s "$submission" ]] && cat "$submission" >&2
    awiki_macos_signing_error "could not submit the DMG for Apple notarization"
    return 1
  fi
  submission_id="$(awiki_notary_json_field "$submission" id)"
  [[ "$submission_id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || {
    [[ -s "$submission" ]] && cat "$submission" >&2
    awiki_macos_signing_error "Apple notarization did not return a submission ID"
    return 1
  }

  if ! awiki_notarytool wait \
    "$submission_id" \
    --timeout "${AWIKI_MACOS_NOTARY_TIMEOUT:-1h}" \
    --no-progress \
    --output-format json > "$result"; then
    :
  fi
  status="$(awiki_notary_json_field "$result" status)"
  if [[ -z "$status" ]]; then
    if awiki_notarytool info \
      "$submission_id" \
      --output-format json > "$info"; then
      status="$(awiki_notary_json_field "$info" status)"
    fi
  fi
  if [[ "$status" != "Accepted" ]]; then
    [[ -s "$result" ]] && cat "$result" >&2
    [[ -s "$info" ]] && cat "$info" >&2
    awiki_notarytool log "$submission_id" "$log" >/dev/null 2>&1 || true
    [[ -s "$log" ]] && cat "$log" >&2
    if [[ "$status" == "In Progress" ]]; then
      awiki_macos_signing_error \
        "Apple notarization is still in progress after the wait timeout (submission: $submission_id)"
    else
      awiki_macos_signing_error \
        "Apple notarization did not accept the DMG (submission: $submission_id, status: ${status:-unavailable})"
    fi
    return 1
  fi

  xcrun stapler staple "$dmg" || {
    awiki_macos_signing_error "could not staple the notarization ticket to the DMG"
    return 1
  }
  xcrun stapler validate "$dmg" || {
    awiki_macos_signing_error "stapled DMG ticket validation failed"
    return 1
  }
  printf '[macos-signing] notarization accepted: %s\n' "$submission_id"
}

awiki_verify_gatekeeper_app() {
  local app="$1"
  local assessment

  assessment="$(spctl --assess --type execute --verbose=4 "$app" 2>&1)" || {
    printf '%s\n' "$assessment" >&2
    awiki_macos_signing_error "Gatekeeper rejected the notarized app"
    return 1
  }
  if grep -Fq 'override=security disabled' <<< "$assessment"; then
    awiki_macos_signing_error \
      "Gatekeeper assessment is disabled on this build host and cannot attest the app"
    return 1
  fi
  if ! grep -Fq 'source=Notarized Developer ID' <<< "$assessment" &&
    ! grep -Fq 'origin=Developer ID Application:' <<< "$assessment"; then
    printf '%s\n' "$assessment" >&2
    awiki_macos_signing_error \
      "Gatekeeper did not report a notarized Developer ID source"
    return 1
  fi
}
