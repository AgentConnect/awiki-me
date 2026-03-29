import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../presentation/shared/awiki_me_design.dart';
import '../presentation/app_shell/app_shell.dart';
import 'bootstrap.dart';

class AwikiMeApp extends StatelessWidget {
  const AwikiMeApp({super.key, required this.bootstrap});

  final AppBootstrap bootstrap;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AwikiMeColors.background,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AwikiMeColors.background,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: AwikiMeColors.background,
      ),
      child: CupertinoApp(
        title: 'AWiki Me',
        debugShowCheckedModeBanner: false,
        theme: const CupertinoThemeData(
          brightness: Brightness.light,
          primaryColor: AwikiMeColors.primary,
          scaffoldBackgroundColor: AwikiMeColors.background,
          textTheme: CupertinoTextThemeData(
            primaryColor: AwikiMeColors.primary,
            textStyle: TextStyle(
              color: AwikiMeColors.body,
              fontSize: 15,
            ),
          ),
        ),
        home: AppShell(bootstrap: bootstrap),
      ),
    );
  }
}
