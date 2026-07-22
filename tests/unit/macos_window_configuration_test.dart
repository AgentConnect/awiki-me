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

  test('remote packaging preserves source and macOS signing contracts', () {
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final packageScript = File('scripts/package_app.sh').readAsStringSync();
    final packageConfig = File('scripts/package_app.config').readAsStringSync();
    final packageWorker = File(
      'scripts/package_unix_worker.sh',
    ).readAsStringSync();
    final packageWorkflow = File(
      '.github/workflows/package-app.yml',
    ).readAsStringSync();
    final manifestTool = File('tool/package_manifest.dart').readAsStringSync();
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

    expect(packageScript, contains('gh workflow run'));
    expect(packageScript, contains('require_exact_upstream_push'));
    expect(packageScript, contains("rev-parse --verify 'HEAD^{commit}'"));
    expect(
      packageScript,
      contains('status --porcelain --untracked-files=normal'),
    );
    expect(packageScript, contains('--raw-field "app_ref=\$APP_SOURCE_REF"'));
    expect(
      packageScript,
      contains('--raw-field "core_ref=\$IM_CORE_SOURCE_REF"'),
    );
    expect(packageScript, contains('--raw-field "anp_ref=\$ANP_SOURCE_REF"'));
    expect(packageScript, isNot(contains('flutter build')));
    expect(packageScript, isNot(contains('write_pubspec_version')));
    expect(
      packageConfig,
      contains(
        'PACKAGE_TARGETS="android-arm64,macos-arm64,macos-x64,windows-x64"',
      ),
    );
    expect(packageConfig, contains('windows-x64'));
    expect(packageConfig, contains('PACKAGE_VERSION_BUMP="none"'));

    expect(packageWorker, contains('AWIKI_MACOS_SIGNING_IDENTITY'));
    expect(packageWorker, contains('AWIKI_MACOS_DEVELOPMENT_TEAM'));
    expect(packageWorker, contains('CODE_SIGN_IDENTITY="\$fingerprint"'));
    expect(packageWorker, contains('awiki_verify_macos_app_signature'));
    expect(packageWorker, contains('xcodebuild'));
    expect(packageWorker, contains('AWIKI_APP_SOURCE_REF="\$APP_REF"'));
    expect(packageWorker, contains('AWIKI_IM_CORE_SOURCE_REF="\$CORE_REF"'));
    expect(
      packageWorker,
      contains(
        'F2:67:E9:18:57:54:ED:C1:2B:E5:69:69:1B:39:B9:EF:'
        'D4:EF:1E:CF:2D:7E:D8:18:81:42:69:B3:70:85:D8:75',
      ),
    );
    expect(packageWorker, contains('verify_android_startup_smoke'));
    expect(packageWorker, contains('GeneratedPluginRegistrant'));
    expect(packageWorker, contains('application-debuggable'));
    expect(
      packageWorker,
      contains('AWIKI_PRIMARY_TENANT_DOMAIN="\$PRIMARY_TENANT_DOMAIN"'),
    );

    expect(packageWorkflow, contains('FLUTTER_VERSION: 3.44.0'));
    expect(packageWorkflow, contains('RUST_VERSION: 1.88.0'));
    expect(packageWorkflow, contains('"runner": "windows-2022"'));
    expect(packageWorkflow, contains('environment: app-packaging'));
    expect(packageWorkflow, contains('AWIKI_ANDROID_STARTUP_SMOKE_TEST'));
    expect(packageWorkflow, contains('innosetup --version=6.3.2'));
    expect(packageWorkflow, contains('--allow-downgrade'));
    expect(
      packageWorkflow,
      contains(r'--android-startup-smoke-test "$ANDROID_STARTUP_SMOKE_TEST"'),
    );
    expect(packageWorkflow, contains('ref: \${{ inputs.app_ref }}'));
    expect(packageWorkflow, contains('ref: \${{ inputs.core_ref }}'));
    expect(packageWorkflow, contains('ref: \${{ inputs.anp_ref }}'));
    expect(
      packageWorkflow,
      contains('DOWNLOAD_BASE_URL: \${{ inputs.download_base_url }}'),
    );
    expect(
      packageWorkflow,
      contains(r'--download-base-url "$DOWNLOAD_BASE_URL"'),
    );
    expect(
      packageWorkflow,
      isNot(contains('--download-base-url "\${{ inputs.download_base_url }}"')),
    );
    expect(
      packageWorkflow,
      isNot(contains('--download-page-url "\${{ inputs.download_page_url }}"')),
    );
    expect(packageWorkflow, isNot(contains('gh release')));

    expect(manifestTool, contains("'app': app"));
    expect(manifestTool, contains("'imCore': imCore"));
    expect(manifestTool, contains("'anp': anp"));
    expect(manifestTool, contains("'signingState'"));
    expect(signingLibrary, contains('codesign --verify --deep --strict'));
    expect(signingLibrary, contains('TeamIdentifier=\$expected_team'));
    expect(signingLibrary, contains('Signature=adhoc'));
    expect(signingLibrary, contains('cdhash H'));
    expect(signingLibrary, contains('<<< "\$details"'));
    expect(signingLibrary, contains('<<< "\$requirement"'));
    expect(signingLibrary, isNot(contains('"\$details" | grep')));
    expect(signingLibrary, isNot(contains('"\$requirement" | grep')));
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
