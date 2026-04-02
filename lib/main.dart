import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/awiki_me_app.dart';
import 'src/app/app_locale.dart';
import 'src/app/bootstrap.dart';
import 'src/presentation/shared/awiki_me_design.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: AwikiMeColors.background,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AwikiMeColors.background,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: AwikiMeColors.background,
    ),
  );
  final bootstrap = await AppBootstrap.create();
  final localeMode = await bootstrap.localePreferenceService.loadMode();
  runApp(
    AwikiMeApp(
      bootstrap: bootstrap,
      providerOverrides: <Override>[
        appLocaleModeProvider.overrideWith((ref) => localeMode),
      ],
    ),
  );
}
