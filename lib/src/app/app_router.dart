import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DialogRoute;
import 'package:flutter/services.dart';

import '../presentation/shared/awiki_me_design.dart';

class AppNavigator {
  const AppNavigator._();

  static const SystemUiOverlayStyle _defaultOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: AwikiMePalette.ivory,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AwikiMePalette.ivory,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: AwikiMePalette.ivory,
  );

  static const SystemUiOverlayStyle _sheetOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Color(0xFFD8D7DC),
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFFD8D7DC),
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Color(0xFFD8D7DC),
  );

  static Future<T?> push<T>(BuildContext context, WidgetBuilder builder) {
    return Navigator.of(
      context,
    ).push<T>(CupertinoPageRoute<T>(builder: builder));
  }

  static Future<T?> pushWithoutAnimation<T>(
    BuildContext context,
    WidgetBuilder builder,
  ) {
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (context, _, __) => builder(context),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  static Future<T?> pushReplacement<T, TO>(
    BuildContext context,
    WidgetBuilder builder,
  ) {
    return Navigator.of(
      context,
    ).pushReplacement<T, TO>(CupertinoPageRoute<T>(builder: builder));
  }

  static Future<T?> showDialog<T>(
    BuildContext context,
    WidgetBuilder builder, {
    bool barrierDismissible = true,
  }) {
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
    SystemChrome.setSystemUIOverlayStyle(_sheetOverlayStyle);
    try {
      return await showCupertinoModalPopup<T>(
        context: context,
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
