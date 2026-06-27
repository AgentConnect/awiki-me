import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/awiki_me_app.dart';
import 'src/app/app_locale.dart';
import 'src/app/bootstrap.dart';
import 'src/core/performance_logger.dart';
import 'src/presentation/shared/awiki_me_design.dart';

Future<void> main() async {
  final startupWatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  AwikiPerformanceLogger.registerFrameTimings();
  AwikiPerformanceLogger.log(
    'main.start',
    level: AwikiPerformanceLogLevel.verbose,
  );
  await AwikiPerformanceLogger.async(
    'main.system_ui',
    () => SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
    level: AwikiPerformanceLogLevel.verbose,
  );
  AwikiPerformanceLogger.sync(
    'main.system_ui_overlay',
    () => SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: AwikiMeColors.background,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AwikiMeColors.background,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: AwikiMeColors.background,
      ),
    ),
    level: AwikiPerformanceLogLevel.verbose,
  );
  final bootstrap = await AwikiPerformanceLogger.async(
    'main.bootstrap_create',
    AppBootstrap.create,
  );
  final localeMode = await AwikiPerformanceLogger.async(
    'main.load_locale',
    bootstrap.localePreferenceService.loadMode,
    level: AwikiPerformanceLogLevel.verbose,
  );
  runApp(
    AwikiMeApp(
      bootstrap: bootstrap,
      providerOverrides: <Override>[
        appLocaleModeProvider.overrideWith((ref) => localeMode),
      ],
    ),
  );
  AwikiPerformanceLogger.log('main.run_app', elapsed: startupWatch.elapsed);
  if (AwikiPerformanceLogger.enabled) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      startupWatch.stop();
      AwikiPerformanceLogger.log(
        'main.first_frame',
        elapsed: startupWatch.elapsed,
      );
    });
  }
}
