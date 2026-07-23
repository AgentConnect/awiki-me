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
}

YamlMap _stepNamed(YamlList steps, String name) {
  return steps.cast<YamlMap>().singleWhere((step) => step['name'] == name);
}
