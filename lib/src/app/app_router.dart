import 'package:flutter/cupertino.dart';
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

  static Future<T?> push<T>(
    BuildContext context,
    WidgetBuilder builder,
  ) {
    return Navigator.of(context).push<T>(
      CupertinoPageRoute<T>(builder: builder),
    );
  }

  static Future<T?> pushReplacement<T, TO>(
    BuildContext context,
    WidgetBuilder builder,
  ) {
    return Navigator.of(context).pushReplacement<T, TO>(
      CupertinoPageRoute<T>(builder: builder),
    );
  }

  static Future<T?> showDialog<T>(
    BuildContext context,
    WidgetBuilder builder,
  ) {
    return showCupertinoDialog<T>(context: context, builder: builder);
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
