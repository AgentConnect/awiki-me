import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('macOS DMG tool supply and Finder layout are pinned', () {
    final workflow =
        loadYaml(File('.github/workflows/package-app.yml').readAsStringSync())
            as YamlMap;
    final environment = workflow['env'] as YamlMap;
    expect(environment['PYTHON_VERSION'].toString(), '3.13.7');
    expect(environment['DMGBUILD_VERSION'].toString(), '1.6.7');

    final jobs = workflow['jobs'] as YamlMap;
    final build = jobs['build'] as YamlMap;
    final pythonSetup = _stepNamed(
      build['steps'] as YamlList,
      'Setup Python 3.13.7 for dmgbuild',
    );
    expect(pythonSetup['if'], "startsWith(matrix.target, 'macos-')");
    expect(pythonSetup['uses'], 'actions/setup-python@v6');
    expect(
      (pythonSetup['with'] as YamlMap)['python-version'],
      r'${{ env.PYTHON_VERSION }}',
    );
    final install = _stepNamed(
      build['steps'] as YamlList,
      'Install pinned dmgbuild',
    );
    expect(install['if'], "startsWith(matrix.target, 'macos-')");
    final installScript = install['run'].toString();
    for (final expected in <String>[
      'python3 -m venv',
      '--index-url https://pypi.org/simple',
      '--only-binary=:all:',
      '--require-hashes',
      '--requirement awiki-me/scripts/requirements-macos-dmg.txt',
      'from importlib.metadata import version',
      'DMGBUILD_PYTHON=',
      r'$GITHUB_ENV',
    ]) {
      expect(installScript, contains(expected), reason: expected);
    }
    expect(installScript, isNot(contains('brew install')));
    expect(installScript, isNot(contains('create-dmg')));

    final requirements = File(
      'scripts/requirements-macos-dmg.txt',
    ).readAsStringSync();
    for (final expected in <String>[
      'dmgbuild==1.6.7',
      'sha256:37ee5771c377beb3203d9164aae8046ffed8531c06edf9227f5788b3c599b1bf',
      'ds-store==1.3.3',
      'sha256:b92a371efbf1b4ccce2a04d1ed13fceacc4736c81ba09cf5aefb74c088160a35',
      'mac-alias==2.2.3',
      'sha256:7362b521d2132ef92f606a37abfed5fcd849ceb2f28b6f9743e014b02af92f0d',
    ]) {
      expect(requirements, contains(expected), reason: expected);
    }

    final worker = File('scripts/package_unix_worker.sh').readAsStringSync();
    expect(worker, contains('DMGBUILD_VERSION="1.6.7"'));
    expect(worker, contains(r'${DMGBUILD_PYTHON:-python3}'));
    expect(worker, contains('from importlib.metadata import version'));
    expect(worker, isNot(contains('create-dmg')));
    for (final expected in <String>[
      r'"$dmgbuild_python" -m dmgbuild',
      r'--settings "$MACOS_DMG_SETTINGS"',
      '--no-hidpi',
      '--detach-retries 5',
      r'-D "application=$app"',
      r'-D "background=$MACOS_DMG_BACKGROUND"',
      r'"AWikiMe $VERSION $arch_label"',
      r'"$staged_dmg"',
    ]) {
      expect(worker, contains(expected), reason: expected);
    }

    final settings = File('installer/macos/dmg_settings.py').readAsStringSync();
    for (final expected in <String>[
      'files = [(application_path, "AWikiMe.app")]',
      'symlinks = {"Applications": "/Applications"}',
      'format = "UDZO"',
      'filesystem = "APFS"',
      'window_rect = ((200, 120), (600, 380))',
      'default_view = "icon-view"',
      'text_size = 13',
      'icon_size = 112',
      '"AWikiMe.app": (155, 185)',
      '"Applications": (445, 185)',
    ]) {
      expect(settings, contains(expected), reason: expected);
    }

    final verifyIndex = worker.indexOf(
      r'verify_macos_dmg "$staged_dmg" "$arch"',
    );
    final publishIndex = worker.indexOf(
      r'mv "$staged_dmg" "$OUTPUT_DIR/$filename"',
      verifyIndex,
    );
    final metadataIndex = worker.indexOf(r'metadata "$filename"', verifyIndex);
    expect(verifyIndex, isNonNegative);
    expect(publishIndex, greaterThan(verifyIndex));
    expect(metadataIndex, greaterThan(publishIndex));
  });

  test('macOS DMG verification checks the final mounted layout', () {
    final worker = File('scripts/package_unix_worker.sh').readAsStringSync();
    for (final expected in <String>[
      r'hdiutil verify "$dmg"',
      r'''hdiutil attach \
      -readonly \
      -nobrowse \
      -noautoopen''',
      'trap cleanup_macos_dmg_mount_on_exit EXIT',
      r'"$mount_point/AWikiMe.app"',
      r'"$mount_point/Applications"',
      r'readlink "$mount_point/Applications"',
      r'"$mount_point/.DS_Store"',
      r'"$mount_point/.background.png"',
      'cmp -s',
      r'hdiutil detach "$mount_point"',
      r'hdiutil detach -force "$mount_point"',
      'failed to detach macOS DMG verification mount',
      'codesign --verify --deep --strict',
    ]) {
      expect(worker, contains(expected), reason: expected);
    }
    expect(
      worker,
      isNot(
        contains(
          r'hdiutil detach -force "$mount_point" >/dev/null 2>&1 || true',
        ),
      ),
    );
  });

  test('macOS release artifacts require Developer ID and notarization', () {
    final workflow =
        loadYaml(File('.github/workflows/package-app.yml').readAsStringSync())
            as YamlMap;
    final build = (workflow['jobs'] as YamlMap)['build'] as YamlMap;
    final steps = build['steps'] as YamlList;
    final prepare = _stepNamed(
      steps,
      'Prepare macOS Developer ID and notarization credentials',
    );
    expect(prepare['if'], "startsWith(matrix.target, 'macos-')");
    final prepareEnvironment = prepare['env'] as YamlMap;
    expect(
      prepareEnvironment['NOTARY_KEY_BASE64'],
      r'${{ secrets.AWIKI_MACOS_NOTARY_KEY_BASE64 }}',
    );
    expect(
      prepareEnvironment['NOTARY_KEY_ID'],
      r'${{ secrets.AWIKI_MACOS_NOTARY_KEY_ID }}',
    );
    expect(
      prepareEnvironment['NOTARY_ISSUER_ID'],
      r'${{ secrets.AWIKI_MACOS_NOTARY_ISSUER_ID }}',
    );
    final prepareScript = prepare['run'].toString();
    for (final expected in <String>[
      r'chmod 600 "$p12" "$notary_key"',
      r'openssl pkey -in "$notary_key" -noout -check',
      'security create-keychain',
      'security set-key-partition-list',
      'xcrun notarytool history',
      r'--key "$notary_key"',
      r'--key-id "$NOTARY_KEY_ID"',
      r'--issuer "$NOTARY_ISSUER_ID"',
      'AWIKI_MACOS_NOTARY_KEY_PATH=',
      'AWIKI_MACOS_NOTARY_KEY_ID=',
      'AWIKI_MACOS_NOTARY_ISSUER_ID=',
    ]) {
      expect(prepareScript, contains(expected), reason: expected);
    }

    final cleanup = _stepNamed(steps, 'Remove macOS release credentials');
    expect(cleanup['if'], "always() && startsWith(matrix.target, 'macos-')");
    final cleanupScript = cleanup['run'].toString();
    expect(cleanupScript, contains('security delete-keychain'));
    expect(cleanupScript, contains('AWIKI_MACOS_CI_P12'));
    expect(cleanupScript, contains('AWIKI_MACOS_NOTARY_KEY_PATH'));
    final diagnostics = _stepNamed(
      steps,
      'Upload macOS notarization diagnostics on failure',
    );
    expect(
      diagnostics['if'],
      "failure() && startsWith(matrix.target, 'macos-')",
    );
    expect(
      steps.cast<YamlMap>().indexOf(cleanup),
      lessThan(steps.cast<YamlMap>().indexOf(diagnostics)),
      reason: 'credentials must be removed before an artifact action runs',
    );

    final worker = File('scripts/package_unix_worker.sh').readAsStringSync();
    for (final expected in <String>[
      'awiki_resolve_developer_id_application_identity',
      'awiki_sign_macos_distribution_app',
      'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO',
      'ENABLE_HARDENED_RUNTIME=YES',
      r'OTHER_CODE_SIGN_FLAGS="--timestamp"',
      'awiki_verify_macos_distribution_app',
      'awiki_notarize_and_staple_dmg',
      'awiki_verify_macos_distribution_dmg',
      'awiki_verify_gatekeeper_app',
    ]) {
      expect(worker, contains(expected), reason: expected);
    }
    _expectBefore(
      worker,
      r'codesign --force \',
      'awiki_notarize_and_staple_dmg',
    );
    _expectBefore(
      worker,
      'awiki_notarize_and_staple_dmg',
      r'verify_macos_dmg "$staged_dmg" "$arch"',
    );
    _expectBefore(
      worker,
      r'verify_macos_dmg "$staged_dmg" "$arch"',
      r'mv "$staged_dmg" "$OUTPUT_DIR/$filename"',
    );

    final signing = File('scripts/lib/macos_signing.sh').readAsStringSync();
    for (final expected in <String>[
      'Developer ID Application:',
      'awiki_codesign_distribution_item',
      'awiki_verify_macos_nested_distribution_code',
      "find \"\$app/Contents\" -type f -perm -111 -print0",
      "find \"\$app/Contents\" -depth -type d",
      "-name '*.framework'",
      "-name '*.xpc'",
      '--preserve-metadata=identifier',
      '--options runtime',
      'flags=0x[0-9A-Fa-f]+',
      'com.apple.security.get-task-allow',
      r"grep -Eq '^Timestamp=.+'",
      'xcrun notarytool',
      'awiki_notarytool submit',
      '--no-wait',
      'awiki_notarytool wait',
      'awiki_notarytool info',
      '--timeout',
      r'AWIKI_MACOS_NOTARY_TIMEOUT:-1h',
      'still in progress after the wait timeout',
      'xcrun stapler staple',
      'xcrun stapler validate',
      'spctl --assess --type execute',
      'override=security disabled',
    ]) {
      expect(signing, contains(expected), reason: expected);
    }
    final buildMacosStart = worker.indexOf('build_macos() {');
    final buildMacos = worker.substring(buildMacosStart);
    _expectBefore(
      buildMacos,
      'awiki_sign_macos_distribution_app',
      'awiki_verify_macos_distribution_app',
    );
    _expectBefore(
      signing,
      'awiki_verify_macos_nested_distribution_code',
      r'details="$(codesign -dvvv "$app" 2>&1)"',
    );
    _expectBefore(
      signing,
      'awiki_notarytool submit',
      'awiki_notarytool wait',
    );
    _expectBefore(
      signing,
      'awiki_notarytool wait',
      'xcrun stapler staple',
    );

    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final releaseStart = project.indexOf(
      '33CC10FD2044A3C60003C045 /* Release */ = {',
    );
    final releaseEnd = project.indexOf('\n\t\t};', releaseStart);
    final releaseTarget = project.substring(releaseStart, releaseEnd);
    expect(releaseTarget, contains('ENABLE_HARDENED_RUNTIME = YES;'));
    expect(releaseTarget, contains('CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;'));
    final entitlements = File(
      'macos/Runner/Release.entitlements',
    ).readAsStringSync();
    expect(entitlements, isNot(contains('get-task-allow')));
  });
}

YamlMap _stepNamed(YamlList steps, String name) {
  return steps.cast<YamlMap>().singleWhere((step) => step['name'] == name);
}

void _expectBefore(String source, String first, String second) {
  final firstIndex = source.indexOf(first);
  final secondIndex = source.indexOf(second);
  expect(firstIndex, isNonNegative, reason: '$first must be configured');
  expect(secondIndex, isNonNegative, reason: '$second must be configured');
  expect(firstIndex, lessThan(secondIndex));
}
