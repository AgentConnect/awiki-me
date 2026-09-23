import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DialogRoute;
import 'package:flutter/services.dart';

import '../presentation/shared/awiki_me_design.dart';
import '../presentation/shared/responsive_layout.dart';

class AppNavigator {
  const AppNavigator._();

  // The macOS window extends Flutter content behind the native traffic lights.
  // Full-window routes need a top safe inset; the root shell reserves that
  // corner separately for its rail and must not inherit this route-only inset.
  static const double macWindowChromeTopInset = 52;

  static Widget _pageBelowMacWindowChrome(
    BuildContext context,
    WidgetBuilder builder,
  ) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return builder(context);
    }
    final media = MediaQuery.of(context);
    final top = media.padding.top < macWindowChromeTopInset
        ? macWindowChromeTopInset
        : media.padding.top;
    return MediaQuery(
      data: media.copyWith(padding: media.padding.copyWith(top: top)),
      child: Builder(builder: builder),
    );
  }

  static const SystemUiOverlayStyle _defaultOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: AwikiMePalette.canvas,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AwikiMePalette.canvas,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: AwikiMePalette.canvas,
  );

  static const SystemUiOverlayStyle _sheetOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: AwikiMePalette.navigationSurface,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AwikiMePalette.navigationSurface,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: AwikiMePalette.navigationBorder,
  );

  static Future<T?> push<T>(
    BuildContext context,
    WidgetBuilder builder, {
    bool rootNavigator = false,
  }) {
    return Navigator.of(context, rootNavigator: rootNavigator).push<T>(
      CupertinoPageRoute<T>(
        builder: (routeContext) =>
            _pageBelowMacWindowChrome(routeContext, builder),
      ),
    );
  }

  static Future<T?> pushWithoutAnimation<T>(
    BuildContext context,
    WidgetBuilder builder, {
    bool rootNavigator = false,
  }) {
    return Navigator.of(context, rootNavigator: rootNavigator).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (context, _, __) =>
            _pageBelowMacWindowChrome(context, builder),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  static Future<T?> pushReplacement<T, TO>(
    BuildContext context,
    WidgetBuilder builder,
  ) {
    return Navigator.of(context).pushReplacement<T, TO>(
      CupertinoPageRoute<T>(
        builder: (routeContext) =>
            _pageBelowMacWindowChrome(routeContext, builder),
      ),
    );
  }

  static Future<T?> showDialog<T>(
    BuildContext context,
    WidgetBuilder builder, {
    bool barrierDismissible = true,
  }) async {
    if (context.awikiResponsive.isCompact) {
      SystemChrome.setSystemUIOverlayStyle(_sheetOverlayStyle);
      try {
        return await showCupertinoModalPopup<T>(
          context: context,
          barrierColor: const Color(0x66000000),
          barrierDismissible: barrierDismissible,
          semanticsDismissible: true,
          useRootNavigator: true,
          requestFocus: true,
          builder: (dialogContext) =>
              _AppDialogKeyboardDismissScope(child: builder(dialogContext)),
        );
      } finally {
        SystemChrome.setSystemUIOverlayStyle(_defaultOverlayStyle);
      }
    }
    return Navigator.of(context, rootNavigator: true).push<T>(
      DialogRoute<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        barrierColor: const Color(0x66000000),
        builder: (dialogContext) =>
            _AppDialogKeyboardDismissScope(child: builder(dialogContext)),
      ),
    );
  }

  static Future<T?> showSheet<T>(
    BuildContext context,
    WidgetBuilder builder,
  ) async {
    if (context.awikiResponsive.isExpanded) {
      return showDialog<T>(context, builder);
    }
    SystemChrome.setSystemUIOverlayStyle(_sheetOverlayStyle);
    try {
      return await showCupertinoModalPopup<T>(
        context: context,
        barrierColor: const Color(0x57000000),
        semanticsDismissible: true,
        requestFocus: true,
        builder: builder,
      );
    } finally {
      SystemChrome.setSystemUIOverlayStyle(_defaultOverlayStyle);
    }
  }
}

class _AppDialogKeyboardDismissScope extends StatelessWidget {
  const _AppDialogKeyboardDismissScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                Navigator.maybeOf(context)?.maybePop();
                return null;
              },
            ),
          },
          child: Focus(autofocus: true, child: child),
        ),
      ),
    );
  }
}
