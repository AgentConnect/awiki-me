import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:awiki_me/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart' as material;

import '../presentation/app_shell/app_shell.dart';
import '../presentation/shared/awiki_me_design.dart';
import 'app_locale.dart';
import 'app_services.dart';
import 'bootstrap.dart';

class AwikiMeApp extends StatelessWidget {
  const AwikiMeApp({
    super.key,
    required this.bootstrap,
    this.providerOverrides = const <Override>[],
  });

  final AppBootstrap bootstrap;
  final List<Override> providerOverrides;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(bootstrap.gateway),
        realtimeGatewayProvider.overrideWithValue(bootstrap.realtimeGateway),
        notificationFacadeProvider.overrideWithValue(
          bootstrap.notificationFacade,
        ),
        e2eeFacadeProvider.overrideWithValue(bootstrap.e2eeFacade),
        localePreferenceServiceProvider.overrideWithValue(
          bootstrap.localePreferenceService,
        ),
        ...providerOverrides,
      ],
      child: const _AwikiMeRoot(),
    );
  }
}

class _AwikiMeRoot extends ConsumerWidget {
  const _AwikiMeRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeMode = ref.watch(appLocaleModeProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AwikiMePalette.ivory,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AwikiMePalette.ivory,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: AwikiMePalette.ivory,
      ),
      child: CupertinoApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: localeMode.locale,
        localeResolutionCallback: (locale, supportedLocales) {
          if (locale == null) {
            return const Locale('zh');
          }
          for (final supportedLocale in supportedLocales) {
            if (supportedLocale.languageCode == locale.languageCode) {
              return supportedLocale;
            }
          }
          return const Locale('zh');
        },
        theme: AwikiMeTheme.cupertinoTheme,
        builder: (context, child) {
          return material.Theme(
            data: AwikiMeTheme.materialTheme,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const AppShell(),
      ),
    );
  }
}
