import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:yaml/yaml.dart';

const _canonicalLogoPath = 'assets/branding/awiki-me-logo.png';

void main() {
  test('native splash and launcher configs use the canonical logo', () {
    final splash =
        loadYaml(File('flutter_native_splash.yaml').readAsStringSync())
            as YamlMap;
    final splashConfig = splash['flutter_native_splash'] as YamlMap;
    expect(splashConfig['image'], _canonicalLogoPath);
    expect((splashConfig['android_12'] as YamlMap)['color'], '#FAF9FE');
    expect(splashConfig['android'], isTrue);
    expect(splashConfig['ios'], isTrue);
    expect(splashConfig['web'], isFalse);

    final launcher =
        loadYaml(File('flutter_launcher_icons.yaml').readAsStringSync())
            as YamlMap;
    final launcherConfig = launcher['flutter_launcher_icons'] as YamlMap;
    expect(launcherConfig['image_path'], _canonicalLogoPath);
    expect(launcherConfig['adaptive_icon_foreground'], _canonicalLogoPath);
    expect(
      (launcherConfig['web'] as YamlMap)['image_path'],
      _canonicalLogoPath,
    );
  });

  test('generated iOS and Android splash images match the canonical logo', () {
    final source = image.decodePng(File(_canonicalLogoPath).readAsBytesSync());
    expect(source, isNotNull);

    const generatedImages = <String, int>{
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png': 256,
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png': 512,
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png': 768,
      'android/app/src/main/res/drawable-mdpi/splash.png': 256,
      'android/app/src/main/res/drawable-hdpi/splash.png': 384,
      'android/app/src/main/res/drawable-xhdpi/splash.png': 512,
      'android/app/src/main/res/drawable-xxhdpi/splash.png': 768,
      'android/app/src/main/res/drawable-xxxhdpi/splash.png': 1024,
    };

    for (final entry in generatedImages.entries) {
      final expected = image.copyResize(
        source!,
        width: entry.value,
        height: entry.value,
        interpolation: image.Interpolation.average,
      );
      final actual = image.decodePng(File(entry.key).readAsBytesSync());
      expect(actual, isNotNull, reason: '${entry.key} must be a valid PNG');
      expect(actual!.width, entry.value, reason: entry.key);
      expect(actual.height, entry.value, reason: entry.key);
      expect(
        sha256.convert(image.encodePng(actual)),
        sha256.convert(image.encodePng(expected)),
        reason:
            '${entry.key} is stale; run '
            '`dart run flutter_native_splash:create`',
      );
    }
  });

  test('native splash backgrounds use the configured color', () {
    const backgrounds = <String>[
      'ios/Runner/Assets.xcassets/LaunchBackground.imageset/background.png',
      'android/app/src/main/res/drawable/background.png',
      'android/app/src/main/res/drawable-v21/background.png',
    ];

    for (final path in backgrounds) {
      final background = image.decodePng(File(path).readAsBytesSync());
      expect(background, isNotNull, reason: '$path must be a valid PNG');
      final pixel = background!.getPixel(0, 0);
      expect(pixel.r.toInt(), 0xFA, reason: path);
      expect(pixel.g.toInt(), 0xF9, reason: path);
      expect(pixel.b.toInt(), 0xFE, reason: path);
      expect(pixel.a.toInt(), 0xFF, reason: path);
    }

    const android12Styles = <String>[
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ];
    for (final path in android12Styles) {
      expect(
        File(path).readAsStringSync(),
        contains(
          '<item name="android:windowSplashScreenBackground">'
          '#FAF9FE</item>',
        ),
        reason: '$path must match the generated Android 12 splash config',
      );
    }
  });

  test('Android launcher has no legacy vector fallback', () {
    expect(
      File(
        'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
      ).existsSync(),
      isFalse,
    );
  });
}
