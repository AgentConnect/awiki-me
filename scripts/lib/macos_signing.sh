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
