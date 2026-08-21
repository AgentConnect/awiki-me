// [INPUT]: Repository root, normalized desktop platform, and user config home.
// [OUTPUT]: An isolated Flutter build/config root plus bounded Linux compatibility link.
// [POS]: Build-filesystem policy; does not select scenarios or execute Flutter.

import 'dart:convert';
import 'dart:io';

import 'failure.dart';
import 'platform.dart';

/// Keeps Flutter integration-test products away from the normal `build/`
/// directory so a test host can never replace the developer-launchable App.
class DesktopFlutterBuildIsolation {
  DesktopFlutterBuildIsolation({
    required this.root,
    required this.platform,
    String? userHome,
  }) : userHome = userHome ?? Platform.environment['HOME'];

  final Directory root;
  final DesktopE2ePlatform platform;
  final String? userHome;

  String get buildDirectory => '.e2e/flutter-build/${platform.name}';

  Directory get configDirectory =>
      Directory('${root.path}/.e2e/flutter-config/${platform.name}');

  File get settingsFile => File('${configDirectory.path}/settings');

  Map<String, String> get environment => <String, String>{
    'XDG_CONFIG_HOME': configDirectory.path,
  };

  Link? prepareLinuxNativeAssetsCompatibility({required bool dryRun}) {
    if (dryRun || platform != DesktopE2ePlatform.linux) {
      return null;
    }
    final target = Directory('${root.path}/$buildDirectory/linux')
      ..createSync(recursive: true);
    final link = Link('${root.path}/build/linux');
    final type = FileSystemEntity.typeSync(link.path, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      if (type != FileSystemEntityType.link ||
          link.targetSync() != target.absolute.path) {
        throw E2eFailure(
          'Flutter E2E native-assets compatibility refuses to replace '
          '${link.path}.',
        );
      }
      return link;
    }
    link.parent.createSync(recursive: true);
    link.createSync(target.absolute.path);
    return link;
  }

  void removeLinuxNativeAssetsCompatibility(Link? link) {
    if (link == null ||
        FileSystemEntity.typeSync(link.path, followLinks: false) !=
            FileSystemEntityType.link) {
      return;
    }
    final expected = Directory(
      '${root.path}/$buildDirectory/linux',
    ).absolute.path;
    if (link.targetSync() == expected) {
      link.deleteSync();
    }
  }

  void prepare({required bool dryRun}) {
    if (dryRun) {
      return;
    }
    final home = userHome?.trim();
    if (home != null && home.isNotEmpty) {
      final legacySettings = File('$home/.flutter_settings');
      if (legacySettings.existsSync()) {
        throw E2eFailure(
          'Flutter E2E build isolation cannot override the legacy '
          '${legacySettings.path} config. Move it to the XDG Flutter config '
          'location before running E2E so the normal build/ App remains safe.',
        );
      }
    }

    final settings = <String, Object?>{};
    if (settingsFile.existsSync()) {
      try {
        final decoded = jsonDecode(settingsFile.readAsStringSync());
        if (decoded is! Map) {
          throw const FormatException('Flutter settings must be an object.');
        }
        settings.addAll(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      } on Object catch (error) {
        throw E2eFailure(
          'Could not load isolated Flutter E2E settings: '
          '${error.runtimeType}.',
        );
      }
    }
    settings['build-dir'] = buildDirectory;
    switch (platform) {
      case DesktopE2ePlatform.macos:
        settings['enable-macos-desktop'] = true;
        break;
      case DesktopE2ePlatform.linux:
        settings['enable-linux-desktop'] = true;
        break;
    }

    configDirectory.createSync(recursive: true);
    final temporary = File('${settingsFile.path}.tmp');
    temporary.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(settings),
      flush: true,
    );
    temporary.renameSync(settingsFile.path);
  }
}
