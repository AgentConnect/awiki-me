import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:awiki_me/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart' as material;

import '../presentation/app_shell/app_shell.dart';
import '../presentation/app_shell/providers/app_lifecycle_provider.dart';
import '../presentation/shared/awiki_me_design.dart';
import 'app_orientation.dart';
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
        awikiAccountGatewayProvider.overrideWithValue(bootstrap.accountGateway),
        awikiGatewayProvider.overrideWithValue(bootstrap.gateway),
        realtimeGatewayProvider.overrideWithValue(bootstrap.realtimeGateway),
        notificationFacadeProvider.overrideWithValue(
          bootstrap.notificationFacade,
        ),
        e2eeFacadeProvider.overrideWithValue(bootstrap.e2eeFacade),
        localePreferenceServiceProvider.overrideWithValue(
          bootstrap.localePreferenceService,
        ),
        updateServiceProvider.overrideWithValue(bootstrap.updateService),
        ...providerOverrides,
      ],
      child: const _AwikiMeRoot(),
    );
  }
}

class _AwikiMeRoot extends ConsumerStatefulWidget {
  const _AwikiMeRoot();

  @override
  ConsumerState<_AwikiMeRoot> createState() => _AwikiMeRootState();
}

class _AwikiMeRootState extends ConsumerState<_AwikiMeRoot>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(appLifecycleProvider.notifier).setLifecycle(state);
  }

  @override
  Widget build(BuildContext context) {
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
          return _KeyboardDismissScope(
            child: material.Theme(
              data: AwikiMeTheme.materialTheme,
              child: AppOrientationScope(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          );
        },
        home: const AppShell(),
      ),
    );
  }
}

class _KeyboardDismissScope extends StatelessWidget {
  const _KeyboardDismissScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_isPointerInsideEditable(context, event.position)) {
          return;
        }
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: child,
    );
  }

  bool _isPointerInsideEditable(BuildContext context, Offset globalPosition) {
    var found = false;

    void visit(Element element) {
      if (found) {
        return;
      }
      if (element.widget is EditableText) {
        final renderObject = element.renderObject;
        if (renderObject is RenderBox && renderObject.attached) {
          final localPosition = renderObject.globalToLocal(globalPosition);
          if (renderObject.size.contains(localPosition)) {
            found = true;
            return;
          }
        }
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }
}
