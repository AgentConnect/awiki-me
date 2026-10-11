import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppNavigator {
  const AppNavigator._();

  // Full-window macOS routes extend behind the native traffic lights.
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
        pageBuilder: (routeContext, _, __) =>
            _pageBelowMacWindowChrome(routeContext, builder),
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

  /// Shows a modal dialog centered over a dimmed scrim on every layout,
  /// fading and scaling it in rather than sliding a sheet up from the bottom.
  static Future<T?> showDialog<T>(
    BuildContext context,
    WidgetBuilder builder, {
    bool barrierDismissible = true,
  }) {
    return showGeneralDialog<T>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'Dismiss',
      barrierColor: const Color(0x33161616),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, _, __) =>
          _AppDialogKeyboardDismissScope(child: builder(dialogContext)),
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// Menus and pickers share the centered dialog presentation.
  static Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder) {
    return showDialog<T>(context, builder);
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
