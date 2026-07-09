import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/core/performance_logger.dart';
import 'src/presentation/shared/awiki_me_design.dart';
import 'src/app/tenant_aware_awiki_me_app.dart';

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
  runApp(const TenantAwareAwikiMeApp());
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
