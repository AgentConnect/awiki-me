import 'package:flutter/widgets.dart';

/// Run real background work without waiting for frames disabled by `hidden`.
/// Always return through `inactive` before requesting foreground UI frames.
Future<T> runInHiddenDesktopLifecycle<T>({
  required void Function(AppLifecycleState) transition,
  required Future<T> Function() action,
}) async {
  transition(AppLifecycleState.inactive);
  transition(AppLifecycleState.hidden);
  try {
    return await action();
  } finally {
    transition(AppLifecycleState.inactive);
    transition(AppLifecycleState.resumed);
  }
}
