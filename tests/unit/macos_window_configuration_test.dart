import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS product and bundle are named AWikiMe', () {
    final appInfo = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final scheme = File(
      'macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
    ).readAsStringSync();

    expect(appInfo, contains('PRODUCT_NAME = AWikiMe'));
    expect(appInfo, contains('PRODUCT_BUNDLE_IDENTIFIER = ai.awiki.awikime'));
    expect(project, contains('AWIKI_APP_DISPLAY_NAME = AWikiMe;'));
    expect(project, contains('/AWikiMe.app/'));
    expect(project, contains('/AWikiMe";'));
    expect(scheme, contains('BuildableName = "AWikiMe.app"'));
    expect(scheme, isNot(contains('BuildableName = "AWiki Me.app"')));
    expect('BlueprintName = "awiki-me"'.allMatches(scheme), hasLength(4));
    expect(scheme, isNot(contains('BlueprintName = "Runner"')));
  });

  test('macOS main window defaults to the larger chat workspace', () {
    final source = File(
      'macos/Runner/Base.lproj/MainMenu.xib',
    ).readAsStringSync();

    expect(
      source,
      contains(
        '<rect key="contentRect" x="335" y="390" width="1180" height="760"/>',
      ),
    );
    expect(
      source,
      contains('<rect key="frame" x="0.0" y="0.0" width="1180" height="760"/>'),
    );
  });

  test('menu bar controller retains the main window for reopen', () {
    final source = File(
      'macos/Runner/MenuBarStatusController.swift',
    ).readAsStringSync();

    expect(source, contains('private var mainWindow: NSWindow?'));
    expect(source, isNot(contains('private weak var mainWindow: NSWindow?')));
    expect(source, contains('window.makeKeyAndOrderFront(nil)'));
  });

  test('Debug App defaults to portable ad-hoc signing with local override', () {
    final source = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final debugConfig = File(
      'macos/Runner/Configs/Debug.xcconfig',
    ).readAsStringSync();
    final localSigningExample = File(
      'macos/Runner/Configs/LocalSigning.xcconfig.example',
    ).readAsStringSync();
    final gitignore = File('.gitignore').readAsStringSync();
    final start = source.indexOf('33CC10FC2044A3C60003C045 /* Debug */ = {');
    final end = source.indexOf('\n\t\t};', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final debugTarget = source.substring(start, end);
    expect(
      debugTarget,
      contains('CODE_SIGN_IDENTITY = "\$(AWIKI_MACOS_CODE_SIGN_IDENTITY)";'),
    );
    expect(
      debugTarget,
      contains('DEVELOPMENT_TEAM = "\$(AWIKI_MACOS_DEVELOPMENT_TEAM)";'),
    );
    expect(
      debugTarget,
      contains('PRODUCT_BUNDLE_IDENTIFIER = "\$(AWIKI_MACOS_DEV_BUNDLE_ID)";'),
    );
    expect(
      debugTarget,
      contains('AWIKI_APP_DISPLAY_NAME = "AWikiMe (Development)";'),
    );
    expect(debugTarget, isNot(contains('DEVELOPMENT_TEAM = DT9HA3J8KE;')));
    expect(debugConfig, contains('AWIKI_MACOS_CODE_SIGN_IDENTITY = -'));
    expect(debugConfig, contains('AWIKI_MACOS_CODE_SIGN_STYLE = Manual'));
    expect(debugConfig, contains('AWIKI_MACOS_DEVELOPMENT_TEAM ='));
    expect(debugConfig, contains('#include? "LocalSigning.xcconfig"'));
    expect(
      localSigningExample,
      contains('AWIKI_MACOS_CODE_SIGN_IDENTITY = Apple Development'),
    );
    expect(
      localSigningExample,
      contains('AWIKI_MACOS_DEVELOPMENT_TEAM = REPLACE_WITH_TEAM_ID'),
    );
    expect(gitignore, contains('macos/Runner/Configs/LocalSigning.xcconfig'));
    expect(gitignore, contains('*.p12'));
    expect(gitignore, contains('*.pfx'));

    final infoPlist = File('macos/Runner/Info.plist').readAsStringSync();
    expect(infoPlist, contains('<key>CFBundleDisplayName</key>'));
    expect(
      '<string>\$(AWIKI_APP_DISPLAY_NAME)</string>'.allMatches(infoPlist),
      hasLength(2),
    );
    for (final locale in <String>['en', 'zh-Hans']) {
      final localizedInfo = File(
        'macos/Runner/$locale.lproj/InfoPlist.strings',
      ).readAsStringSync();
      expect(localizedInfo, isNot(contains('"CFBundleName"')));
    }
  });

  test('macOS trial packaging requires and verifies a stable signer', () {
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final packageScript = File('scripts/package_app.sh').readAsStringSync();
    final packageConfig = File('scripts/package_app.config').readAsStringSync();
    final localConfigExample = File(
      'scripts/package_app.local.config.example',
    ).readAsStringSync();
    final signingLibrary = File(
      'scripts/lib/macos_signing.sh',
    ).readAsStringSync();
    final nativeWindow = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    final profileStart = project.indexOf(
      '338D0CEA231458BD00FA5F75 /* Profile */ = {',
    );
    final profileEnd = project.indexOf('\n\t\t};', profileStart);
    final profileTarget = project.substring(profileStart, profileEnd);
    expect(profileTarget, contains('CODE_SIGN_IDENTITY = "-";'));
    expect(profileTarget, contains('CODE_SIGN_STYLE = Manual;'));
    expect(
      profileTarget,
      contains('PRODUCT_BUNDLE_IDENTIFIER = ai.awiki.awikime.dev;'),
    );

    final releaseStart = project.indexOf(
      '33CC10FD2044A3C60003C045 /* Release */ = {',
    );
    final releaseEnd = project.indexOf('\n\t\t};', releaseStart);
    final releaseTarget = project.substring(releaseStart, releaseEnd);
    expect(releaseTarget, contains('CODE_SIGN_IDENTITY = "-";'));
    expect(releaseTarget, contains('CODE_SIGN_STYLE = Manual;'));
    expect(
      releaseTarget,
      contains('PRODUCT_BUNDLE_IDENTIFIER = ai.awiki.awikime;'),
    );

    expect(packageScript, contains('PACKAGE_APP_DISPLAY_NAME="AWikiMe"'));
    expect(packageScript, contains('PACKAGE_MACOS_BUILD_MODE="release"'));
    expect(packageScript, contains('XCODE_CONFIGURATION="Release"'));
    expect(packageScript, contains('package_app.local.config'));
    expect(
      packageScript,
      contains('CODE_SIGN_IDENTITY="\$AWIKI_MACOS_SIGNING_FINGERPRINT"'),
    );
    expect(packageScript, contains('awiki_verify_macos_app_signature'));
    expect(packageScript, contains("rev-parse --verify 'HEAD^{commit}'"));
    expect(
      packageScript,
      contains('status --porcelain --untracked-files=normal'),
    );
    expect(packageScript, contains('HEAD changed during packaging'));
    expect(
      packageScript,
      contains(
        'require_source_tree_matches_ref "AWiki Me" "\$ROOT_DIR" "\$APP_SOURCE_REF"',
      ),
    );
    expect(
      packageScript,
      contains(
        'require_source_tree_matches_ref "im-core" "\$SDK_REPO_DIR" "\$IM_CORE_SOURCE_REF"',
      ),
    );
    expect(packageScript, contains('AWIKI_APP_SOURCE_REF="\$APP_SOURCE_REF"'));
    expect(
      packageScript,
      contains('AWIKI_IM_CORE_SOURCE_REF="\$IM_CORE_SOURCE_REF"'),
    );
    expect(
      packageScript,
      contains(
        'AWIKI_PRIMARY_TENANT_DOMAIN="\$PACKAGE_PRIMARY_TENANT_DOMAIN"',
      ),
    );
    expect(packageScript, contains('"sourceRefs": {'));
    expect(
      packageScript,
      contains('"app": \$(json_string "\$APP_SOURCE_REF")'),
    );
    expect(
      packageScript,
      contains('"imCore": \$(json_string "\$IM_CORE_SOURCE_REF")'),
    );
    expect(
      packageScript,
      contains(
        '"primaryDomain": \$(json_string "\$PACKAGE_PRIMARY_TENANT_DOMAIN")',
      ),
    );
    expect(packageConfig, contains('PACKAGE_VERSION_BUMP="none"'));
    expect(
      packageConfig,
      contains(
        'AWIKI_MACOS_SIGNING_IDENTITY="\${AWIKI_MACOS_SIGNING_IDENTITY:-}"',
      ),
    );
    expect(
      localConfigExample,
      contains('AWIKI_MACOS_DEVELOPMENT_TEAM="REPLACE_ME"'),
    );
    expect(signingLibrary, contains('codesign --verify --deep --strict'));
    expect(signingLibrary, contains('TeamIdentifier=\$expected_team'));
    expect(signingLibrary, contains('Signature=adhoc'));
    expect(signingLibrary, contains('cdhash H'));
    expect(
      nativeWindow,
      contains('bundleIdentifier.hasPrefix("ai.awiki.awikime.dev.")'),
    );
    expect(nativeWindow, contains('case .production:'));
    expect(nativeWindow, contains('case .development:'));

    final infoPlist = File('macos/Runner/Info.plist').readAsStringSync();
    expect(infoPlist, contains('<key>AWikiAppSourceRef</key>'));
    expect(infoPlist, contains('<string>\$(AWIKI_APP_SOURCE_REF)</string>'));
    expect(infoPlist, contains('<key>AWikiImCoreSourceRef</key>'));
    expect(
      infoPlist,
      contains('<string>\$(AWIKI_IM_CORE_SOURCE_REF)</string>'),
    );
    expect(infoPlist, contains('<key>AWikiPrimaryTenantDomain</key>'));
    expect(
      infoPlist,
      contains('<string>\$(AWIKI_PRIMARY_TENANT_DOMAIN)</string>'),
    );
  });
}
